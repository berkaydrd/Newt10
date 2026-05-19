import {admin, db} from "../app/firebase";
import {SymbolEvents, PortfolioRecord} from "../types";
import {formatDateId} from "../utils/dates";
import {toNumber} from "../utils/numbers";
import {toEvent, parseSplitRatio, ratioText} from "../utils/events";
import {toSymbol, resolveEventSymbol} from "../utils/symbols";

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

    const shares = toNumber(data["shares"]);
    const currency = (data["currency"] ?? "").toString().toUpperCase();

    if (events.dividends) {
      for (const [key, rawEvent] of Object.entries(events.dividends)) {
        const event = toEvent(rawEvent);
        if (!event) continue;
        const eventId = `dividend_${key}`;
        if (await isProcessed(record.ref, eventId)) continue;

        const amountPerShare = toNumber(event["amount"]);
        const ts = toNumber(event["date"]);
        const eventDate = new Date(ts * 1000);
        const totalRaw = amountPerShare * shares;
        const amountTry = currency === "USD" ?
          totalRaw * exchangeRate :
          totalRaw;

        if (amountTry > 0) {
          await userRef.collection("cash_flows").add({
            date: admin.firestore.Timestamp.fromDate(eventDate),
            amount_try: amountTry,
            amount_currency: totalRaw,
            currency: currency,
            type: "dividend",
          });

          await userRef.collection("notifications").add({
            type: "dividend",
            symbol: symbol,
            amount_try: amountTry,
            event_date: admin.firestore.Timestamp.fromDate(eventDate),
            created_at: admin.firestore.Timestamp.now(),
            event_id: eventId,
            read: false,
          });
        }

        await markProcessed(record.ref, eventId, {
          type: "dividend",
          date: admin.firestore.Timestamp.fromDate(eventDate),
          amount_per_share: amountPerShare,
          shares: shares,
          total_amount_try: amountTry,
          currency: currency,
        });
      }
    }

    if (events.splits) {
      for (const [key, rawEvent] of Object.entries(events.splits)) {
        const event = toEvent(rawEvent);
        if (!event) continue;
        const eventId = `split_${key}`;
        if (await isProcessed(record.ref, eventId)) continue;

        const ts = toNumber(event["date"]);
        const eventDate = new Date(ts * 1000);
        const ratio = parseSplitRatio(event);
        if (ratio <= 0 || ratio === 1) continue;

        const currentShares = toNumber(data["shares"]);
        const purchasePrice = toNumber(data["purchase_price"]);
        const currentPrice = toNumber(data["current_price"]);

        const newShares = currentShares * ratio;
        const newPurchasePrice = purchasePrice / ratio;
        const newCurrentPrice = currentPrice / ratio;

        await record.ref.update({
          shares: newShares,
          purchase_price: newPurchasePrice,
          current_price: newCurrentPrice,
        });

        await userRef.collection("notifications").add({
          type: "split",
          symbol: symbol,
          ratio_text: ratioText(event, ratio),
          event_date: admin.firestore.Timestamp.fromDate(eventDate),
          created_at: admin.firestore.Timestamp.now(),
          event_id: eventId,
          read: false,
        });

        await markProcessed(record.ref, eventId, {
          type: "split",
          date: admin.firestore.Timestamp.fromDate(eventDate),
          ratio: ratio,
          ratio_text: ratioText(event, ratio),
        });

        data["shares"] = newShares;
        data["purchase_price"] = newPurchasePrice;
        data["current_price"] = newCurrentPrice;
      }
    }
  }
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

  const response = await globalThis.fetch(url, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    },
  });

  if (!response.ok) return {};
  const data = (await response.json()) as {
    chart?: { result?: Array<{ events?: SymbolEvents }> };
  };
  const events = data.chart?.result?.[0]?.events;
  if (!events) return {};
  return {
    dividends: events.dividends ?? {},
    splits: events.splits ?? {},
  };
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
