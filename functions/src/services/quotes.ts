import {PriceMap} from "../types";
import {toNumber} from "../utils/numbers";
import {toSymbol} from "../utils/symbols";
import {logger} from "../app/firebase";

export type HistoricalDataPoint = {
  timestamp: number;
  price: number;
};

export type SeriesPoint = {
  t: number;
  p: number;
};

export type PopularStockQuoteData = {
  symbol: string;
  currentPrice: number;
  return24h: number;
  series: SeriesPoint[];
};

const QUOTE_CHUNK_SIZE = 50;
const QUOTE_RETRY_ATTEMPTS = 3;
const QUOTE_RETRY_BASE_DELAY_MS = 800;
const QUOTE_REQUEST_TIMEOUT_MS = 10000;
const CHART_FALLBACK_CONCURRENCY = 6;
const POPULAR_STOCKS_DELAY_MS = 500;
const POPULAR_STOCKS_LIMIT = 10;

export type QuoteErrorType =
  | "API_Error"
  | "Timeout"
  | "Network_Error"
  | "Parse_Error"
  | "No_Data"
  | "Unknown_Error";

export type SymbolFetchFailure = {
  status: number | null;
  errorType: QuoteErrorType;
  error: string | null;
  source: "quote" | "chart_fallback";
};

export type QuoteFetchReport = {
  prices: PriceMap;
  failedSymbols: Record<string, SymbolFetchFailure>;
  successfulChunks: number;
  failedChunks: number;
  retriedChunks: number;
};

type YahooQuote = {
  symbol?: string;
  regularMarketPrice?: number;
};

type QuoteChunkResult = {
  ok: boolean;
  quotes: YahooQuote[];
  attempts: number;
  status: number | null;
  error: string | null;
  errorType: QuoteErrorType | null;
};

type SingleChartPriceResult = {
  price: number;
  status: number | null;
  error: string | null;
  errorType: QuoteErrorType | null;
};

type ChartFallbackResult = {
  prices: PriceMap;
  failures: Record<string, SymbolFetchFailure>;
};

/**
 * Fetches quote prices and swallows transient failures.
 *
 * @param {string[]} symbols Symbol list.
 * @return {Promise<PriceMap>} Price map keyed by symbol.
 */
export async function fetchQuotePrices(
  symbols: string[]
): Promise<PriceMap> {
  const report = await fetchQuotePricesWithReport(symbols);
  return report.prices;
}

/**
 * Fetches quote prices and returns partial failure diagnostics.
 *
 * @param {string[]} symbols Symbol list.
 * @return {Promise<QuoteFetchReport>} Prices and per-symbol failures.
 */
