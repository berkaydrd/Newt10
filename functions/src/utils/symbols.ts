/**
 * Converts unknown values to a symbol string.
 *
 * @param {unknown} value Unknown input.
 * @return {string | null} Symbol or null.
 */
export function toSymbol(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
}

/**
 * Resolves the Yahoo symbol for event checks.
 *
 * @param {Record<string, unknown>} data Portfolio item.
 * @return {string | null} Yahoo symbol.
 */
export function resolveEventSymbol(
  data: Record<string, unknown>
): string | null {
  const symbol = toSymbol(data["symbol"]);
  if (!symbol) return null;
  const upper = symbol.toUpperCase();
  const currency =
    (data["currency"] ?? "").toString().toUpperCase();
  if (upper.endsWith(".IS")) return upper;
  if (currency === "TRY") return `${upper}.IS`;
  return upper;
}
