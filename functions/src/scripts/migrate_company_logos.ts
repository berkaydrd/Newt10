import {randomUUID} from "crypto";
import {admin, db} from "../app/firebase";

const PREFIX = "company_logos/";
const EXT = ".png";
const DEFAULT_BUCKET = "newtnet-58210.firebasestorage.app";

/**
 * Resolves the storage bucket name from env with fallback.
 *
 * @return {string} Bucket name.
 */
function resolveBucketName(): string {
  const envBucket =
    process.env.FIREBASE_STORAGE_BUCKET ??
    process.env.STORAGE_BUCKET ??
    process.env.GOOGLE_CLOUD_STORAGE_BUCKET;
  if (envBucket && envBucket.trim().length > 0) {
    return envBucket.trim();
  }
  return DEFAULT_BUCKET;
}

/**
 * Extracts a stock symbol from logo file path.
 *
 * @param {string} filePath File path in bucket.
 * @return {string | null} Normalized symbol or null.
 */
function normalizeSymbolFromPath(filePath: string): string | null {
  const fileName = filePath.split("/").pop();
  if (!fileName) return null;
  if (!fileName.toLowerCase().endsWith(EXT)) return null;
  const base = fileName.slice(0, -EXT.length).trim();
  if (!base) return null;
  return base.toUpperCase();
}

/**
 * Builds a public download URL for a storage object.
 *
 * @param {string} bucketName Storage bucket name.
 * @param {string} filePath File path in bucket.
 * @param {string} token Download token.
 * @return {string} Download URL.
 */
function buildDownloadUrl(
  bucketName: string,
  filePath: string,
  token: string
): string {
  const encodedPath = encodeURIComponent(filePath);
  return (
    "https://firebasestorage.googleapis.com/v0/b/" +
    `${bucketName}/o/${encodedPath}?alt=media&token=${token}`
  );
}

/**
 * Ensures a Firebase Storage download token exists for a file.
 *
 * @param {unknown} file Storage file object.
 * @return {Promise<string>} Existing or newly-created token.
 */
async function ensureDownloadToken(file: unknown): Promise<string> {
  const storageFile = file as {
    getMetadata: () => Promise<[Record<string, unknown>, ...unknown[]]>;
    setMetadata: (
      metadata: {metadata: Record<string, string>}
    ) => Promise<unknown>;
  };

  const [metadata] = await storageFile.getMetadata();
  const userMeta = metadata["metadata"] as Record<string, unknown> | undefined;
  const rawToken = userMeta?.["firebaseStorageDownloadTokens"];
  let existingToken: string | null = null;
  if (typeof rawToken === "string" && rawToken.trim().length > 0) {
    existingToken = rawToken.split(",")[0].trim();
  }

  if (existingToken) return existingToken;

  const newToken = randomUUID();
  const existingMetadata =
    (metadata?.metadata as Record<string, string> | undefined) ?? {};

  await storageFile.setMetadata({
    metadata: {
      ...existingMetadata,
      firebaseStorageDownloadTokens: newToken,
    },
  });

  return newToken;
}

/**
 * Migrates company logos from storage to stocks collection.
 *
 * @return {Promise<void>} Promise resolved when migration finishes.
 */
async function migrateCompanyLogos(): Promise<void> {
  const bucketName = resolveBucketName();
  const bucket = admin.storage().bucket(bucketName);
  const [files] = await bucket.getFiles({prefix: PREFIX});

  let createdCount = 0;
  let updatedCount = 0;
  let skippedCount = 0;

  for (const file of files) {
    if (file.name.endsWith("/")) {
      skippedCount += 1;
      continue;
    }

    const symbol = normalizeSymbolFromPath(file.name);
    if (!symbol) {
      skippedCount += 1;
      continue;
    }

    const docRef = db.collection("stocks").doc(symbol);
    const docSnap = await docRef.get();

    const token = await ensureDownloadToken(file);
    const url = buildDownloadUrl(bucket.name, file.name, token);

    if (docSnap.exists) {
      await docRef.set(
        {
          logo_url: url,
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      updatedCount += 1;
    } else {
      await docRef.set(
        {
          symbol: symbol,
          logo_url: url,
          last_updated: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true}
      );
      createdCount += 1;
    }
  }

  console.log("Logo migration completed.", {
    createdCount,
    updatedCount,
    skippedCount,
    totalFiles: files.length,
  });
}

migrateCompanyLogos()
  .then(async () => {
    await admin.app().delete();
  })
  .catch(async (error) => {
    console.error("Logo migration failed.", error);
    await admin.app().delete();
    process.exitCode = 1;
  });
