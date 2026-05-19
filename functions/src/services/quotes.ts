import {PriceMap} from "../types";
import {toNumber} from "../utils/numbers";
import {toSymbol} from "../utils/symbols";

/**
 * Fetches quote prices from Yahoo Finance for the provided symbols.
 *
 * @param {string[]} symbols Symbol list.
 * @return {Promise<PriceMap>} Price map keyed by symbol.
 */
export async function fetchQuotePrices(
  symbols: string[]
): Promise<PriceMap> {
  if (symbols.length === 0) return {};
  const chunkSize = 50;
  const result: PriceMap = {};
  const userAgent = [
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
    "AppleWebKit/537.36 (KHTML, like Gecko)",
    "Chrome/120.0.0.0 Safari/537.36",
  ].join(" ");

  for (let i = 0; i < symbols.length; i += chunkSize) {
    const chunk = symbols.slice(i, i + chunkSize);
    const query = encodeURIComponent(chunk.join(","));
    const url =
      `https://query1.finance.yahoo.com/v7/finance/quote?symbols=${query}`;

    const response = await globalThis.fetch(url, {
      headers: {
        "User-Agent": userAgent,
      },
    });

    if (!response.ok) continue;
    const data = (await response.json()) as {
      quoteResponse?: {
        result?: Array<{ symbol?: string; regularMarketPrice?: number }>;
      };
    };

    const quotes = data.quoteResponse?.result ?? [];
    for (const quote of quotes) {
      const symbol = (quote.symbol ?? "").toUpperCase();
      const price = quote.regularMarketPrice;
      if (symbol && typeof price === "number") {
        result[symbol] = price;
      }
    }
  }

  return result;
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
