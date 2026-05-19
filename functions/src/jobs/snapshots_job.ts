import {onSchedule} from "firebase-functions/v2/scheduler";
import {admin, db, logger} from "../app/firebase";
import {TIME_ZONE} from "../app/config";
import {PortfolioRecord} from "../types";
import {formatDateId, formatHourId} from "../utils/dates";
import {
  toSymbol,
  resolveEventSymbol,
  resolvePriceSymbol,
} from "../utils/symbols";
import {getExchangeRate} from "../services/fx";
import {
  fetchQuotePricesWithReport,
  SymbolFetchFailure,
} from "../services/quotes";
import {applySymbolEvents, fetchSymbolEvents} from "../services/events_service";
import {
  updatePortfolioCurrentPrices,
  calculateTotals,
  recordPortfolioShareHistory,
  sumCashFlowComponents,
} from "../services/portfolio";
import {
  cleanupSnapshots,
  syncTempSnapshotsToIntraday,
  getLastSnapshot,
} from "../services/snapshots";

const SCHEDULER_RETRY_COUNT = 3;
const SCHEDULER_MIN_BACKOFF_SECONDS = 60;
const SCHEDULER_MAX_BACKOFF_SECONDS = 900;
const SCHEDULER_MAX_DOUBLINGS = 4;
const SCHEDULER_TIMEOUT_SECONDS = 540;

export const batchSnapshots = onSchedule(
  {
    schedule: "0 */3 * * *",
    timeZone: TIME_ZONE,
    region: "europe-west1",
    retryCount: SCHEDULER_RETRY_COUNT,
    minBackoffSeconds: SCHEDULER_MIN_BACKOFF_SECONDS,
    maxBackoffSeconds: SCHEDULER_MAX_BACKOFF_SECONDS,
    maxDoublings: SCHEDULER_MAX_DOUBLINGS,
    timeoutSeconds: SCHEDULER_TIMEOUT_SECONDS,
  },
  async () => {
    await runBatch({finalize: false});
  }
);

export const finalizeDailySnapshots = onSchedule(
  {
    schedule: "59 23 * * *",
    timeZone: TIME_ZONE,
    region: "europe-west1",
    retryCount: SCHEDULER_RETRY_COUNT,
    minBackoffSeconds: SCHEDULER_MIN_BACKOFF_SECONDS,
    maxBackoffSeconds: SCHEDULER_MAX_BACKOFF_SECONDS,
    maxDoublings: SCHEDULER_MAX_DOUBLINGS,
    timeoutSeconds: SCHEDULER_TIMEOUT_SECONDS,
  },
  async () => {
    await runBatch({finalize: true});
  }
);

/**
 * Runs the scheduled batch snapshot job.
 *
 * @param {object} options Job options.
 * @param {boolean} options.finalize Whether to run end-of-day cleanup.
 * @return {Promise<void>} Promise resolved when job completes.
 */
