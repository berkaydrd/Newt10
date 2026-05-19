import {onSchedule} from "firebase-functions/v2/scheduler";
import {admin, db, logger} from "../app/firebase";
import {TIME_ZONE} from "../app/config";
import {PortfolioRecord} from "../types";
import {formatDateId, formatHourId} from "../utils/dates";
import {toSymbol, resolveEventSymbol} from "../utils/symbols";
import {getExchangeRate} from "../services/fx";
import {fetchQuotePrices} from "../services/quotes";
import {applySymbolEvents, fetchSymbolEvents} from "../services/events_service";
import {
  updatePortfolioCurrentPrices,
  calculateTotals,
  sumCashFlows,
} from "../services/portfolio";
import {
  cleanupSnapshots,
  syncTempSnapshotsToIntraday,
  getLastSnapshot,
} from "../services/snapshots";

export const batchSnapshots = onSchedule(
  {
    schedule: "0 */3 * * *",
    timeZone: TIME_ZONE,
    region: "europe-west1",
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

    for (const userDoc of usersSnapshot.docs) {
      const portfolioSnap = await userDoc.ref.collection("portfolio").get();
      const records = portfolioSnap.docs.map((doc) => {
        return {ref: doc.ref, data: doc.data()};
      });
      userPortfolios.set(userDoc.id, records);

      for (const record of records) {
        const rawSymbol = toSymbol(record.data["symbol"]);
        if (!rawSymbol) continue;
        const upper = rawSymbol.toUpperCase();
        priceSymbols.add(upper);
        if (!upper.endsWith(".IS")) {
          priceSymbols.add(`${upper}.IS`);
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

    const prices = await fetchQuotePrices(Array.from(priceSymbols));
    const eventsBySymbol = await fetchSymbolEvents(
      Array.from(eventSymbols),
      now
    );

    let processed = 0;
    for (const [username, records] of userPortfolios.entries()) {
      const userRef = db.collection("usernames").doc(username);

      await applySymbolEvents(
        userRef,
        records,
        eventsBySymbol,
        exchangeRate
      );

      await updatePortfolioCurrentPrices(records, prices);

      const totals = calculateTotals(records, prices, exchangeRate);
      const lastSnapshot = await getLastSnapshot(userRef, dateId);
      const lastDate = lastSnapshot ? lastSnapshot.date : null;
      const cashFlow = await sumCashFlows(userRef, lastDate, now, exchangeRate);

      const previousTotal = lastSnapshot ? lastSnapshot.totalTry : 0;
      const previousCumulative = lastSnapshot ? lastSnapshot.cumulativeTwr : 0;

      const denominator = previousTotal + cashFlow;

      let periodReturn = 0;
      let cumulativeTwr = previousCumulative;
      if (denominator > 0) {
        periodReturn = (totals.totalTry - denominator) / denominator;
        cumulativeTwr = (1 + previousCumulative) * (1 + periodReturn) - 1;
      }

      const tempId = `${dateId}_${hourId}`;
      const snapshotPayload = {
        date: admin.firestore.Timestamp.fromDate(now),
        date_id: dateId,
        hour_id: hourId,
        total_value_try: totals.totalTry,
        total_value_usd: totals.totalUsd,
        daily_return: periodReturn,
        period_return: periodReturn,
        cumulative_twr: cumulativeTwr,
        net_cash_flow: cashFlow,
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
    }

    logger.info("Batch snapshot finished", {
      processedUsers: processed,
      finalize: options.finalize,
    });
  } catch (error) {
    logger.error("Batch snapshot failed", error as Error);
    throw error;
  }
}
