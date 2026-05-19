import {admin, db, logger} from "../app/firebase";
import {SymbolEvents, PortfolioRecord} from "../types";
import {formatDateId} from "../utils/dates";
import {toNumber} from "../utils/numbers";
import {toEvent, parseSplitRatio, ratioText} from "../utils/events";
import {toSymbol, resolveEventSymbol} from "../utils/symbols";

const EVENT_RETRY_ATTEMPTS = 3;
const EVENT_RETRY_BASE_DELAY_MS = 800;
const EVENT_REQUEST_TIMEOUT_MS = 10000;

type DividendEntitlement = {
  shares: number;
  source: "shares_history" | "split_adjusted_fallback";
};

type SplitApplyResult = {
  applied: boolean;
  newShares: number;
  newPurchasePrice: number;
  newCurrentPrice: number;
};

/**
 * Fetches and applies dividend/split events to user portfolios.
 *
 * @param {admin.firestore.DocumentReference} userRef User document ref.
 * @param {PortfolioRecord[]} records Portfolio docs.
 * @param {Record<string, SymbolEvents>} eventsBySymbol Events by symbol.
 * @param {number} exchangeRate USD/TRY rate.
 * @return {Promise<void>} Promise resolved when done.
 */
export async function applySymbolEvents(
  userRef: admin.firestore.DocumentReference,
  records: PortfolioRecord[],
  eventsBySymbol: Record<string, SymbolEvents>,
  exchangeRate: number
): Promise<void> {
  for (const record of records) {
    const data = record.data;
    const symbol = toSymbol(data["symbol"]);
    if (!symbol) continue;

    const eventSymbol = resolveEventSymbol(data);
    if (!eventSymbol) continue;
    const events = eventsBySymbol[eventSymbol];
    if (!events) continue;

    const currency = (data["currency"] ?? "").toString().toUpperCase();

    if (events.dividends) {
      for (const [key, rawEvent] of Object.entries(events.dividends)) {
        const event = toEvent(rawEvent);
        if (!event) continue;
        const eventId = `dividend_${key}`;
        const amountPerShare = toNumber(event["amount"]);
        if (amountPerShare <= 0) continue;
        const ts = toNumber(event["date"]);
        if (ts <= 0) continue;
        const eventDate = new Date(ts * 1000);
        const entitlement = await resolveDividendEntitlement(
          record.ref,
          toNumber(data["shares"]),
          eventDate
        );
        const entitledShares = entitlement.shares;
        const totalRaw = amountPerShare * entitledShares;
        const amountTry = currency === "USD" ?
          totalRaw * exchangeRate :
          totalRaw;
        const eventTs = admin.firestore.Timestamp.fromDate(eventDate);
        const flowDocId = `${record.ref.id}_${eventId}`;
        const processedRef = record.ref
          .collection("processed_events")
          .doc(eventId);
        const cashFlowRef = userRef.collection("cash_flows").doc(flowDocId);
        const notificationRef = userRef
          .collection("notifications")
          .doc(flowDocId);

        await db.runTransaction(async (transaction) => {
          const processedDoc = await transaction.get(processedRef);
          if (processedDoc.exists) return;

          transaction.set(processedRef, {
            type: "dividend",
            date: eventTs,
            event_date: eventTs,
            amount_per_share: amountPerShare,
            shares: entitledShares,
            total_amount_try: amountTry,
            currency: currency,
            entitlement_source: entitlement.source,
            dividend_amount: amountTry,
            performance_impact: amountTry,
            adjusted_price: null,
            processed_at: admin.firestore.FieldValue.serverTimestamp(),
          });

          if (amountTry <= 0 || entitledShares <= 0) {
            return;
          }

          transaction.set(cashFlowRef, {
            date: eventTs,
            amount_try: amountTry,
            amount_currency: totalRaw,
            currency: currency,
            type: "dividend",
            event_id: eventId,
            stock_ref_id: record.ref.id,
            dividend_amount: amountTry,
            performance_impact: amountTry,
            adjusted_price: null,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
          }, {merge: true});

          transaction.set(notificationRef, {
            type: "dividend",
            symbol: symbol,
            amount_try: amountTry,
            event_date: eventTs,
            created_at: admin.firestore.FieldValue.serverTimestamp(),
            event_id: eventId,
            read: false,
            dividend_amount: amountTry,
            performance_impact: amountTry,
            adjusted_price: null,
          }, {merge: true});
        });
      }
    }

    if (events.splits) {
      for (const [key, rawEvent] of Object.entries(events.splits)) {
        const event = toEvent(rawEvent);
        if (!event) continue;
        const eventId = `split_${key}`;

        const ts = toNumber(event["date"]);
        if (ts <= 0) continue;
        const eventDate = new Date(ts * 1000);
        const ratio = parseSplitRatio(event);
        if (ratio <= 0 || ratio === 1) continue;
        const ratioLabel = ratioText(event, ratio);

        const splitResult = await applySplitAtomically(
          record.ref,
          eventId,
          eventDate,
          ratio,
          ratioLabel
        );

        if (!splitResult.applied) continue;

        await userRef
          .collection("notifications")
          .doc(`${record.ref.id}_${eventId}`)
          .set(
            {
              type: "split",
              symbol: symbol,
              ratio_text: ratioLabel,
              event_date: admin.firestore.Timestamp.fromDate(eventDate),
              created_at: admin.firestore.FieldValue.serverTimestamp(),
              event_id: eventId,
              read: false,
            },
            {merge: true}
          );

        data["shares"] = splitResult.newShares;
        data["purchase_price"] = splitResult.newPurchasePrice;
        data["current_price"] = splitResult.newCurrentPrice;
      }
    }
  }
}