export async function fetchQuotePricesWithReport(
  symbols: string[]
): Promise<QuoteFetchReport> {
  if (symbols.length === 0) {
    return {
      prices: {},
      failedSymbols: {},
      successfulChunks: 0,
      failedChunks: 0,
      retriedChunks: 0,
    };
  }

  const normalizedSymbols = Array.from(
    new Set(
      symbols
        .map((symbol) => toSymbol(symbol))
        .filter((symbol): symbol is string => Boolean(symbol))
        .map((symbol) => symbol.toUpperCase())
    )
  );

  if (normalizedSymbols.length === 0) {
    return {
      prices: {},
      failedSymbols: {},
      successfulChunks: 0,
      failedChunks: 0,
      retriedChunks: 0,
    };
  }

  const prices: PriceMap = {};
  const failedSymbols: Record<string, SymbolFetchFailure> = {};

  const userAgent = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "AppleWebKit/537.36 (KHTML, like Gecko)",
    "Chrome/120.0.0.0 Safari/537.36",
  ].join(" ");

  let successfulChunks = 0;
  let failedChunks = 0;
  let retriedChunks = 0;

  for (let i = 0; i < normalizedSymbols.length; i += QUOTE_CHUNK_SIZE) {
    const chunk = normalizedSymbols.slice(i, i + QUOTE_CHUNK_SIZE);
    const chunkResult = await fetchQuoteChunk(chunk, userAgent);

    if (chunkResult.attempts > 1) {
      retriedChunks += 1;
    }

    if (!chunkResult.ok) {
      logger.error("Quote API chunk failed", {
        status: chunkResult.status,
        errorType: chunkResult.errorType,
        error: chunkResult.error,
        attempts: chunkResult.attempts,
        symbols: chunk,
        chunkSize: chunk.length,
      });

      const fallback = await fetchChartFallbackPrices(chunk, userAgent);
      Object.assign(prices, fallback.prices);

      const unresolved = chunk.filter((symbol) => !fallback.prices[symbol]);
      setUnresolvedSymbols(
        unresolved,
        failedSymbols,
        fallback.failures,
        {
          status: chunkResult.status,
          error: chunkResult.error,
          errorType: chunkResult.errorType ?? "Unknown_Error",
          source: "quote",
        }
      );

      if (Object.keys(fallback.prices).length > 0) {
        logger.warn("Quote API fallback used", {
          status: chunkResult.status,
          errorType: chunkResult.errorType,
          symbolsRequested: chunk.length,
          fallbackResolved: Object.keys(fallback.prices).length,
          unresolved: unresolved.length,
        });
      }

      if (unresolved.length > 0) {
        failedChunks += 1;
        logger.error("Quote chunk unresolved after fallback", {
          status: chunkResult.status,
          errorType: chunkResult.errorType,
          unresolvedCount: unresolved.length,
          unresolvedSymbols: unresolved,
        });
      } else {
        successfulChunks += 1;
      }

      continue;
    }

    successfulChunks += 1;

    const resolvedByQuote = new Set<string>();
    for (const quote of chunkResult.quotes) {
      const symbol = (quote.symbol ?? "").toUpperCase();
      const price = quote.regularMarketPrice;
      if (!symbol || typeof price !== "number" || price <= 0) continue;
      prices[symbol] = price;
      resolvedByQuote.add(symbol);
    }

    const missingSymbols = chunk.filter(
      (symbol) => !resolvedByQuote.has(symbol)
    );

    if (missingSymbols.length > 0) {
      logger.warn("Quote API chunk missing symbols", {
        missingCount: missingSymbols.length,
        missingSymbols: missingSymbols,
        chunkSize: chunk.length,
      });

      const fallback = await fetchChartFallbackPrices(
        missingSymbols,
        userAgent
      );
      Object.assign(prices, fallback.prices);

      const unresolved = missingSymbols.filter(
        (symbol) => !fallback.prices[symbol]
      );

      setUnresolvedSymbols(
        unresolved,
        failedSymbols,
        fallback.failures,
        {
          status: chunkResult.status,
          error: "Quote response missing symbol",
          errorType: "No_Data",
          source: "quote",
        }
      );

      if (Object.keys(fallback.prices).length > 0) {
        logger.warn("Quote missing-symbol fallback used", {
          symbolsRequested: missingSymbols.length,
          fallbackResolved: Object.keys(fallback.prices).length,
          unresolved: unresolved.length,
        });
      }

      if (unresolved.length > 0) {
        failedChunks += 1;
        logger.error("Quote symbols unresolved after quote+fallback", {
          unresolvedCount: unresolved.length,
          unresolvedSymbols: unresolved,
        });
      }
    }
  }

  const resolvedCount = Object.keys(prices).length;
  const failedCount = Object.keys(failedSymbols).length;

  if (successfulChunks === 0) {
    logger.error("Quote API unavailable: all chunks unresolved", {
      requestedSymbols: normalizedSymbols.length,
      failedChunks: failedChunks,
      resolvedCount: resolvedCount,
    });
  }

  if (failedCount > 0) {
    logger.warn("Quote API partial failures", {
      requestedSymbols: normalizedSymbols.length,
      resolvedCount: resolvedCount,
      failedSymbols: failedCount,
      failedChunks: failedChunks,
      sampleFailedSymbols: Object.keys(failedSymbols).slice(0, 10),
    });
  }

  if (retriedChunks > 0) {
    logger.warn("Quote API retries used", {
      retriedChunks: retriedChunks,
      totalChunks: Math.ceil(normalizedSymbols.length / QUOTE_CHUNK_SIZE),
      resolvedCount: resolvedCount,
    });
  }

  return {
    prices: prices,
    failedSymbols: failedSymbols,
    successfulChunks: successfulChunks,
    failedChunks: failedChunks,
    retriedChunks: retriedChunks,
  };
}

/**
 * Fetches a quote chunk with retry.
 *
 * @param {string[]} symbols Chunk symbols.
 * @param {string} userAgent Request user-agent.
 * @return {Promise<QuoteChunkResult>} Chunk result.
 */
