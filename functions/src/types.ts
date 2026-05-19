import {admin} from "./app/firebase";
import * as FirebaseFirestore from 'firebase-admin/firestore';

export type PriceMap = Record<string, number>;
export type EventMap = Record<string, unknown>;
export type SymbolEvents = { dividends?: EventMap; splits?: EventMap };
export type PortfolioRecord = {
  ref: admin.firestore.DocumentReference;
  data: Record<string, unknown>;
};
export type SnapshotInfo = {
  date: Date;
  totalTry: number;
  totalUsd: number;
  cumulativeTwr: number;
};
export type LeaderboardEntry = {
  username: string;
  profile_image_path: string | null;
  twr_ratio: number;
  rank: number;
};
export type LeaderboardConfig = {
  id: "weekly" | "monthly" | "yearly";
  days: number;
  minCount: number;
};

// ──────────────────────────────────────────────
// Popular Stocks Types
// ──────────────────────────────────────────────

export type PopularStockSeriesPoint = {
  t: FirebaseFirestore.Timestamp;
  p: number;
};

export type PopularStockEntry = {
  symbol: string;
  name: string;
  logo_url: string; 
  price: number;
  return_24h_pct: number;
  series_3h?: PopularStockSeriesPoint[];
};

export type PopularStocksDocument = {
  updated_at: FirebaseFirestore.Timestamp;
  entries: PopularStockEntry[];
};

export type PopularStocksJobConfig = {
  symbols: string[];
  entryCount: number;
  seriesMaxPoints: number;
};
