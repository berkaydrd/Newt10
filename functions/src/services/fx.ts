import {admin, db} from "../app/firebase";
import {DEFAULT_FX} from "../app/config";
import {fetchQuotePrices} from "./quotes";
import {toNumber} from "../utils/numbers";

/**
 * Fetches daily USD/TRY exchange rate with fallbacks.
 *
 * @return {Promise<number>} USD/TRY exchange rate.
 */
export async function getExchangeRate(): Promise<number> {
  const chartRate = await fetchYahooChartRate("USDTRY=X");
  if (chartRate > 0) {
    await saveFxRate(chartRate, "yahoo_chart");
    return chartRate;
  }

  const prices = await fetchQuotePrices(["USDTRY=X"]);
  const quoteRate = prices["USDTRY=X"];
  if (quoteRate && quoteRate > 0) {
    await saveFxRate(quoteRate, "yahoo_quote");
    return quoteRate;
  }

  const cachedRate = await getCachedFxRate();
  if (cachedRate > 0) return cachedRate;

  return DEFAULT_FX;
}

/**
 * Fetches exchange rate using Yahoo chart endpoint.
 *
 * @param {string} symbol Yahoo finance symbol.
 * @return {Promise<number>} Exchange rate or 0 on failure.
 */
export async function fetchYahooChartRate(symbol: string): Promise<number> {
  const url =
    `https://query1.finance.yahoo.com/v8/finance/chart/${symbol}` +
    "?interval=1d&range=1d";

  const response = await globalThis.fetch(url, {
    headers: {
      "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
    },
  });

  if (!response.ok) return 0;
  const data = (await response.json()) as {
    chart?: { result?: Array<{ meta?: { regularMarketPrice?: number } }> };
  };

  const price = data.chart?.result?.[0]?.meta?.regularMarketPrice;
  if (typeof price === "number" && price > 0) return price;
  return 0;
}

/**
 * Reads the last cached USD/TRY exchange rate.
 *
 * @return {Promise<number>} Cached rate or 0.
 */
export async function getCachedFxRate(): Promise<number> {
  const doc = await db.collection("fx_rates").doc("usdtry").get();
  if (!doc.exists) return 0;
  const rate = toNumber(doc.data()?.rate);
  return rate > 0 ? rate : 0;
}

/**
 * Stores the latest USD/TRY exchange rate.
 *
 * @param {number} rate Exchange rate.
 * @param {string} source Data source.
 * @return {Promise<void>} Promise resolved when write completes.
 */
export async function saveFxRate(rate: number, source: string): Promise<void> {
  await db.collection("fx_rates").doc("usdtry").set(
    {
      rate: rate,
      source: source,
      updated_at: admin.firestore.Timestamp.now(),
    },
    {merge: true}
  );
}
