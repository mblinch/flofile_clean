/**
 * Overwrite every user's caption wire defaults + game identifiers with the
 * published admin originals from appDefaults/current.
 *
 * Leaves verbs, FTP, IPTC personal settings, etc. untouched.
 *
 * Dry-run:
 *   node functions/scripts/overwrite-user-captions-from-admin.js
 * Apply:
 *   node functions/scripts/overwrite-user-captions-from-admin.js --apply
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const https = require("https");
const { execFileSync } = require("child_process");

const PROJECT = "projectflo-e99c6";
const ROOT = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const CAPTION_PREF_KEYS = [
  "captionTemplateWireDefaults",
  "gameIdentifierByWireAndSport",
];

function loadToken() {
  const file = path.join(
    os.homedir(),
    ".config",
    "configstore",
    "firebase-tools.json",
  );
  const token = JSON.parse(fs.readFileSync(file, "utf8"))?.tokens?.access_token;
  if (!token) throw new Error("No Firebase CLI access token");
  return token;
}

function request(method, url, token, body) {
  return new Promise((resolve, reject) => {
    const parsed = new URL(url);
    const req = https.request(
      {
        method,
        hostname: parsed.hostname,
        path: parsed.pathname + parsed.search,
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
          ...(body ? { "Content-Length": Buffer.byteLength(body) } : {}),
        },
      },
      (res) => {
        let data = "";
        res.on("data", (chunk) => (data += chunk));
        res.on("end", () => {
          const status = res.statusCode || 0;
          if (status >= 400) {
            reject(
              new Error(`${method} ${parsed.pathname} -> ${status}: ${data}`),
            );
            return;
          }
          resolve(data ? JSON.parse(data) : {});
        });
      },
    );
    req.on("error", reject);
    if (body) req.write(body);
    req.end();
  });
}

function deepClone(value) {
  return JSON.parse(JSON.stringify(value));
}

function stableJson(node) {
  if (node == null || typeof node !== "object") return JSON.stringify(node);
  if (Array.isArray(node)) {
    return `[${node.map(stableJson).join(",")}]`;
  }
  const keys = Object.keys(node).sort();
  return `{${keys.map((k) => `${JSON.stringify(k)}:${stableJson(node[k])}`).join(",")}}`;
}

function fieldSummary(field) {
  if (!field) return null;
  if (field.mapValue?.fields) {
    return Object.keys(field.mapValue.fields).sort();
  }
  if (field.arrayValue?.values) {
    return { arrayLength: field.arrayValue.values.length };
  }
  return Object.keys(field);
}

function authUsers() {
  const out = path.join(os.tmpdir(), "flofile-users-overwrite-captions.json");
  execFileSync(
    "firebase",
    ["auth:export", out, "--format=json", `--project=${PROJECT}`],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
  return JSON.parse(fs.readFileSync(out, "utf8")).users || [];
}

function applyAdminCaptionsToPrefsDoc(prefsDoc, adminFields) {
  if (!prefsDoc.fields) prefsDoc.fields = {};
  if (!prefsDoc.fields.preferences) {
    prefsDoc.fields.preferences = { mapValue: { fields: {} } };
  }
  if (!prefsDoc.fields.preferences.mapValue) {
    prefsDoc.fields.preferences.mapValue = { fields: {} };
  }
  if (!prefsDoc.fields.preferences.mapValue.fields) {
    prefsDoc.fields.preferences.mapValue.fields = {};
  }

  const prefFields = prefsDoc.fields.preferences.mapValue.fields;
  const before = {};
  const after = {};
  let changed = false;

  for (const key of CAPTION_PREF_KEYS) {
    const adminValue = adminFields[key];
    if (!adminValue) continue;
    before[key] = fieldSummary(prefFields[key]);
    const next = deepClone(adminValue);
    if (stableJson(prefFields[key] || null) !== stableJson(next)) {
      changed = true;
    }
    prefFields[key] = next;
    after[key] = fieldSummary(prefFields[key]);
  }

  const nowMs = Date.now();
  prefsDoc.fields.updatedAtMs = { integerValue: String(nowMs) };
  prefsDoc.fields.updatedAt = {
    timestampValue: new Date(nowMs).toISOString(),
  };

  return { changed, before, after, updatedAtMs: nowMs };
}

async function main() {
  const apply = process.argv.includes("--apply");
  const token = loadToken();
  const report = {
    apply,
    admin: {},
    users: [],
    scannedUsers: 0,
    changedUsers: 0,
    unchangedUsers: 0,
    missingPrefs: 0,
  };

  const defaults = await request("GET", `${ROOT}/appDefaults/current`, token);
  const adminFields = defaults.fields || {};
  for (const key of CAPTION_PREF_KEYS) {
    if (!adminFields[key]) {
      throw new Error(`appDefaults/current missing ${key}`);
    }
    report.admin[key] = fieldSummary(adminFields[key]);
  }

  for (const user of authUsers()) {
    report.scannedUsers += 1;
    const uid = user.localId;
    const email = user.email || null;
    try {
      const prefs = await request(
        "GET",
        `${ROOT}/users/${uid}/preferences/current`,
        token,
      );
      const result = applyAdminCaptionsToPrefsDoc(prefs, adminFields);
      const entry = {
        uid,
        email,
        changed: result.changed,
        before: result.before,
        after: result.after,
      };
      report.users.push(entry);
      if (result.changed) report.changedUsers += 1;
      else report.unchangedUsers += 1;

      if (apply) {
        await request(
          "PATCH",
          `${ROOT}/users/${uid}/preferences/current`,
          token,
          JSON.stringify({ fields: prefs.fields }),
        );
        entry.applied = true;
        entry.updatedAtMs = result.updatedAtMs;
      }
    } catch (error) {
      const message = String(error.message || error);
      if (message.includes("404")) {
        report.missingPrefs += 1;
        report.users.push({ uid, email, missingPrefs: true });
      } else {
        report.users.push({ uid, email, error: message });
      }
    }
  }

  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
