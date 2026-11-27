/**
 * Force every user's verb catalog to the published admin originals, while
 * keeping each account's personal customVerbs (+ favorites).
 *
 * Dry-run:
 *   node functions/scripts/overwrite-user-verbs-from-admin.js
 * Apply:
 *   node functions/scripts/overwrite-user-verbs-from-admin.js --apply
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const https = require("https");
const { execFileSync } = require("child_process");

const PROJECT = "projectflo-e99c6";
const ROOT = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;

const PRESERVE_KEYS = new Set([
  "customVerbs",
  "favoriteVerbs",
  "favoritePlayers",
  "favoriteTeams",
]);

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

function decode(node) {
  if (node == null || typeof node !== "object") return node;
  if ("stringValue" in node) return node.stringValue;
  if ("integerValue" in node) return Number(node.integerValue);
  if ("doubleValue" in node) return node.doubleValue;
  if ("booleanValue" in node) return node.booleanValue;
  if ("nullValue" in node) return null;
  if ("timestampValue" in node) return node.timestampValue;
  if ("arrayValue" in node) {
    return (node.arrayValue.values || []).map(decode);
  }
  if ("mapValue" in node) {
    const out = {};
    for (const [key, value] of Object.entries(node.mapValue.fields || {})) {
      out[key] = decode(value);
    }
    return out;
  }
  return node;
}

function encode(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (typeof value === "number") {
    if (Number.isInteger(value)) return { integerValue: String(value) };
    return { doubleValue: value };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(encode) } };
  }
  if (typeof value === "object") {
    const fields = {};
    for (const [key, child] of Object.entries(value)) {
      fields[key] = encode(child);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(value) };
}

function verbKey(raw) {
  if (!raw || typeof raw !== "object") return "";
  return String(raw.key || raw.label || "")
    .trim()
    .toLowerCase();
}

function mergeCustoms(adminCustoms, userCustoms, adminOverrides) {
  const byKey = new Map();
  for (const item of adminCustoms || []) {
    const key = verbKey(item);
    if (!key) continue;
    byKey.set(key, item);
  }
  for (const item of userCustoms || []) {
    const key = verbKey(item);
    if (!key) continue;
    if (byKey.has(key)) continue;
    if (adminOverrides && Object.prototype.hasOwnProperty.call(adminOverrides, item.key || item.label)) {
      continue;
    }
    // Also skip if override map uses same casing variants.
    const overrideHit = Object.keys(adminOverrides || {}).some(
      (k) => k.trim().toLowerCase() === key,
    );
    if (overrideHit) continue;
    byKey.set(key, item);
  }
  return Array.from(byKey.values());
}

function authUsers() {
  const out = path.join(os.tmpdir(), "flofile-users-overwrite-verbs.json");
  execFileSync(
    "firebase",
    ["auth:export", out, "--format=json", `--project=${PROJECT}`],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
  return JSON.parse(fs.readFileSync(out, "utf8")).users || [];
}

function adminSliceForSport(adminVerbs, sport) {
  if (adminVerbs[sport]) return adminVerbs[sport];
  if (sport === "wnba" && adminVerbs.basketball) return adminVerbs.basketball;
  return null;
}

function applyAdminVerbsToPrefsDoc(prefsDoc, adminVerbs) {
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
  const userVerbs = decode(prefFields.verbSettingsBySport) || {};
  const nextBySport = {};
  const report = { sports: {}, preservedCustoms: {} };
  let changed = false;

  const sports = new Set([
    ...Object.keys(adminVerbs || {}),
    ...Object.keys(userVerbs || {}),
    "wnba",
  ]);

  for (const sport of sports) {
    const adminSlice = adminSliceForSport(adminVerbs, sport);
    if (!adminSlice) continue;
    const userSlice = userVerbs[sport] || {};
    const mergedCustoms = mergeCustoms(
      adminSlice.customVerbs || [],
      userSlice.customVerbs || [],
      adminSlice.verbOverrides || {},
    );
    const next = { ...deepClone(adminSlice) };
    next.customVerbs = mergedCustoms;
    for (const key of PRESERVE_KEYS) {
      if (key === "customVerbs") continue;
      if (Array.isArray(userSlice[key])) next[key] = deepClone(userSlice[key]);
    }
    nextBySport[sport] = next;
    report.sports[sport] = {
      adminOverrides: Object.keys(adminSlice.verbOverrides || {}).length,
      customBefore: (userSlice.customVerbs || []).length,
      customAfter: mergedCustoms.length,
    };
    report.preservedCustoms[sport] = mergedCustoms.length;
    const before = JSON.stringify(userSlice);
    const after = JSON.stringify(next);
    if (before !== after) changed = true;
  }

  prefFields.verbSettingsBySport = encode(nextBySport);

  const nowMs = Date.now();
  prefsDoc.fields.updatedAtMs = { integerValue: String(nowMs) };
  prefsDoc.fields.updatedAt = {
    timestampValue: new Date(nowMs).toISOString(),
  };

  return { changed, report, updatedAtMs: nowMs };
}

async function main() {
  const apply = process.argv.includes("--apply");
  const token = loadToken();
  const report = {
    apply,
    adminSports: [],
    users: [],
    scannedUsers: 0,
    changedUsers: 0,
    unchangedUsers: 0,
    missingPrefs: 0,
  };

  const defaults = await request("GET", `${ROOT}/appDefaults/current`, token);
  const adminVerbs = decode(defaults.fields?.verbSettingsBySport);
  if (!adminVerbs || typeof adminVerbs !== "object") {
    throw new Error("appDefaults/current missing verbSettingsBySport");
  }
  report.adminSports = Object.keys(adminVerbs).sort();

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
      const result = applyAdminVerbsToPrefsDoc(prefs, adminVerbs);
      const entry = {
        uid,
        email,
        changed: result.changed,
        ...result.report,
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
