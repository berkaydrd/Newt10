import {onSchedule} from "firebase-functions/v2/scheduler";
import {admin, db, logger} from "../app/firebase";
import {LEADERBOARD_CONFIGS, TIME_ZONE} from "../app/config";
import {LeaderboardEntry} from "../types";
import {extractSnapshotDate} from "../utils/dates";
import {toNumber} from "../utils/numbers";
import {resolveProfileImagePath} from "../utils/profile";

export const updateLeaderboards = onSchedule(
  {
    schedule: "0 23 * * *",
    timeZone: TIME_ZONE,
    region: "europe-west1",
  },
  async () => {
    await rebuildLeaderboards();
  }
);

/**
 * Rebuilds leaderboard documents from performance history.
 *
 * @return {Promise<void>} Promise resolved when leaderboard updates finish.
 */
async function rebuildLeaderboards(): Promise<void> {
  const now = new Date();
  const cutoff = new Date(now.getTime() - 365 * 24 * 60 * 60 * 1000);
  const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);

  logger.info("Leaderboard rebuild start", {
    cutoff: cutoff.toISOString(),
  });

  const usersSnapshot = await db.collection("usernames").get();
  if (usersSnapshot.empty) {
    logger.warn("No users found in usernames collection for leaderboard.");
    return;
  }

  const buckets: Record<string, Array<Omit<LeaderboardEntry, "rank">>> = {};
  for (const config of LEADERBOARD_CONFIGS) {
    buckets[config.id] = [];
  }

  for (const userDoc of usersSnapshot.docs) {
    const userData = userDoc.data() as Record<string, unknown>;
    const usernameRaw = userData["username"] ?? userDoc.id;
    let username: string | null = null;
    if (typeof usernameRaw === "string" && usernameRaw.trim().length > 0) {
      username = usernameRaw.trim();
    }
    if (!username) continue;

    const profileImage = resolveProfileImagePath(userData);

    const perfSnap = await userDoc.ref
      .collection("performance_history")
      .where("date", ">=", cutoffTs)
      .orderBy("date", "asc")
      .get();

    if (perfSnap.empty) continue;

    const snapshots = perfSnap.docs
      .map((doc) => {
        const data = doc.data() as Record<string, unknown>;
        const date = extractSnapshotDate(data);
        if (!date) return null;
        return {date, twr: toNumber(data["cumulative_twr"])};
      })
      .filter(
        (item): item is {date: Date; twr: number} => item !== null
      );

    if (snapshots.length === 0) continue;

    for (const config of LEADERBOARD_CONFIGS) {
      const windowStart = new Date(
        now.getTime() - config.days * 24 * 60 * 60 * 1000
      );
      const windowDocs = snapshots.filter((item) => item.date >= windowStart);
      if (windowDocs.length < config.minCount) continue;

      const startTwr = windowDocs[0].twr;
      const endTwr = windowDocs[windowDocs.length - 1].twr;
      const denominator = 1 + startTwr;
      if (denominator <= 0) continue;

      const ratio = (1 + endTwr) / denominator - 1;
      if (!Number.isFinite(ratio)) continue;

      buckets[config.id].push({
        username: username,
        profile_image_path: profileImage,
        twr_ratio: ratio,
      });
    }
  }

  for (const config of LEADERBOARD_CONFIGS) {
    const entries: LeaderboardEntry[] = buckets[config.id]
      .sort((a, b) => b.twr_ratio - a.twr_ratio)
      .slice(0, 10)
      .map((entry, index) => ({
        ...entry,
        rank: index + 1,
      }));

    await db.collection("leaderboards").doc(config.id).set(
      {
        entries: entries,
        updated_at: admin.firestore.Timestamp.fromDate(now),
      },
      {merge: true}
    );
  }

  logger.info("Leaderboard rebuild finished", {
    weekly: buckets["weekly"]?.length ?? 0,
    monthly: buckets["monthly"]?.length ?? 0,
    yearly: buckets["yearly"]?.length ?? 0,
  });
}
