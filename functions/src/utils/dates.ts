import {admin} from "../app/firebase";
import {TIME_ZONE} from "../app/config";

/**
 * Formats date in YYYY-MM-DD for configured timezone.
 *
 * @param {Date} date Date instance.
 * @return {string} YYYY-MM-DD.
 */
export function formatDateId(date: Date): string {
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(date);
}

/**
 * Formats hour in HH for configured timezone.
 *
 * @param {Date} date Date instance.
 * @return {string} Hour string (00-23).
 */
export function formatHourId(date: Date): string {
  return new Intl.DateTimeFormat("en-GB", {
    timeZone: TIME_ZONE,
    hour: "2-digit",
    hour12: false,
  }).format(date);
}

/**
 * Extracts a snapshot date from stored data.
 *
 * @param {Record<string, unknown>} data Snapshot document data.
 * @return {Date | null} Snapshot date or null.
 */
export function extractSnapshotDate(
  data: Record<string, unknown>
): Date | null {
  const rawDate = data["date"];
  if (rawDate instanceof admin.firestore.Timestamp) {
    return rawDate.toDate();
  }
  if (rawDate instanceof Date) return rawDate;

  const dateId = data["date_id"];
  if (typeof dateId === "string") {
    const parts = dateId.split("-");
    if (parts.length === 3) {
      const year = Number(parts[0]);
      const month = Number(parts[1]);
      const day = Number(parts[2]);
      if (
        Number.isFinite(year) &&
        Number.isFinite(month) &&
        Number.isFinite(day)
      ) {
        const hourRaw = data["hour_id"]?.toString() ?? "0";
        const hour = Number(hourRaw);
        return new Date(
          year,
          Math.max(0, month - 1),
          day,
          Number.isFinite(hour) ? hour : 0
        );
      }
    }
  }

  return null;
}