async function fetchQuoteChunk(
  symbols: string[],
  userAgent: string
): Promise<QuoteChunkResult> {
  const query = encodeURIComponent(symbols.join(","));
  const url =
    "https://query1.finance.yahoo.com/v7/finance/quote?symbols=" +
    query;

  let lastStatus: number | null = null;
  let lastError: string | null = null;
  let lastErrorType: QuoteErrorType | null = null;

  for (let attempt = 1; attempt <= QUOTE_RETRY_ATTEMPTS; attempt += 1) {
    try {
      const response = await fetchWithTimeout(url, userAgent);
      lastStatus = response.status;

      if (!response.ok) {
        lastError = `HTTP ${response.status}`;
        lastErrorType = "API_Error";
        if (attempt < QUOTE_RETRY_ATTEMPTS &&
          isRetryableStatus(response.status)) {
          await delayMs(getRetryDelayMs(attempt));
          continue;
        }

        return {
          ok: false,
          quotes: [],
          attempts: attempt,
          status: response.status,
          error: lastError,
          errorType: lastErrorType,
        };
      }

      const data = (await response.json()) as {
        quoteResponse?: {
          result?: YahooQuote[];
        };
      };

      return {
        ok: true,
        quotes: data.quoteResponse?.result ?? [],
        attempts: attempt,
        status: response.status,
        error: null,
        errorType: null,
      };
    } catch (error) {
      const classified = classifyError(error);
      lastError = classified.error;
      lastErrorType = classified.errorType;

      if (attempt < QUOTE_RETRY_ATTEMPTS) {
        await delayMs(getRetryDelayMs(attempt));
        continue;
      }
    }
  }

  return {
    ok: false,
    quotes: [],
    attempts: QUOTE_RETRY_ATTEMPTS,
    status: lastStatus,
    error: lastError,
    errorType: lastErrorType,
  };
}

/**
 * Fetches prices using Yahoo chart endpoint as fallback.
 *
 * @param {string[]} symbols Symbols to query.
 * @param {string} userAgent Request user-agent.
 * @return {Promise<ChartFallbackResult>} Resolved prices + failures.
 */
async function fetchChartFallbackPrices(
  symbols: string[],
  userAgent: string
): Promise<ChartFallbackResult> {
  const prices: PriceMap = {};
  const failures: Record<string, SymbolFetchFailure> = {};

  for (let i = 0; i < symbols.length; i += CHART_FALLBACK_CONCURRENCY) {
    const windowSymbols = symbols.slice(i, i + CHART_FALLBACK_CONCURRENCY);
    const windowResults = await Promise.all(
      windowSymbols.map(async (symbol) => {
        const result = await fetchSingleChartPrice(symbol, userAgent);
        return {symbol: symbol, result: result};
      })
    );

    for (const entry of windowResults) {
      if (entry.result.price > 0) {
        prices[entry.symbol] = entry.result.price;
        continue;
      }

      failures[entry.symbol] = {
        status: entry.result.status,
        errorType: entry.result.errorType ?? "Unknown_Error",
        error: entry.result.error,
        source: "chart_fallback",
      };
    }
  }

  return {prices: prices, failures: failures};
}

/**
 * Fetches a single symbol price from Yahoo chart endpoint.
 *
 * @param {string} symbol Symbol to query.
 * @param {string} userAgent Request user-agent.
 * @return {Promise<SingleChartPriceResult>} Latest market price or failure.
 */
async function fetchSingleChartPrice(
  symbol: string,
  userAgent: string
): Promise<SingleChartPriceResult> {
  const encoded = encodeURIComponent(symbol);
  const url =
    `https://query1.finance.yahoo.com/v8/finance/chart/${encoded}` +
    "?interval=1d&range=1d";

  let lastStatus: number | null = null;
  let lastError: string | null = null;
  let lastErrorType: QuoteErrorType | null = null;

  for (let attempt = 1; attempt <= QUOTE_RETRY_ATTEMPTS; attempt += 1) {
    try {
      const response = await fetchWithTimeout(url, userAgent);
      lastStatus = response.status;

      if (!response.ok) {
        lastError = `HTTP ${response.status}`;
        lastErrorType = "API_Error";
        if (attempt < QUOTE_RETRY_ATTEMPTS &&
          isRetryableStatus(response.status)) {
          await delayMs(getRetryDelayMs(attempt));
          continue;
        }
        return {
          price: 0,
          status: response.status,
          error: lastError,
          errorType: lastErrorType,
        };
      }

      const data = (await response.json()) as {
        chart?: {
          result?: Array<{
            meta?: { regularMarketPrice?: number };
            indicators?: { quote?: Array<{ close?: Array<number | null> }> };
          }>;
        };
      };

      const result = data.chart?.result?.[0];
      const metaPrice = result?.meta?.regularMarketPrice;
      if (typeof metaPrice === "number" && metaPrice > 0) {
        return {
          price: metaPrice,
          status: response.status,
          error: null,
          errorType: null,
        };
      }

      const closes = result?.indicators?.quote?.[0]?.close ?? [];
      for (let i = closes.length - 1; i >= 0; i -= 1) {
        const close = closes[i];
        if (typeof close === "number" && close > 0) {
          return {
            price: close,
            status: response.status,
            error: null,
            errorType: null,
          };
        }
      }

      return {
        price: 0,
        status: response.status,
        error: "No price in chart response",
        errorType: "No_Data",
      };
    } catch (error) {
      const classified = classifyError(error);
      lastError = classified.error;
      lastErrorType = classified.errorType;

      if (attempt < QUOTE_RETRY_ATTEMPTS) {
        await delayMs(getRetryDelayMs(attempt));
        continue;
      }
    }
  }

  return {
    price: 0,
    status: lastStatus,
    error: lastError,
    errorType: lastErrorType,
  };
}

