import {LeaderboardConfig} from "../types";

export const TIME_ZONE = "Europe/Istanbul";
export const DEFAULT_FX = 35.0;
export const LEADERBOARD_CONFIGS: LeaderboardConfig[] = [
  {id: "weekly", days: 7, minCount: 5},
  {id: "monthly", days: 30, minCount: 20},
  {id: "yearly", days: 365, minCount: 200},
];