async function runBatch(
  options: { finalize: boolean }
): Promise<void> {
  const startedAt = Date.now();
  const now = new Date();
  const dateId = formatDateId(now);
  const hourId = formatHourId(now);
  const cleanupCutoff = new Date(now.getTime() - 24 * 60 * 60 * 1000);

  logger.info("Batch snapshot start", {
    finalize: options.finalize,
    dateId: dateId,
    hourId: hourId,
  });

  try {
    const exchangeRate = await getExchangeRate();
    const usersSnapshot = await db.collection("usernames").get();

    logger.info("Users loaded", {count: usersSnapshot.size});

    if (usersSnapshot.empty) {
      logger.warn("No users found in usernames collection.");
      return;
    }

    const userPortfolios = new Map<string, PortfolioRecord[]>();
    const priceSymbols = new Set<string>();
    const eventSymbols = new Set<string>();

    const portfolioEntries = await Promise.all(
      usersSnapshot.docs.map(async (userDoc) => {
        const portfolioSnap = await userDoc.ref.collection("portfolio").get();
        const records = portfolioSnap.docs.map((doc) => {
          return {ref: doc.ref, data: doc.data()};
        });
        return {username: userDoc.id, records: records};
      })
    );

    for (const entry of portfolioEntries) {
      userPortfolios.set(entry.username, entry.records);

      for (const record of entry.records) {
        const priceSymbol = resolvePriceSymbol(record.data);
        if (priceSymbol) {
          priceSymbols.add(priceSymbol);
        }

        const eventSymbol = resolveEventSymbol(record.data);
        if (eventSymbol) {
          eventSymbols.add(eventSymbol);
        }
      }
    }

    logger.info("Symbols prepared", {
      priceSymbols: priceSymbols.size,
      eventSymbols: eventSymbols.size,
    });

    const quoteReport = await fetchQuotePricesWithReport(
      Array.from(priceSymbols)
    );
    const prices = quoteReport.prices;
    const failedSymbolCount = Object.keys(quoteReport.failedSymbols).length;
    logger.info("Quote fetch completed", {
      requestedSymbols: priceSymbols.size,
      resolvedSymbols: Object.keys(prices).length,
      failedSymbols: failedSymbolCount,
      failedChunks: quoteReport.failedChunks,
      successfulChunks: quoteReport.successfulChunks,
      retriedChunks: quoteReport.retriedChunks,
    });

    if (failedSymbolCount > 0) {
      logger.warn("Quote fetch has stale-symbol candidates", {
        failedSymbols: failedSymbolCount,
        sampleFailedSymbols: Object.keys(
          quoteReport.failedSymbols
        ).slice(0, 10),
      });
    }

    const eventsBySymbol = await fetchSymbolEvents(
      Array.from(eventSymbols),
      now
    );

    let processed = 0;
    let failedUsers = 0;
    const failedSamples: Array<{username: string; reason: string}> = [];
    for (const [username, records] of userPortfolios.entries()) {
      try {
        const userRef = db.collection("usernames").doc(username);
        const tempId = `${dateId}_${hourId}`;

        await recordPortfolioShareHistory(records, now, tempId);

        await applySymbolEvents(
          userRef,
          records,
          eventsBySymbol,
          exchangeRate
        );

        await markPortfolioPriceHealth(
          records,
          prices,
          quoteReport.failedSymbols
        );

        await updatePortfolioCurrentPrices(records, prices);

        const totals = calculateTotals(records, prices, exchangeRate);
        const lastSnapshot = await getLastSnapshot(userRef, dateId);
        const lastDate = lastSnapshot ? lastSnapshot.date : null;
        const flowComponents = await sumCashFlowComponents(
          userRef,
          lastDate,
          now,
          exchangeRate
        );
        const externalCashFlow = flowComponents.externalFlowTry;
        const dividendAmount = flowComponents.dividendYieldTry;
        const adjustedEndValueTry = totals.totalTry + dividendAmount;
        const performanceImpact = adjustedEndValueTry - totals.totalTry;

        const previousTotal = lastSnapshot ? lastSnapshot.totalTry : 0;
        const previousCumulative = lastSnapshot ?
          lastSnapshot.cumulativeTwr :
          0;

        const denominator = previousTotal + externalCashFlow;

        let periodReturn = 0;
        let cumulativeTwr = previousCumulative;
        if (denominator > 0) {
          periodReturn = (adjustedEndValueTry - denominator) / denominator;
          cumulativeTwr = (1 + previousCumulative) * (1 + periodReturn) - 1;
        }

        const snapshotPayload = {
          date: admin.firestore.Timestamp.fromDate(now),
          date_id: dateId,
          hour_id: hourId,
          total_value_try: totals.totalTry,
          total_value_usd: totals.totalUsd,
          daily_return: periodReturn,
          period_return: periodReturn,
          cumulative_twr: cumulativeTwr,
          net_cash_flow: externalCashFlow,
          dividend_amount: dividendAmount,
          adjusted_price: adjustedEndValueTry,
          performance_impact: performanceImpact,
        };

        if (!options.finalize) {
          await userRef
            .collection("temp_hourly_snapshots")
            .doc(tempId)
            .set(snapshotPayload, {merge: true});
        }

        await userRef
          .collection("performance_intraday")
          .doc(tempId)
          .set(
            {
              date: snapshotPayload.date,
              date_id: snapshotPayload.date_id,
              hour_id: snapshotPayload.hour_id,
              total_value_try: snapshotPayload.total_value_try,
              total_value_usd: snapshotPayload.total_value_usd,
              daily_return: snapshotPayload.daily_return,
              period_return: snapshotPayload.period_return,
              cumulative_twr: snapshotPayload.cumulative_twr,
              dividend_amount: snapshotPayload.dividend_amount,
              adjusted_price: snapshotPayload.adjusted_price,
              performance_impact: snapshotPayload.performance_impact,
            },
            {merge: true}
          );

        await userRef
          .collection("performance_history")
          .doc(dateId)
          .set(
            {
              ...snapshotPayload,
              last_snapshot_at: admin.firestore.Timestamp.fromDate(now),
            },
            {merge: true}
          );

        await syncTempSnapshotsToIntraday(userRef, cleanupCutoff);
        await cleanupSnapshots(userRef, "temp_hourly_snapshots", cleanupCutoff);
        await cleanupSnapshots(userRef, "performance_intraday", cleanupCutoff);

        processed += 1;
      } catch (error) {
        failedUsers += 1;
        const reason = error instanceof Error ? error.message : String(error);
        logger.error("Snapshot processing failed for user", {
          username: username,
          reason: reason,
        });
        if (failedSamples.length < 5) {
          failedSamples.push({username: username, reason: reason});
        }
      }
    }

    if (processed === 0) {
      throw new Error(
        "Batch snapshot failed for all users. " +
        `failedUsers=${failedUsers}`
      );
    }

    if (failedUsers > 0) {
      logger.warn("Batch snapshot completed with partial failures", {
        processedUsers: processed,
        failedUsers: failedUsers,
        failedSamples: failedSamples,
      });
    }

    logger.info("Batch snapshot finished", {
      processedUsers: processed,
      failedUsers: failedUsers,
      finalize: options.finalize,
      durationMs: Date.now() - startedAt,
    });
  } catch (error) {
    logger.error("Batch snapshot failed", error as Error);
    throw error;
  }
}

