import {admin, db, logger} from "../app/firebase";
import {DEFAULT_FX} from "../app/config";
import {fetchQuotePrices} from "./quotes";
import {toNumber} from "../utils/numbers";

const FX_RETRY_ATTEMPTS = 3;
const FX_RETRY_BASE_DELAY_MS = 800;
const FX_REQUEST_TIMEOUT_MS = 10000;

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

  const userAgent =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
    "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  for (let attempt = 1; attempt <= FX_RETRY_ATTEMPTS; attempt += 1) {
    try {
      const response = await fetchWithTimeout(url, userAgent);
      if (!response.ok) {
        if (attempt < FX_RETRY_ATTEMPTS &&
          isRetryableStatus(response.status)) {
          await delayMs(getRetryDelayMs(attempt));
          continue;
        }
        logger.warn("FX chart request failed", {
          symbol: symbol,
          status: response.status,
          attempts: attempt,
        });
        return 0;
      }

      const data = (await response.json()) as {
        chart?: { result?: Array<{ meta?: { regularMarketPrice?: number } }> };
      };

      const price = data.chart?.result?.[0]?.meta?.regularMarketPrice;
      if (typeof price === "number" && price > 0) return price;

      logger.warn("FX chart response missing regularMarketPrice", {
        symbol: symbol,
        attempts: attempt,
      });
      return 0;
    } catch (error) {
      if (attempt < FX_RETRY_ATTEMPTS) {
        await delayMs(getRetryDelayMs(attempt));
        continue;
      }
      logger.error("FX chart request failed after retries", {
        symbol: symbol,
        error: error instanceof Error ? error.message : String(error),
        attempts: FX_RETRY_ATTEMPTS,
      });
    }
  }

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

/**
 * Calls fetch with timeout for FX requests.
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
    FX_REQUEST_TIMEOUT_MS
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
 * Returns true for transient HTTP statuses.
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
  return FX_RETRY_BASE_DELAY_MS * Math.pow(2, exp);
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
