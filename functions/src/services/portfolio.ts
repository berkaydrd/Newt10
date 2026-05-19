import {admin, db} from "../app/firebase";
import {DEFAULT_FX} from "../app/config";
import {PortfolioRecord, PriceMap, SnapshotInfo} from "../types";
import {toNumber} from "../utils/numbers";
import {toSymbol} from "../utils/symbols";
import {resolveLatestPrice} from "./quotes";

export type CashFlowComponents = {
  externalFlowTry: number;
  dividendYieldTry: number;
};

/**
 * Updates portfolio current_price using latest fetched prices.
 *
 * @param {PortfolioRecord[]} records Portfolio docs.
 * @param {PriceMap} prices Live price map.
 * @return {Promise<void>} Promise resolved when updates finish.
 */
export async function updatePortfolioCurrentPrices(
  records: PortfolioRecord[],
  prices: PriceMap
): Promise<void> {
  let batch = db.batch();
  let pending = 0;

  for (const record of records) {
    const data = record.data;
    const price = resolveLatestPrice(data, prices);
    if (price <= 0) continue;

    batch.update(record.ref, {current_price: price});
    data["current_price"] = price;
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
 * Sums cash flows between (start, end].
 *
 * @param {admin.firestore.DocumentReference} userRef User document ref.
 * @param {Date | null} start Exclusive start time or null.
 * @param {Date} end Inclusive end time.
 * @param {number} exchangeRate USD/TRY exchange rate.
 * @return {Promise<number>} Total cash flow in TRY.
 */
export async function sumCashFlows(
  userRef: admin.firestore.DocumentReference,
  start: Date | null,
  end: Date,
  exchangeRate: number
): Promise<number> {
  const components = await sumCashFlowComponents(
    userRef,
    start,
    end,
    exchangeRate
  );
  return components.externalFlowTry;
}

/**
 * Splits period cash movements into external flows and dividend yield.
 *
 * @param {admin.firestore.DocumentReference} userRef User document ref.
 * @param {Date | null} start Exclusive start time or null.
 * @param {Date} end Inclusive end time.
 * @param {number} exchangeRate USD/TRY exchange rate.
 * @return {Promise<CashFlowComponents>} Cash flow components in TRY.
 */
export async function sumCashFlowComponents(
  userRef: admin.firestore.DocumentReference,
  start: Date | null,
  end: Date,
  exchangeRate: number
): Promise<CashFlowComponents> {
  let query = userRef.collection("cash_flows").where("date", "<=", end);
  if (start) {
    query = query.where("date", ">", start);
  }
  const snapshot = await query.get();

  let externalFlowTry = 0;
  let dividendYieldTry = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const amount = toCashFlowTryAmount(data, exchangeRate);
    const type = (data["type"] ?? "").toString();

    if (type === "dividend") {
      dividendYieldTry += amount;
      continue;
    }

    if (type === "withdrawal") {
      externalFlowTry -= amount;
      continue;
    }

    externalFlowTry += amount;
  }

  return {
    externalFlowTry: externalFlowTry,
    dividendYieldTry: dividendYieldTry,
  };
}

/**
 * Calculates portfolio totals in TRY and USD.
 *
 * @param {PortfolioRecord[]} records Portfolio docs.
 * @param {PriceMap} prices Live price map.
 * @param {number} exchangeRate USD/TRY exchange rate.
 * @return {{totalTry: number, totalUsd: number}} Totals in TRY and USD.
 */
export function calculateTotals(
  records: PortfolioRecord[],
  prices: PriceMap,
  exchangeRate: number
): { totalTry: number; totalUsd: number } {
  let trySum = 0;
  let usdSum = 0;
  const safeRate = exchangeRate > 0 ? exchangeRate : DEFAULT_FX;

  for (const record of records) {
    const data = record.data;
    const rawSymbol = toSymbol(data["symbol"]);
    if (!rawSymbol) continue;

    const symbolUpper = rawSymbol.toUpperCase();
    const storedCurrency =
      (data["currency"] ?? "").toString().toUpperCase();
    const isBist = symbolUpper.endsWith(".IS") || storedCurrency === "TRY";

    const price = resolveLatestPrice(data, prices);

    const shares = toNumber(data["shares"]);
    const value = price * shares;

    if (isBist) {
      trySum += value;
    } else {
      usdSum += value;
    }
  }

  const totalTry = trySum + usdSum * safeRate;
  const totalUsd = usdSum + trySum / safeRate;

  return {totalTry, totalUsd};
}

/**
 * Persists point-in-time share counts for entitlement checks.
 *
 * @param {PortfolioRecord[]} records Portfolio docs.
 * @param {Date} now Snapshot timestamp.
 * @param {string} snapshotId Snapshot id (dateId_hourId).
 * @return {Promise<void>} Promise resolved when writes finish.
 */
export async function recordPortfolioShareHistory(
  records: PortfolioRecord[],
  now: Date,
  snapshotId: string
): Promise<void> {
  const timestamp = admin.firestore.Timestamp.fromDate(now);
  let batch = db.batch();
  let pending = 0;

  for (const record of records) {
    const shares = toNumber(record.data["shares"]);
    batch.set(
      record.ref.collection("shares_history").doc(snapshotId),
      {
        date: timestamp,
        shares: shares,
      },
      {merge: true}
    );
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
 * Builds snapshot info from stored data.
 *
 * @param {Record<string, unknown>} data Snapshot document data.
 * @param {Date} date Snapshot date.
 * @return {SnapshotInfo} Snapshot info.
 */
export function snapshotFromData(
  data: Record<string, unknown>,
  date: Date
): SnapshotInfo {
  return {
    date: date,
    totalTry: toNumber(data["total_value_try"]),
    totalUsd: toNumber(data["total_value_usd"]),
    cumulativeTwr: toNumber(data["cumulative_twr"]),
  };
}

/**
 * Resolves a cash flow amount in TRY from document data.
 *
 * @param {Record<string, unknown>} data Cash flow doc data.
 * @param {number} exchangeRate USD/TRY exchange rate.
 * @return {number} Amount in TRY.
 */
function toCashFlowTryAmount(
  data: Record<string, unknown>,
  exchangeRate: number
): number {
  const currency = (data["currency"] ?? "TRY").toString().toUpperCase();
  const amountCurrency = toNumber(data["amount_currency"]);
  let amount = toNumber(data["amount_try"]);

  if (currency !== "TRY" && amountCurrency > 0) {
    const rate = exchangeRate > 0 ? exchangeRate : DEFAULT_FX;
    amount = amountCurrency * rate;
  }

  return amount;
}
