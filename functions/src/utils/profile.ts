/**
 * Resolves profile image URL from a user document.
 *
 * @param {Record<string, unknown>} data User document data.
 * @return {string | null} Profile image URL or null.
 */
export function resolveProfileImagePath(
  data: Record<string, unknown>
): string | null {
  const raw =
    data["profile_image_path"] ??
    data["photoUrl"] ??
    data["photo_url"] ??
    null;
  if (typeof raw !== "string") return null;
  const trimmed = raw.trim();
  return trimmed.length > 0 ? trimmed : null;
}
