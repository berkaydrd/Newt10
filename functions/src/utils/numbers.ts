/**
 * Converts unknown values to number.
 *
 * @param {unknown} value Unknown input.
 * @return {number} Numeric value or 0.
 */
export function toNumber(value: unknown): number {
  if (typeof value === "number") return value;
  if (typeof value === "string") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : 0;
  }
  return 0;
}
