/**
 * Nightly roster fetch → Firestore (same paths and head-coach sources as the Flutter app).
 *
 * Firestore document: roster_sync/config
 *   enabled?: boolean   (default true)
 *   syncAllMlb?: boolean — if true, pulls every MLB team from statsapi.mlb.com (ignores items).
 *   items: { sportId: string, teamId: string }[]  — used when syncAllMlb is not true
 *
 * Per team this reconciles players (add / delete / update only what changed;
 * doc id = stable league player id) and the team doc coach fields when the
 * sport provides them (baseball: manager + pitching / first / third from MLB
 * coaches; basketball: ESPN NBA; hockey: ESPN NHL by tri-code). Timestamps
 * (`teamUpdatedAt`, `coachStaffUpdatedAt`) move only when that data changes.
 *
 * Env: FIREBASE_SERVICE_ACCOUNT_JSON — Firebase Admin SDK service account JSON.
 */

import { initAdmin, syncJobs, fetchMlbAllTeamJobs } from "./roster-sync-core.mjs";

async function main() {
  const db = initAdmin();
  const snap = await db.doc("roster_sync/config").get();
  if (!snap.exists) {
    console.log(
      "No roster_sync/config — in Firestore create document roster_sync/config with enabled=true and syncAllMlb=true (MLB only).",
    );
    process.exit(0);
  }
  const data = snap.data() ?? {};
  if (data.enabled === false) {
    console.log("roster_sync/config.enabled is false — skipping.");
    process.exit(0);
  }

  let items = Array.isArray(data.items) ? data.items : [];
  if (data.syncAllMlb === true) {
    console.log("syncAllMlb: loading all MLB team IDs from statsapi.mlb.com …");
    items = await fetchMlbAllTeamJobs();
    console.log(`  ${items.length} MLB teams`);
  }

  if (items.length === 0) {
    console.log(
      "Nothing to sync. Set syncAllMlb: true or add items: [{ sportId, teamId }, …] on roster_sync/config.",
    );
    process.exit(0);
  }

  const delayMs = data.syncAllMlb === true ? 400 : 0;
  await syncJobs(db, items, { delayBetweenJobsMs: delayMs });
  console.log("Done.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
