import {admin} from "./app/firebase";

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
