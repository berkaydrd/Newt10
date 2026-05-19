import {admin, db} from "../app/firebase";
import {DEFAULT_FX} from "../app/config";
import {PortfolioRecord, PriceMap, SnapshotInfo} from "../types";
import {toNumber} from "../utils/numbers";
import {toSymbol} from "../utils/symbols";
import {resolveLatestPrice} from "./quotes";

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
  let query = userRef.collection("cash_flows").where("date", "<=", end);
  if (start) {
    query = query.where("date", ">", start);
  }
  const snapshot = await query.get();

  let total = 0;
  for (const doc of snapshot.docs) {
    const data = doc.data();
    const currency =
      (data["currency"] ?? "TRY").toString().toUpperCase();
    const amountCurrency = toNumber(data["amount_currency"]);
    let amount = toNumber(data["amount_try"]);
    if (currency !== "TRY" && amountCurrency > 0) {
      const rate = exchangeRate > 0 ? exchangeRate : DEFAULT_FX;
      amount = amountCurrency * rate;
    }
    const type = (data["type"] ?? "").toString();
    if (type === "withdrawal") total -= amount;
    else total += amount;
  }
  return total;
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
