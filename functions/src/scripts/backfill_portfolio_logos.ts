import {admin, db} from "../app/firebase";

function candidateStockIds(symbol: string): string[] {
  const trimmed = symbol.trim().toUpperCase();
  const ids: string[] = [];
  const add = (value: string) => {
    if (!value) return;
    if (!ids.includes(value)) ids.push(value);
  };

  add(trimmed);

  if (trimmed.includes(".")) {
    add(trimmed.split(".")[0]);
  }

  if (trimmed.endsWith("-USD")) {
    add(trimmed.replace(/-USD$/i, ""));
  }

  if (trimmed.endsWith("=X")) {
    add(trimmed.replace(/=X$/i, ""));
  }

  return ids;
}

async function backfillPortfolioLogos(): Promise<void> {
  const usersSnap = await db.collection("usernames").get();

  let updatedCount = 0;
  let skippedCount = 0;
  let missingStockCount = 0;
  let missingLogoCount = 0;
  let processedCount = 0;

  console.log("Portfolio logo backfill started.", {
    totalUsers: usersSnap.size,
    startedAt: new Date().toISOString(),
  });

  for (const userDoc of usersSnap.docs) {
    console.log("Scanning portfolio.", {username: userDoc.id});
    const portfolioSnap = await userDoc.ref.collection("portfolio").get();
    console.log("Portfolio documents loaded.", {
      username: userDoc.id,
      count: portfolioSnap.size,
    });

    for (const portfolioDoc of portfolioSnap.docs) {
      const data = portfolioDoc.data() as Record<string, unknown>;
      processedCount += 1;
      const existingLogo = data["logo_url"];
      if (typeof existingLogo === "string" && existingLogo.trim().length > 0) {
        skippedCount += 1;
        continue;
      }

      const symbolRaw = data["symbol"];
      if (typeof symbolRaw !== "string" || symbolRaw.trim().length === 0) {
        skippedCount += 1;
        continue;
      }

      const candidates = candidateStockIds(symbolRaw);
      let logoUrl: string | null = null;
      let foundStock = false;

      for (const candidate of candidates) {
        const stockDoc = await db.collection("stocks").doc(candidate).get();
        if (!stockDoc.exists) continue;
        foundStock = true;
        const stockData =
          stockDoc.data() as Record<string, unknown> | undefined;
        const candidateUrl = stockData?.["logo_url"];
        if (typeof candidateUrl === "string" && candidateUrl.trim().length > 0) {
          logoUrl = candidateUrl.trim();
          break;
        }
      }

      if (!foundStock) {
        missingStockCount += 1;
        continue;
      }

      if (!logoUrl) {
        missingLogoCount += 1;
        continue;
      }

      await portfolioDoc.ref.set(
        {
          logo_url: logoUrl,
        },
        {merge: true}
      );
      updatedCount += 1;

      if (processedCount % 100 === 0) {
        console.log("Backfill progress.", {
          processedCount,
          updatedCount,
          skippedCount,
          missingStockCount,
          missingLogoCount,
        });
      }
    }
  }

  console.log("Portfolio logo backfill completed.", {
    updatedCount,
    skippedCount,
    missingStockCount,
    missingLogoCount,
    totalUsers: usersSnap.size,
    processedCount,
  });
}

backfillPortfolioLogos()
  .then(async () => {
    await admin.app().delete();
  })
  .catch(async (error) => {
    console.error("Portfolio logo backfill failed.", error);
    await admin.app().delete();
    process.exitCode = 1;
  });
