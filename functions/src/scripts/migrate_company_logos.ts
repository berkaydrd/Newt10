import {randomUUID} from "crypto";
import {admin, db} from "../app/firebase";

const PREFIX = "company_logos/";
const EXT = ".png";
const DEFAULT_BUCKET = "newtnet-58210.firebasestorage.app";

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

function normalizeSymbolFromPath(filePath: string): string | null {
  const fileName = filePath.split("/").pop();
  if (!fileName) return null;
  if (!fileName.toLowerCase().endsWith(EXT)) return null;
  const base = fileName.slice(0, -EXT.length).trim();
  if (!base) return null;
  return base.toUpperCase();
}

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

async function ensureDownloadToken(file: any): Promise<string> {
  const [metadata] = await file.getMetadata();
  const rawToken = metadata?.metadata?.firebaseStorageDownloadTokens;
  const existingToken =
    typeof rawToken === "string" && rawToken.trim().length > 0
      ? rawToken.split(",")[0].trim()
      : null;

  if (existingToken) return existingToken;

  const newToken = randomUUID();
  const existingMetadata =
    (metadata?.metadata as Record<string, string> | undefined) ?? {};

  await file.setMetadata({
    metadata: {
      ...existingMetadata,
      firebaseStorageDownloadTokens: newToken,
    },
  });

  return newToken;
}

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
