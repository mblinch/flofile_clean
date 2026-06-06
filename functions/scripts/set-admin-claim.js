/**
 * One-time: grant Firebase Auth custom claim { admin: true } for app-defaults writes.
 *
 * Usage (from repo root, with Application Default Credentials or GOOGLE_APPLICATION_CREDENTIALS):
 *   node functions/scripts/set-admin-claim.js YOUR_FIREBASE_AUTH_UID
 *
 * Find UID: Firebase Console → Authentication → Users.
 */
const admin = require("firebase-admin");

async function main() {
  const uid = process.argv[2];
  if (!uid) {
    console.error("Usage: node functions/scripts/set-admin-claim.js <uid>");
    process.exit(1);
  }
  admin.initializeApp();
  await admin.auth().setCustomUserClaims(uid, { admin: true });
  console.log(`Set admin: true on uid ${uid}`);
  process.exit(0);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
