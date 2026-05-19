/**
 * Seed leaderboards with dummy data.
 * 
 * Usage:
 *   cd functions
 *   npm run build
 *   CONFIRM_SEED_LEADERBOARDS=true node lib/scripts/seed_leaderboards.js
 * 
 * OR:
 *   node lib/scripts/seed_leaderboards.js --yes
 */

import * as admin from 'firebase-admin';
import * as process from 'process';

interface LeaderboardEntry {
  username: string;
  twr_ratio: number;
  rank: number;
  photoUrl: null;
}

const LEADERBOARD_TYPES = ['weekly', 'monthly', 'yearly'] as const;
const ENTRIES_PER_DOC = 10;

function confirmSeed(): void {
  const envConfirmed = process.env.CONFIRM_SEED_LEADERBOARDS === 'true';
  const flagConfirmed = process.argv.includes('--yes');

  if (!envConfirmed && !flagConfirmed) {
    console.error(
      'Aborted: Set CONFIRM_SEED_LEADERBOARDS=true or pass --yes flag to seed leaderboards.'
    );
    process.exit(1);
  }
}

function generateDummyEntries(): LeaderboardEntry[] {
  const entries: LeaderboardEntry[] = [];

  for (let i = 0; i < ENTRIES_PER_DOC; i++) {
    entries.push({
      username: `User${i + 1}`,
      twr_ratio: parseFloat(((ENTRIES_PER_DOC - i) / 100.0).toFixed(2)),
      rank: i + 1,
      photoUrl: null,
    });
  }

  return entries;
}

async function seedLeaderboardDoc(
  db: FirebaseFirestore.Firestore,
  type: string,
  entries: LeaderboardEntry[]
): Promise<void> {
  try {
    await db.collection('leaderboards').doc(type).set({ entries });
    console.log(`  ✓ Seeded: leaderboards/${type}`);
  } catch (error) {
    console.error(`  ✗ Failed to seed leaderboards/${type}:`, error);
    process.exit(1);
  }
}

function printSummary(projectId: string): void {
  console.log(`
✓ Successfully seeded leaderboards:
  Project: ${projectId}
  Documents written: ${LEADERBOARD_TYPES.length} (${LEADERBOARD_TYPES.join(', ')})
  Entries per document: ${ENTRIES_PER_DOC}
  Data is deterministic and idempotent`);
}

async function main(): Promise<void> {
  confirmSeed();

  // Initialize Firebase Admin SDK
  try {
    admin.initializeApp();
  } catch (error) {
    console.error('Failed to initialize Firebase Admin SDK:', error);
    process.exit(1);
  }

  const db = admin.firestore();
  const projectId = admin.app().options.projectId || 'unknown-project';
  const entries = generateDummyEntries();

  console.log('Seeding leaderboards...\n');

  for (const type of LEADERBOARD_TYPES) {
    await seedLeaderboardDoc(db, type, entries);
  }

  printSummary(projectId);
}

main().catch((error) => {
  console.error('Unexpected error during seeding:', error);
  process.exit(1);
});