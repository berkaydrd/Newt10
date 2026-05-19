import {toNumber} from "./numbers";

/**
 * Ensures the event map has object shape.
 *
 * @param {unknown} value Unknown input.
 * @return {Record<string, unknown> | null} Event object.
 */
export function toEvent(value: unknown): Record<string, unknown> | null {
  if (!value || typeof value !== "object") return null;
  return value as Record<string, unknown>;
}

/**
 * Parses split ratio from Yahoo event data.
 *
 * @param {Record<string, unknown>} event Split event data.
 * @return {number} Split ratio.
 */
export function parseSplitRatio(event: Record<string, unknown>): number {
  const numerator = toNumber(event["numerator"]);
  const denominator = toNumber(event["denominator"]);
  if (numerator > 0 && denominator > 0) {
    return numerator / denominator;
  }
  const ratio = event["splitRatio"]?.toString();
  if (ratio && ratio.includes("/")) {
    const parts = ratio.split("/");
    const num = Number(parts[0]);
    const den = Number(parts[1]);
    if (Number.isFinite(num) && Number.isFinite(den) && den > 0) {
      return num / den;
    }
  }
  return 1;
}

/**
 * Formats split ratio text.
 *
 * @param {Record<string, unknown>} event Split event data.
 * @param {number} ratio Parsed ratio.
 * @return {string} Ratio text.
 */
export function ratioText(
  event: Record<string, unknown>,
  ratio: number
): string {
  const ratioTextRaw = event["splitRatio"]?.toString();
  if (ratioTextRaw && ratioTextRaw.includes("/")) {
    return ratioTextRaw.replace(/\//g, ":");
  }
  if (ratio > 0) return ratio.toFixed(2);
  return "N/A";
}
