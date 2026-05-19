import {admin, db} from "../app/firebase";
import {SnapshotInfo} from "../types";
import {formatDateId} from "../utils/dates";
import {snapshotFromData} from "./portfolio";

/**
 * Cleans up snapshot documents older than the cutoff.
 *
 * @param {admin.firestore.DocumentReference} userRef User document ref.
 * @param {string} collectionName Subcollection to clean.
 * @param {Date} cutoff Delete snapshots older than this date.
 * @return {Promise<void>} Promise resolved when cleanup finishes.
 */
export async function cleanupSnapshots(
  userRef: admin.firestore.DocumentReference,
  collectionName: string,
  cutoff: Date
): Promise<void> {
  const collectionRef = userRef.collection(collectionName);
  const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);
  const snap = await collectionRef.where("date", "<", cutoffTs).get();
  if (snap.empty) return;

  let batch = db.batch();
  let pending = 0;
  for (const doc of snap.docs) {
    batch.delete(doc.ref);
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
 * Mirrors recent temp snapshots into public intraday collection.
 *
 * @param {admin.firestore.DocumentReference} userRef User document ref.
 * @param {Date} cutoff Only sync snapshots after this date.
 * @return {Promise<void>} Promise resolved when sync completes.
 */
export async function syncTempSnapshotsToIntraday(
  userRef: admin.firestore.DocumentReference,
  cutoff: Date
): Promise<void> {
  const cutoffTs = admin.firestore.Timestamp.fromDate(cutoff);
  const tempSnap = await userRef
    .collection("temp_hourly_snapshots")
    .where("date", ">=", cutoffTs)
    .get();

  if (tempSnap.empty) return;

  let batch = db.batch();
  let pending = 0;
  for (const doc of tempSnap.docs) {
    const data = doc.data();
    batch.set(
      userRef.collection("performance_intraday").doc(doc.id),
      {
        date: data["date"],
        date_id: data["date_id"],
        hour_id: data["hour_id"],
        total_value_try: data["total_value_try"],
        total_value_usd: data["total_value_usd"],
        daily_return: data["daily_return"],
        period_return: data["period_return"],
        cumulative_twr: data["cumulative_twr"],
      },
      {merge: true}
    );
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
 * Returns the last snapshot from hourly or performance history.
 *
 * @param {admin.firestore.DocumentReference} userRef User document ref.
 * @param {string} dateId Current date id.
 * @return {Promise<SnapshotInfo | null>} Snapshot info or null.
 */
export async function getLastSnapshot(
  userRef: admin.firestore.DocumentReference,
  dateId: string
): Promise<SnapshotInfo | null> {
  const tempSnap = await userRef
    .collection("temp_hourly_snapshots")
    .orderBy("date", "desc")
    .limit(1)
    .get();

  if (!tempSnap.empty) {
    const doc = tempSnap.docs[0];
    const data = doc.data();
    const ts = data["date"] as admin.firestore.Timestamp | undefined;
    if (ts) {
      const tempDateId = formatDateId(ts.toDate());
      if (tempDateId === dateId) {
        return snapshotFromData(data, ts.toDate());
      }
    }
  }

  const perfSnap = await userRef
    .collection("performance_history")
    .orderBy("date", "desc")
    .limit(1)
    .get();

  if (perfSnap.empty) return null;
  const data = perfSnap.docs[0].data();
  const ts = data["date"] as admin.firestore.Timestamp | undefined;
  if (!ts) return null;
  return snapshotFromData(data, ts.toDate());
}
