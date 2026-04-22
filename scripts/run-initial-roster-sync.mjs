/**
 * One-shot: write roster_sync/config from a local JSON file, then sync all jobs.
 *
 * Usage:
 *   export FIREBASE_SERVICE_ACCOUNT_JSON="$(cat ~/path/to/serviceAccount.json)"
 *   node run-initial-roster-sync.mjs ../tool/roster_sync_initial.example.json
 *   node run-initial-roster-sync.mjs ../tool/roster_sync_mlb_all.example.json
 *
 * JSON shapes:
 *   { "enabled": true, "items": [ { "sportId": "baseball", "teamId": "121" } ] }
 *   { "enabled": true, "syncAllMlb": true }   — every MLB team from statsapi.mlb.com
 *
 * Each sync reconciles players against the league's current roster (adds new,
 * deletes gone, updates changed) and writes coach fields on the team doc only
 * when the league provides them and they actually changed (baseball: four
 * roles; basketball / hockey: head coach).
 */

import fs from "fs";
import {
  initAdmin,
  syncJobs,
  fetchMlbAllTeamJobs,
} from "./roster-sync-core.mjs";

const path = process.argv[2];
if (!path) {
  console.error("Usage: node run-initial-roster-sync.mjs <config.json>");
  process.exit(1);
}

const body = JSON.parse(fs.readFileSync(path, "utf8"));
const enabled = body.enabled !== false;
let items = Array.isArray(body.items) ? body.items : [];
const syncAllMlb = body.syncAllMlb === true;

if (syncAllMlb) {
  console.log("Loading all MLB team IDs …");
  items = await fetchMlbAllTeamJobs();
} else if (items.length === 0) {
  console.error(
    'config.json needs either "syncAllMlb": true or a non-empty "items" array.',
  );
  process.exit(1);
}

const db = initAdmin();
const firestorePayload = {
  enabled,
  items,
  ...(syncAllMlb ? { syncAllMlb: true } : {}),
};
await db.doc("roster_sync/config").set(firestorePayload, { merge: true });
console.log(
  `Saved roster_sync/config (enabled=${enabled}, ${items.length} job(s)${syncAllMlb ? ", syncAllMlb" : ""}).`,
);

const delayMs = syncAllMlb ? 400 : 0;
await syncJobs(db, items, { delayBetweenJobsMs: delayMs });
console.log("Initial sync finished.");