/**
 * Resolves share entitlement for a dividend ex-date.
 *
 * @param {admin.firestore.DocumentReference} stockRef Stock document ref.
 * @param {number} fallbackShares Current shares fallback.
 * @param {Date} eventDate Dividend event date.
 * @return {Promise<DividendEntitlement>} Entitled share result.
 */
async function resolveDividendEntitlement(
  stockRef: admin.firestore.DocumentReference,
  fallbackShares: number,
  eventDate: Date
): Promise<DividendEntitlement> {
  const eventTs = admin.firestore.Timestamp.fromDate(eventDate);
  const historySnap = await stockRef
    .collection("shares_history")
    .where("date", "<=", eventTs)
    .orderBy("date", "desc")
    .limit(1)
    .get();

  if (!historySnap.empty) {
    const shares = toNumber(historySnap.docs[0].data()["shares"]);
    return {
      shares: Math.max(0, shares),
      source: "shares_history",
    };
  }

  const estimatedShares = await estimateSharesWithSplitBackfill(
    stockRef,
    fallbackShares,
    eventDate
  );
  return {
    shares: Math.max(0, estimatedShares),
    source: "split_adjusted_fallback",
  };
}

/**
 * Estimates historical shares by reversing splits after event date.
 *
 * @param {admin.firestore.DocumentReference} stockRef Stock document ref.
 * @param {number} currentShares Current shares.
 * @param {Date} eventDate Event date.
 * @return {Promise<number>} Estimated shares at event date.
 */
async function estimateSharesWithSplitBackfill(
  stockRef: admin.firestore.DocumentReference,
  currentShares: number,
  eventDate: Date
): Promise<number> {
  let estimatedShares = currentShares;
  if (estimatedShares <= 0) return 0;

  const processedSnap = await stockRef.collection("processed_events").get();
  for (const doc of processedSnap.docs) {
    const data = doc.data();
    if ((data["type"] ?? "").toString() !== "split") continue;
    const eventTs = data["date"] as admin.firestore.Timestamp | undefined;
    if (!eventTs) continue;
    if (eventTs.toDate().getTime() <= eventDate.getTime()) continue;

    const ratio = toNumber(data["ratio"]);
    if (ratio <= 0) continue;
    estimatedShares /= ratio;
  }

  return estimatedShares;
}

