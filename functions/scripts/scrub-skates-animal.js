/**
 * Replace banned hockey skate phrases with "skates" in every user prefs doc
 * and appDefaults.
 *
 * Dry-run:
 *   node functions/scripts/scrub-skates-animal.js
 * Apply:
 *   node functions/scripts/scrub-skates-animal.js --apply
 */
const fs = require("fs");
const os = require("os");
const path = require("path");
const https = require("https");
const { execFileSync } = require("child_process");

const PROJECT = "projectflo-e99c6";
const ROOT = `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents`;
const CANONICAL = "skates";
const BANNED_RE =
  /\bskat(?:e|es|ing)\s+like\s+a(?:\s+fucking)?\s+animal\b/gi;

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
            reject(new Error(`${method} ${parsed.pathname} -> ${status}: ${data}`));
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

function scrubString(text) {
  BANNED_RE.lastIndex = 0;
  if (!BANNED_RE.test(text)) return { value: text, changed: false };
  BANNED_RE.lastIndex = 0;
  let next = text.replace(BANNED_RE, CANONICAL);
  next = next.replace(/\bskates(\s+skates)+\b/gi, CANONICAL);
  return { value: next, changed: next !== text };
}

function scrubFirestoreValue(node, path, hits) {
  if (!node || typeof node !== "object") return node;

  if ("stringValue" in node) {
    const result = scrubString(node.stringValue);
    if (result.changed) {
      hits.push({ path, from: node.stringValue, to: result.value });
      return { stringValue: result.value };
    }
    return node;
  }

  if ("arrayValue" in node) {
    const original = node.arrayValue.values || [];
    const values = original.map((item, index) =>
      scrubFirestoreValue(item, `${path}[${index}]`, hits),
    );
    // If a banned phrase became "skates" and that key already existed in the
    // same verb-order list, drop only the renamed duplicate.
    const isVerbOrder =
      /\.verbOrder(\.|$)/.test(path) || path.includes("verbOrder.");
    if (!isVerbOrder) {
      return { arrayValue: { values } };
    }
    const existedBefore = new Set(
      original
        .filter((item) => item && "stringValue" in item)
        .map((item) => item.stringValue.trim().toLowerCase()),
    );
    const deduped = [];
    for (let index = 0; index < values.length; index++) {
      const item = values[index];
      const before = original[index];
      const beforeText =
        before && "stringValue" in before ? before.stringValue : null;
      const afterText =
        item && "stringValue" in item ? item.stringValue : null;
      const renamedToSkates =
        !!beforeText &&
        !!afterText &&
        beforeText !== afterText &&
        afterText.trim().toLowerCase() === "skates";
      if (
        renamedToSkates &&
        (existedBefore.has("skates") || existedBefore.has("skates"))
      ) {
        hits.push({
          path: `${path}[dedupe]`,
          from: beforeText,
          to: "(removed duplicate skates)",
        });
        continue;
      }
      deduped.push(item);
    }
    return { arrayValue: { values: deduped } };
  }

  if ("mapValue" in node) {
    const fields = node.mapValue.fields || {};
    const nextFields = {};
    for (const [key, child] of Object.entries(fields)) {
      const keyResult = scrubString(key);
      let nextKey = keyResult.value;
      if (keyResult.changed) {
        hits.push({ path: `${path}.{key}`, from: key, to: nextKey });
        // Prefer canonical factory key casing when colliding with Skates/skates.
        if (nextKey.toLowerCase() === "skates" && fields.Skates && !fields.skates) {
          nextKey = "Skates";
        } else if (nextKey.toLowerCase() === "skates" && fields.skates) {
          nextKey = "skates";
        }
      }
      const scrubbedChild = scrubFirestoreValue(
        child,
        `${path}.${nextKey}`,
        hits,
      );
      if (nextFields[nextKey]) {
        // Merge: keep existing, drop duplicate key after rename.
        hits.push({
          path: `${path}.${nextKey}`,
          from: key,
          to: `(merged into existing ${nextKey})`,
        });
        continue;
      }
      nextFields[nextKey] = scrubbedChild;
    }
    return { mapValue: { fields: nextFields } };
  }

  return node;
}

function scrubDocument(doc) {
  const hits = [];
  const fields = {};
  for (const [key, value] of Object.entries(doc.fields || {})) {
    fields[key] = scrubFirestoreValue(value, key, hits);
  }
  return {
    doc: { ...doc, fields },
    hits,
    changed: hits.length > 0,
  };
}

function authUsers() {
  const out = path.join(os.tmpdir(), "flofile-users-scrub.json");
  execFileSync(
    "firebase",
    ["auth:export", out, "--format=json", `--project=${PROJECT}`],
    { stdio: ["ignore", "pipe", "pipe"] },
  );
  return JSON.parse(fs.readFileSync(out, "utf8")).users || [];
}

async function main() {
  const apply = process.argv.includes("--apply");
  const token = loadToken();
  const report = {
    apply,
    appDefaults: { changed: false, hits: [] },
    users: [],
    scannedUsers: 0,
    missingPrefs: 0,
  };

  try {
    const defaults = await request(
      "GET",
      `${ROOT}/appDefaults/current`,
      token,
    );
    const scrubbed = scrubDocument(defaults);
    report.appDefaults = { changed: scrubbed.changed, hits: scrubbed.hits };
    if (apply && scrubbed.changed) {
      await request(
        "PATCH",
        `${ROOT}/appDefaults/current`,
        token,
        JSON.stringify({ fields: scrubbed.doc.fields }),
      );
    }
  } catch (error) {
    report.appDefaults = { error: String(error.message || error) };
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
      const scrubbed = scrubDocument(prefs);
      if (!scrubbed.changed) continue;
      report.users.push({
        uid,
        email,
        hitCount: scrubbed.hits.length,
        hits: scrubbed.hits,
      });
      if (apply) {
        await request(
          "PATCH",
          `${ROOT}/users/${uid}/preferences/current`,
          token,
          JSON.stringify({ fields: scrubbed.doc.fields }),
        );
      }
    } catch (error) {
      const message = String(error.message || error);
      if (message.includes("404")) report.missingPrefs += 1;
      else report.users.push({ uid, email, error: message });
    }
  }

  console.log(JSON.stringify(report, null, 2));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