/**
 * Persists unresolved symbols with fallback-first failure details.
 *
 * @param {string[]} unresolved Symbol list unresolved after fallback.
 * @param {Record<string, SymbolFetchFailure>} target Output failure map.
 * @param {Record<string, SymbolFetchFailure>} fallbackFailures Fallback map.
 * @param {SymbolFetchFailure} primaryFailure Primary quote failure.
 * @return {void}
 */
function setUnresolvedSymbols(
  unresolved: string[],
  target: Record<string, SymbolFetchFailure>,
  fallbackFailures: Record<string, SymbolFetchFailure>,
  primaryFailure: SymbolFetchFailure
): void {
  for (const symbol of unresolved) {
    const failure = fallbackFailures[symbol] ?? primaryFailure;
    target[symbol] = failure;
  }
}

/**
 * Classifies fetch/json errors for structured logging.
 *
 * @param {unknown} error Raw thrown error.
 * @return {{errorType: QuoteErrorType, error: string}} Classified info.
 */
function classifyError(
  error: unknown
): { errorType: QuoteErrorType; error: string } {
  const message = error instanceof Error ? error.message : String(error);

  if (error instanceof SyntaxError) {
    return {
      errorType: "Parse_Error",
      error: message,
    };
  }

  const name = error instanceof Error ? error.name : "";
  const lower = message.toLowerCase();

  if (name === "AbortError" || lower.includes("timeout")) {
    return {
      errorType: "Timeout",
      error: message,
    };
  }

  if (
    lower.includes("eai_again") ||
    lower.includes("enotfound") ||
    lower.includes("fetch failed") ||
    lower.includes("network")
  ) {
    return {
      errorType: "Network_Error",
      error: message,
    };
  }

  return {
    errorType: "Unknown_Error",
    error: message,
  };
}

/**
 * Calls fetch with timeout for quote requests.
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
    QUOTE_REQUEST_TIMEOUT_MS
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
  return QUOTE_RETRY_BASE_DELAY_MS * Math.pow(2, exp);
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
 * Fetches popular stock quotes with 24-hour returns and 3-hour series.
 *
 * @param {string[]} symbols Array of stock symbols.
 * @return {Promise<PopularStockQuoteData[]>} Array of popular stock quote data.
 */
export async function getPopularStockQuotes(
  symbols: string[]
): Promise<PopularStockQuoteData[]> {
  logger.info("Starting popular stock quotes fetch", {
    symbolCount: symbols.length,
  });

  const results: PopularStockQuoteData[] = [];
  const symbolsToProcess = symbols.slice(0, POPULAR_STOCKS_LIMIT);

  for (const symbol of symbolsToProcess) {
    try {
      // Fetch current quote
      const quotePrices = await fetchQuotePrices([symbol]);
      const currentPrice = quotePrices[symbol] ?? 0;

      // Fetch historical data for 24-hour calculation
      const historicalData = await getHistoricalData(symbol, "5d", "3h");
      
      // Compute 24-hour return
      const return24h = compute24hReturn(currentPrice, historicalData);
      
      // Extract 3-hour series
      const series = extract3hSeries(historicalData);

      results.push({
        symbol,
        currentPrice,
        return24h,
        series,
      });

      // Rate limiting delay
      await delayMs(POPULAR_STOCKS_DELAY_MS);
    } catch (error) {
      logger.error(`Error fetching data for popular stock ${symbol}`, {
        error: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
      });

      // Add with null values on error
      results.push({
        symbol,
        currentPrice: 0,
        return24h: 0,
        series: [],
      });
    }
  }

  logger.info("Completed popular stock quotes fetch", {
    processedSymbols: results.length,
    failedSymbols: results.filter(r => r.currentPrice <= 0).length,
  });

  return results;
}

