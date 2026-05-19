import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore } from "firebase-admin/firestore";
import * as admin from 'firebase-admin';
import { fetchQuotePricesWithReport, getHistoricalData, compute24hReturn } from "../services/quotes";
import type { PopularStockEntry, PopularStocksDocument } from "../types";

const POPULAR_SYMBOLS = [
  "AAPL", "MSFT", "GOOGL", "AMZN", "META",
  "NVDA", "TSLA", "BRK.B", "JPM", "V"
];

const DELAY_BETWEEN_REQUESTS_MS = 500;

function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function fetchLogoUrl(symbol: string): Promise<string | null> {
  try {
    const db = getFirestore();
    const stockDoc = await db.collection("stocks").doc(symbol).get();
    if (!stockDoc.exists) {
      console.warn(`No stock document found for ${symbol}`);
      return null;
    }
    const data = stockDoc.data();
    return data?.logo_url ?? null;
  } catch (error) {
    console.warn(`Failed to fetch logo for ${symbol}:`, error);
    return null;
  }
}

async function fetchStockEntries(symbols: string[]): Promise<PopularStockEntry[]> {
  const entries: PopularStockEntry[] = [];

  const priceReport = await fetchQuotePricesWithReport(symbols);

  for (let i = 0; i < symbols.length; i++) {
    const symbol = symbols[i];
    // 3. DÜZELTME: Fiyatı doğru objenin içinden çekiyoruz
    const price = priceReport.prices[symbol];

    if (typeof price !== "number" || price <= 0) {
      console.warn(`No price data for ${symbol}, skipping`);
      continue;
    }

    if (i > 0) {
      await delay(DELAY_BETWEEN_REQUESTS_MS);
    }

    const logoUrl = await fetchLogoUrl(symbol);

    // 4. DÜZELTME: 24h getirisini quotes.ts'in kurallarına göre hesaplıyoruz
    const historicalData = await getHistoricalData(symbol, "5d", "3h");
    const return24h = compute24hReturn(price, historicalData);

    entries.push({
      symbol,
      name: symbol, // name verisi quote'tan gelmiyor, symbol'ü name olarak atıyoruz
      // 5. DÜZELTME: types.ts'in beklediği gibi null yerine boş string ("") atıyoruz
      logo_url: logoUrl ?? "", 
      price: price,
      return_24h_pct: return24h
    });
  }

  return entries;
}

export const popularStocksJob = onSchedule(
  {
    schedule: "every 3 hours",
    timeZone: "Europe/Istanbul" // Daha doğru olması için Istanbul yapıldı
  },
  async (event) => {
    const db = getFirestore();

    try {
      console.log("Starting popular stocks job");
      const entries = await fetchStockEntries(POPULAR_SYMBOLS);

      if (entries.length === 0) {
        console.error("No valid entries found, aborting write");
        return;
      }

      // 6. DÜZELTME: Payload tipi types.ts ile eşitlendi
      const payload: PopularStocksDocument = {
        updated_at: admin.firestore.FieldValue.serverTimestamp() as any,
        entries
      };

      try {
        await db.collection("popular_stocks").doc("v1").set(payload);
      } catch (writeError) {
        console.warn("First Firestore write attempt failed, retrying in 5 seconds...", writeError);
        await delay(5000);
        await db.collection("popular_stocks").doc("v1").set(payload);
      }

      console.log(`Successfully updated popular_stocks/v1 with ${entries.length} entries`);

    } catch (error) {
      console.error("Fatal error in popular stocks job:", error);
      throw error; 
    }
  }
);