type PriceHealth = {
  stale: boolean;
  lastFetchError: string | null;
};

/**
 * Marks portfolio docs with stale-data fetch diagnostics.
 *
 * @param {PortfolioRecord[]} records Portfolio docs.
 * @param {Record<string, number>} prices Resolved live prices.
 * @param {Record<string, SymbolFetchFailure>} failedSymbols Failure map.
 * @return {Promise<void>} Promise resolved when writes complete.
 */
async function markPortfolioPriceHealth(
  records: PortfolioRecord[],
  prices: Record<string, number>,
  failedSymbols: Record<string, SymbolFetchFailure>
): Promise<void> {
  let batch = db.batch();
  let pending = 0;

  for (const record of records) {
    const health = resolvePriceHealth(record.data, prices, failedSymbols);
    if (!health) continue;

    const currentStale = record.data["stale_data"] === true;
    const currentErrorValue = record.data["last_fetch_error"];
    const currentError = currentErrorValue == null ?
      null :
      currentErrorValue.toString();

    if (currentStale === health.stale &&
      currentError === health.lastFetchError) {
      continue;
    }

    const payload: Record<string, unknown> = {
      stale_data: health.stale,
    };

    if (health.stale) {
      payload["last_fetch_error"] = health.lastFetchError;
    } else {
      payload["last_fetch_error"] = admin.firestore.FieldValue.delete();
    }

    batch.set(record.ref, payload, {merge: true});
    record.data["stale_data"] = health.stale;
    if (health.stale && health.lastFetchError) {
      record.data["last_fetch_error"] = health.lastFetchError;
    } else {
      delete record.data["last_fetch_error"];
    }

    pending += 1;
    if (pending >= 450) {
      await batch.commit();
      batch = db.batch();
      pending = 0;
    }
  }

  if (pending > 0) {
    await batch.commit();
  }
}

/**
 * Resolves stale/fresh marker for a portfolio row.
 *
 * @param {Record<string, unknown>} data Portfolio row data.
 * @param {Record<string, number>} prices Resolved live prices.
 * @param {Record<string, SymbolFetchFailure>} failedSymbols Failure map.
 * @return {PriceHealth | null} Marker payload or null when symbol missing.
 */
function resolvePriceHealth(
  data: Record<string, unknown>,
  prices: Record<string, number>,
  failedSymbols: Record<string, SymbolFetchFailure>
): PriceHealth | null {
  const canonicalPriceSymbol = resolvePriceSymbol(data);
  if (!canonicalPriceSymbol) return null;
  const rawSymbol = toSymbol(data["symbol"]);
  const candidateSymbols = Array.from(
    new Set(
      [
        canonicalPriceSymbol,
        rawSymbol ? rawSymbol.toUpperCase() : null,
      ].filter((symbol): symbol is string => Boolean(symbol))
    )
  );

  const hasFreshPrice = candidateSymbols.some((symbol) => {
    const price = prices[symbol];
    return typeof price === "number" && price > 0;
  });

  if (hasFreshPrice) {
    return {
      stale: false,
      lastFetchError: null,
    };
  }

  const failure = candidateSymbols
    .map((symbol) => failedSymbols[symbol])
    .find((entry) => Boolean(entry));

  if (!failure) {
    return {
      stale: true,
      lastFetchError: "NO_DATA",
    };
  }

  const codeText = failure.status == null ?
    failure.errorType :
    `HTTP_${failure.status}`;

  return {
    stale: true,
    lastFetchError: codeText,
  };
}