/**
 * Fetches historical data for a symbol with configurable range and interval.
 *
 * @param {string} symbol Stock symbol.
 * @param {string} range Time range (e.g., '1d', '5d', '1mo').
 * @param {string} interval Data point interval (e.g., '3h', '1d').
 * @return {Promise<HistoricalDataPoint[]>} Array of historical data points.
 */
export async function getHistoricalData(
  symbol: string,
  range: string,
  interval: string
): Promise<HistoricalDataPoint[]> {
  const userAgent = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "AppleWebKit/537.36 (KHTML, like Gecko)",
    "Chrome/120.0.0.0 Safari/537.36",
  ].join(" ");

  const encoded = encodeURIComponent(symbol);
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encoded}?interval=${interval}&range=${range}`;

  let lastStatus: number | null = null;
  let lastError: string | null = null;

  for (let attempt = 1; attempt <= QUOTE_RETRY_ATTEMPTS; attempt += 1) {
    try {
      const response = await fetchWithTimeout(url, userAgent);
      lastStatus = response.status;

      if (!response.ok) {
        lastError = `HTTP ${response.status}`;
        if (attempt < QUOTE_RETRY_ATTEMPTS && isRetryableStatus(response.status)) {
          await delayMs(getRetryDelayMs(attempt));
          continue;
        }
        logger.error(`Failed to fetch historical data for ${symbol}`, {
          status: response.status,
          error: lastError,
          range,
          interval,
        });
        return [];
      }

      const data = await response.json() as {
        chart?: {
          result?: Array<{
            timestamp?: number[];
            indicators?: {
              quote?: Array<{
                close?: Array<number | null>;
              }>;
            };
          }>;
        };
      };

      const result = data.chart?.result?.[0];
      if (!result?.timestamp || !result?.indicators?.quote?.[0]?.close) {
        logger.warn(`No historical data found for ${symbol}`, {
          range,
          interval,
        });
        return [];
      }

      const timestamps = result.timestamp;
      const closes = result.indicators.quote[0].close;
      const dataPoints: HistoricalDataPoint[] = [];

      for (let i = 0; i < timestamps.length; i++) {
        const timestamp = timestamps[i] * 1000; // Convert to milliseconds
        const price = closes[i];
        
        if (typeof timestamp === "number" && typeof price === "number" && price > 0) {
          dataPoints.push({
            timestamp,
            price,
          });
        }
      }

      return dataPoints;
    } catch (error) {
      lastError = error instanceof Error ? error.message : String(error);
      
      if (attempt < QUOTE_RETRY_ATTEMPTS) {
        await delayMs(getRetryDelayMs(attempt));
        continue;
      }

      logger.error(`Error fetching historical data for ${symbol}`, {
        error: lastError,
        stack: error instanceof Error ? error.stack : undefined,
        range,
        interval,
      });
      return [];
    }
  }

  logger.error(`All attempts failed for historical data of ${symbol}`, {
    status: lastStatus,
    error: lastError,
  });
  return [];
}

/**
 * Computes 24-hour return percentage from historical data.
 *
 * @param {number} currentPrice Current stock price.
 * @param {HistoricalDataPoint[]} historicalData Array of historical data points.
 * @return {number} Percentage change (e.g., -1.23 or 4.56).
 */
export function compute24hReturn(
  currentPrice: number,
  historicalData: HistoricalDataPoint[]
): number {
  if (currentPrice <= 0 || historicalData.length === 0) {
    return 0;
  }

  const twentyFourHoursAgo = Date.now() - 24 * 60 * 60 * 1000;
  
  // Find the data point closest to 24 hours ago
  let closestPoint: HistoricalDataPoint | null = null;
  let closestDiff = Infinity;

  for (const point of historicalData) {
    const diff = Math.abs(point.timestamp - twentyFourHoursAgo);
    if (diff < closestDiff) {
      closestDiff = diff;
      closestPoint = point;
    }
  }

  if (!closestPoint || closestPoint.price <= 0) {
    return 0;
  }

  const percentageChange = ((currentPrice - closestPoint.price) / closestPoint.price) * 100;
  
  // Round to 2 decimal places
  return Math.round(percentageChange * 100) / 100;
}

/**
 * Extracts 3-hour interval series from historical data.
 *
 * @param {HistoricalDataPoint[]} historicalData Full historical data array.
 * @param {number} maxPoints Maximum points to return (default: 8).
 * @return {SeriesPoint[]} Array of series points with timestamp and price.
 */
export function extract3hSeries(
  historicalData: HistoricalDataPoint[],
  maxPoints: number = 8
): SeriesPoint[] {
  if (historicalData.length === 0) {
    return [];
  }

  // Sort by timestamp to ensure chronological order
  const sortedData = [...historicalData].sort((a, b) => a.timestamp - b.timestamp);
  
  // Filter for 3-hour intervals (approximate)
  const threeHours = 3 * 60 * 60 * 1000; // 3 hours in milliseconds
  const seriesPoints: SeriesPoint[] = [];
  let lastTimestamp = 0;

  for (const point of sortedData) {
    // Ensure we have at least 3 hours between points
    if (point.timestamp - lastTimestamp >= threeHours * 0.8) { // 80% of 3 hours
      seriesPoints.push({
        t: point.timestamp,
        p: point.price,
      });
      lastTimestamp = point.timestamp;
    }
  }

  // If we have too few points, use the available data
  if (seriesPoints.length === 0 && sortedData.length > 0) {
    // Take every other point to get approximately 3-hour intervals
    const step = Math.max(1, Math.floor(sortedData.length / maxPoints));
    for (let i = 0; i < sortedData.length && seriesPoints.length < maxPoints; i += step) {
      seriesPoints.push({
        t: sortedData[i].timestamp,
        p: sortedData[i].price,
      });
    }
  }

  // Return last N points
  return seriesPoints.slice(-maxPoints);
}

/**
 * Fetches the most recent closing or last-trade price for a single symbol
 * from a recent historical window (approximately 24-26 hours ago).
 *
 * @param {string} symbol Stock symbol to fetch recent price for.
 * @return {Promise<number | null>} Recent price or null if unavailable.
 */
export async function fetchRecentPrice(
  symbol: string
): Promise<number | null> {
  if (!symbol || typeof symbol !== "string" || symbol.trim() === "") {
    return null;
  }

  try {
    // Fetch 2 days of historical data with 1-hour intervals to ensure we have ~24h ago price
    const historicalData = await getHistoricalData(symbol, "2d", "1h");
    
    if (historicalData.length === 0) {
      logger.warn(`No historical data available for recent price of ${symbol}`);
      return null;
    }

    const twentyFourHoursAgo = Date.now() - 24 * 60 * 60 * 1000;
    
    // Find the data point closest to 24 hours ago
    let closestPoint: HistoricalDataPoint | null = null;
    let closestDiff = Infinity;

    for (const point of historicalData) {
      const diff = Math.abs(point.timestamp - twentyFourHoursAgo);
      if (diff < closestDiff) {
        closestDiff = diff;
        closestPoint = point;
      }
    }

    if (!closestPoint || closestPoint.price <= 0) {
      logger.warn(`No valid price found in historical data for ${symbol} near 24h mark`);
      return null;
    }

    return closestPoint.price;
  } catch (error) {
    // This catch is for any unexpected errors in the above code
    logger.warn(`Error fetching recent price for ${symbol}: ${error instanceof Error ? error.message : String(error)}`);
    return null;
  }
}

/**
 * Resolves the latest price for a portfolio item.
 *
 * @param {Record<string, unknown>} data Portfolio item data.
 * @param {PriceMap} prices Live price map.
 * @return {number} Latest price or fallback.
 */
export function resolveLatestPrice(
  data: Record<string, unknown>,
  prices: PriceMap
): number {
  const rawSymbol = toSymbol(data["symbol"]);
  if (!rawSymbol) return 0;

  const symbolUpper = rawSymbol.toUpperCase();
  const storedCurrency =
    (data["currency"] ?? "").toString().toUpperCase();
  const isBist = symbolUpper.endsWith(".IS") || storedCurrency === "TRY";

  const baseSymbol = symbolUpper.replace(/\.IS$/i, "");
  const trySymbol = `${baseSymbol}.IS`;
  const usdSymbol = baseSymbol;

  let price = 0;
  if (isBist) {
    price = prices[trySymbol] ?? prices[symbolUpper] ?? 0;
  } else {
    price = prices[usdSymbol] ?? prices[symbolUpper] ?? 0;
  }

  if (price <= 0) {
    price =
      toNumber(data["current_price"]) ||
      toNumber(data["purchase_price"]);
  }

  return price;
}