/**
 * Applies split update and processed marker atomically.
 *
 * @param {admin.firestore.DocumentReference} stockRef Stock document ref.
 * @param {string} eventId Event id.
 * @param {Date} eventDate Event date.
 * @param {number} ratio Split ratio.
 * @param {string} ratioLabel Ratio text.
 * @return {Promise<SplitApplyResult>} Split application result.
 */
async function applySplitAtomically(
  stockRef: admin.firestore.DocumentReference,
  eventId: string,
  eventDate: Date,
  ratio: number,
  ratioLabel: string
): Promise<SplitApplyResult> {
  const result = await db.runTransaction(async (transaction) => {
    const processedRef = stockRef.collection("processed_events").doc(eventId);
    const processedDoc = await transaction.get(processedRef);
    if (processedDoc.exists) {
      return {
        applied: false,
        newShares: 0,
        newPurchasePrice: 0,
        newCurrentPrice: 0,
      };
    }

    const stockDoc = await transaction.get(stockRef);
    if (!stockDoc.exists) {
      transaction.set(processedRef, {
        type: "split",
        skipped: true,
        skip_reason: "stock_document_missing",
        date: admin.firestore.Timestamp.fromDate(eventDate),
        ratio: ratio,
        ratio_text: ratioLabel,
        processed_at: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {
        applied: false,
        newShares: 0,
        newPurchasePrice: 0,
        newCurrentPrice: 0,
      };
    }

    const data = stockDoc.data() as Record<string, unknown>;
    const currentShares = toNumber(data["shares"]);
    const purchasePrice = toNumber(data["purchase_price"]);
    const currentPrice = toNumber(data["current_price"]);
    const newShares = currentShares * ratio;
    const newPurchasePrice = purchasePrice / ratio;
    const newCurrentPrice = currentPrice / ratio;

    transaction.update(stockRef, {
      shares: newShares,
      purchase_price: newPurchasePrice,
      current_price: newCurrentPrice,
    });

    transaction.set(processedRef, {
      type: "split",
      date: admin.firestore.Timestamp.fromDate(eventDate),
      ratio: ratio,
      ratio_text: ratioLabel,
      processed_at: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      applied: true,
      newShares: newShares,
      newPurchasePrice: newPurchasePrice,
      newCurrentPrice: newCurrentPrice,
    };
  });

  return result;
}

/**
 * Fetches dividend/split events for each symbol (cached per day).
 *
 * @param {string[]} symbols Symbol list.
 * @param {Date} now Current timestamp.
 * @return {Promise<Record<string, SymbolEvents>>} Events per symbol.
 */
export async function fetchSymbolEvents(
  symbols: string[],
  now: Date
): Promise<Record<string, SymbolEvents>> {
  const results: Record<string, SymbolEvents> = {};

  for (const symbol of symbols) {
    const docRef = db.collection("symbol_events").doc(symbol);
    const doc = await docRef.get();
    const cached = doc.exists ? doc.data() : null;
    const cachedDate = cached?.last_checked as
      admin.firestore.Timestamp | undefined;

    if (cachedDate) {
      const cachedId = formatDateId(cachedDate.toDate());
      const nowId = formatDateId(now);
      if (cachedId === nowId && cached?.events) {
        results[symbol] = cached.events as SymbolEvents;
        continue;
      }
    }

    const events = await fetchSymbolEventsFromApi(symbol);
    results[symbol] = events;
    await docRef.set(
      {
        last_checked: admin.firestore.Timestamp.fromDate(now),
        events: events,
      },
      {merge: true}
    );
  }

  return results;
}

/**
 * Calls Yahoo chart API for dividend and split events.
 *
 * @param {string} symbol Yahoo symbol.
 * @return {Promise<SymbolEvents>} Parsed events.
 */
export async function fetchSymbolEventsFromApi(
  symbol: string
): Promise<SymbolEvents> {
  const url =
    `https://query1.finance.yahoo.com/v8/finance/chart/${symbol}` +
    "?interval=1d&range=5d&events=div,splits";

  const userAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  let lastStatus: number | null = null;
  let lastError: string | null = null;

  for (let attempt = 1; attempt <= EVENT_RETRY_ATTEMPTS; attempt += 1) {
    try {
      const response = await fetchWithTimeout(url, userAgent);
      lastStatus = response.status;

      if (!response.ok) {
        lastError = `HTTP ${response.status}`;
        if (attempt < EVENT_RETRY_ATTEMPTS &&
          isRetryableStatus(response.status)) {
          await delayMs(getRetryDelayMs(attempt));
          continue;
        }
        logger.warn("Event API request failed", {
          symbol: symbol,
          status: response.status,
          attempts: attempt,
        });
        return {};
      }

      const data = (await response.json()) as {
        chart?: { result?: Array<{ events?: SymbolEvents }> };
      };
      const events = data.chart?.result?.[0]?.events;
      if (!events) return {};
      return {
        dividends: events.dividends ?? {},
        splits: events.splits ?? {},
      };
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      if (attempt < EVENT_RETRY_ATTEMPTS) {
        await delayMs(getRetryDelayMs(attempt));
        continue;
      }
    }
  }

  logger.error("Event API request exhausted retries", {
    symbol: symbol,
    status: lastStatus,
    error: lastError,
    attempts: EVENT_RETRY_ATTEMPTS,
  });
  return {};
}

/**
 * Calls fetch with timeout for event API requests.
 *
 * @param {string} url Request URL.
 * @param {string} userAgent Request user-agent.
 * @return {Promise<Response>} Fetch response.
 */
async function fetchWithTimeout(
  url: string,
  userAgent: string
): Promise<Response> {
  const controller = new AbortController();
  const timeout = setTimeout(
    () => controller.abort(),
    EVENT_REQUEST_TIMEOUT_MS
  );

  try {
    return await globalThis.fetch(url, {
      headers: {
        "User-Agent": userAgent,
      },
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }
}

/**
 * Returns true for transient status codes.
 *
 * @param {number} status HTTP status code.
 * @return {boolean} True if retryable.
 */
function isRetryableStatus(status: number): boolean {
  return status === 408 || status === 429 || status >= 500;
}

/**
 * Calculates exponential backoff delay.
 *
 * @param {number} attempt Attempt number.
 * @return {number} Delay in milliseconds.
 */
function getRetryDelayMs(attempt: number): number {
  const exp = Math.max(0, attempt - 1);
  return EVENT_RETRY_BASE_DELAY_MS * Math.pow(2, exp);
}

/**
 * Delays execution for given milliseconds.
 *
 * @param {number} ms Delay in milliseconds.
 * @return {Promise<void>} Promise resolved after delay.
 */
async function delayMs(ms: number): Promise<void> {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Checks if a stock event was already processed.
 *
 * @param {admin.firestore.DocumentReference} stockRef Stock document ref.
 * @param {string} eventId Event id.
 * @return {Promise<boolean>} True if processed.
 */
export async function isProcessed(
  stockRef: admin.firestore.DocumentReference,
  eventId: string
): Promise<boolean> {
  const doc = await stockRef
    .collection("processed_events")
    .doc(eventId)
    .get();
  return doc.exists;
}

/**
 * Marks a stock event as processed.
 *
 * @param {admin.firestore.DocumentReference} stockRef Stock document ref.
 * @param {string} eventId Event id.
 * @param {Record<string, unknown>} data Event metadata.
 * @return {Promise<void>} Promise resolved when done.
 */
export async function markProcessed(
  stockRef: admin.firestore.DocumentReference,
  eventId: string,
  data: Record<string, unknown>
): Promise<void> {
  await stockRef.collection("processed_events").doc(eventId).set({
    ...data,
    processed_at: admin.firestore.Timestamp.now(),
  });
}
