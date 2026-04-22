/**
 * Shared roster fetch + Firestore reconcile (used by nightly and initial sync).
 *
 * Reconcile strategy (cheap + quiet):
 *   1. Fetch the current roster + coaches + team name from the league API.
 *   2. Read the current state of `sports/{sportId}/teams/{teamId}` and its
 *      `players` subcollection from Firestore in one batched read.
 *   3. Diff against the API payload and only write what actually changed:
 *        - add new players (docId = stable league player id)
 *        - delete players no longer on the roster
 *        - update existing players only if a visible field changed
 *          (fullName / firstName / jerseyNumber / displayName)
 *        - update the team doc (displayName + coach fields) only if a value
 *          changed; timestamps advance only when the related data did.
 *
 * Firestore document layout:
 *   sports/{sportId}/teams/{teamId}
 *     displayName, teamUpdatedAt, coachStaffUpdatedAt,
 *     headCoach, pitchingCoach, firstBaseCoach, thirdBaseCoach
 *   sports/{sportId}/teams/{teamId}/players/{leaguePlayerId}
 *     fullName, firstName, jerseyNumber, displayName, playerId, updatedAt
 */

import admin from "firebase-admin";

const MLB_HOST = "statsapi.mlb.com";
const NHL_HOST = "api-web.nhle.com";
const ESPN = "site.api.espn.com";

const COACH_KEYS = ["headCoach", "pitchingCoach", "firstBaseCoach", "thirdBaseCoach"];
const PLAYER_FIELDS = ["fullName", "firstName", "jerseyNumber", "displayName"];

/**
 * Stable Firestore doc id for a player. Prefers the league's own player id
 * (MLB personId, NHL player id, ESPN athlete id); falls back to a name/jersey
 * slug for the rare case where no id is available.
 */
function playerDocId(p) {
  const pid = p.playerId != null ? String(p.playerId).trim() : "";
  if (pid) return pid;
  const j = (p.jerseyNumber ?? "").toString().trim();
  const slug = (p.fullName ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return j ? `${j}_${slug}` : slug || "unknown";
}

async function fetchJson(url) {
  const res = await fetch(url, { headers: { "User-Agent": "caption-writer-roster-sync/1" } });
  if (!res.ok) throw new Error(`${url} → ${res.status}`);
  return res.json();
}

async function fetchMlbRoster(teamId) {
  const url = `https://${MLB_HOST}/api/v1/teams/${teamId}/roster?rosterType=active`;
  const data = await fetchJson(url);
  const rosterList = data.roster ?? [];
  return rosterList.map((row) => {
    const person = row.person ?? {};
    const fullName = person.fullName ?? "";
    const firstName = fullName.split(" ")[0] ?? fullName;
    const jerseyNumber = row.jerseyNumber != null ? String(row.jerseyNumber) : null;
    const displayName =
      jerseyNumber && jerseyNumber.length > 0 ? `${fullName} #${jerseyNumber}` : fullName;
    const playerId = person.id != null ? String(person.id) : null;
    return { fullName, firstName, jerseyNumber, displayName, playerId };
  });
}

/** MLB coaching staff from statsapi `/teams/{id}/coaches` (same jobs as the app). */
async function fetchMlbCoachingStaff(teamId) {
  const data = await fetchJson(`https://${MLB_HOST}/api/v1/teams/${teamId}/coaches`);
  const roster = data.roster ?? [];
  function nameForJob(job) {
    const row = roster.find(
      (c) => String(c.job ?? "").toLowerCase() === job.toLowerCase(),
    );
    const name = row?.person?.fullName?.trim();
    return name || null;
  }
  return {
    headCoach: nameForJob("Manager"),
    pitchingCoach: nameForJob("Pitching Coach"),
    firstBaseCoach: nameForJob("First Base Coach"),
    thirdBaseCoach: nameForJob("Third Base Coach"),
  };
}

function nhlParsePlayer(playerJson) {
  const firstName = playerJson.firstName?.default ?? "";
  const lastName = playerJson.lastName?.default ?? "";
  const jerseyNumber =
    playerJson.sweaterNumber != null ? String(playerJson.sweaterNumber) : null;
  const fullName = `${firstName} ${lastName}`.trim();
  const displayName =
    jerseyNumber && jerseyNumber.length > 0 ? `${fullName} #${jerseyNumber}` : fullName;
  const playerId = playerJson.id != null ? String(playerJson.id) : null;
  return { fullName, firstName, jerseyNumber, displayName, playerId };
}

async function fetchNhlRoster(triCode) {
  const code = triCode.length <= 3 ? triCode : triCode.slice(0, 3);
  const url = `https://${NHL_HOST}/v1/roster/${code}/current`;
  const data = await fetchJson(url);
  const lists = ["forwards", "defensemen", "goalies"];
  const all = [];
  for (const key of lists) {
    const arr = data[key];
    if (Array.isArray(arr)) {
      for (const p of arr) all.push(nhlParsePlayer(p));
    }
  }
  return all;
}

function extractEspnAthletes(data) {
  const raw = data.athletes;
  if (!raw || !Array.isArray(raw)) return [];
  const out = [];
  for (const el of raw) {
    if (el.items && Array.isArray(el.items)) {
      for (const a of el.items) out.push(a);
    } else {
      out.push(el);
    }
  }
  return out;
}

/** ESPN roster `coach` array (NBA, NHL, …). */
function parseEspnRosterCoach(coachField) {
  if (!Array.isArray(coachField) || coachField.length === 0) return null;
  const m = coachField[0];
  if (!m || typeof m !== "object") return null;
  if (m.fullName && String(m.fullName).trim()) return String(m.fullName).trim();
  const first = (m.firstName ?? "").toString().trim();
  const last = (m.lastName ?? "").toString().trim();
  const combined = `${first} ${last}`.trim();
  return combined || null;
}

/** [teamId] is NHL tri-code (e.g. BOS); resolves ESPN team id then reads roster `coach`. */
async function fetchEspnNhlHeadCoachByTriCode(triCode) {
  const code = String(triCode).trim().toUpperCase();
  if (code.length !== 3) return null;
  const teamsData = await fetchJson(
    `https://${ESPN}/apis/site/v2/sports/hockey/nhl/teams?limit=100`,
  );
  const teamsList = teamsData.sports?.[0]?.leagues?.[0]?.teams;
  if (!Array.isArray(teamsList)) return null;
  const row = teamsList.find(
    (t) => String(t.team?.abbreviation ?? "").toUpperCase() === code,
  );
  if (!row?.team?.id) return null;
  const id = String(row.team.id);
  const rosterData = await fetchJson(
    `https://${ESPN}/apis/site/v2/sports/hockey/nhl/teams/${id}/roster`,
  );
  return parseEspnRosterCoach(rosterData.coach);
}

function parseEspnAthlete(map) {
  const fullName = map.fullName ?? "";
  const jersey = map.jersey != null ? String(map.jersey) : null;
  const firstName = map.firstName ?? fullName.split(" ")[0] ?? fullName;
  const displayName =
    jersey && jersey.length > 0 ? `${fullName} #${jersey}` : fullName;
  const playerId = map.id != null ? String(map.id) : null;
  return { fullName, firstName, jerseyNumber: jersey, displayName, playerId };
}

async function fetchEspnNbaRoster(teamId) {
  const path = `/apis/site/v2/sports/basketball/nba/teams/${teamId}/roster`;
  const data = await fetchJson(`https://${ESPN}${path}`);
  const players = extractEspnAthletes(data).map(parseEspnAthlete);
  const headCoach = parseEspnRosterCoach(data.coach);
  return { players, headCoach };
}

async function fetchEspnMlsRoster(teamId) {
  const path = `/apis/site/v2/sports/soccer/usa.1/teams/${teamId}/roster`;
  const data = await fetchJson(`https://${ESPN}${path}`);
  return extractEspnAthletes(data).map(parseEspnAthlete);
}

/** Full team name for Firestore `teams/{teamId}.displayName` (same idea as the app). */
export async function fetchTeamDisplayName(sportId, teamId) {
  switch (String(sportId)) {
    case "baseball": {
      const data = await fetchJson(`https://${MLB_HOST}/api/v1/teams/${teamId}`);
      const t = data.teams?.[0];
      const name = t?.name ?? t?.teamName;
      return name ? String(name).trim() : null;
    }
    case "basketball":
      return fetchEspnTeamDisplayNameById("basketball/nba", teamId);
    case "hockey":
      return fetchEspnNhlTeamDisplayNameByTri(teamId);
    case "soccer":
      return fetchEspnTeamDisplayNameById("soccer/usa.1", teamId);
    default:
      return null;
  }
}

async function fetchEspnTeamDisplayNameById(leaguePath, teamId) {
  const idStr = String(teamId);
  const data = await fetchJson(
    `https://${ESPN}/apis/site/v2/sports/${leaguePath}/teams?limit=100`,
  );
  const teamsList = data.sports?.[0]?.leagues?.[0]?.teams;
  if (!Array.isArray(teamsList)) return null;
  const row = teamsList.find((x) => String(x.team?.id) === idStr);
  const t = row?.team;
  const n = (t?.displayName || t?.name || "").trim();
  return n || null;
}

async function fetchEspnNhlTeamDisplayNameByTri(triCode) {
  const code = String(triCode).trim().toUpperCase();
  if (code.length !== 3) return null;
  const data = await fetchJson(
    `https://${ESPN}/apis/site/v2/sports/hockey/nhl/teams?limit=100`,
  );
  const teamsList = data.sports?.[0]?.leagues?.[0]?.teams;
  const row = teamsList?.find(
    (x) => String(x.team?.abbreviation ?? "").toUpperCase() === code,
  );
  const t = row?.team;
  const n = (t?.displayName || t?.name || "").trim();
  return n || null;
}

/**
 * @returns {{
 *   players: object[],
 *   headCoach: string|null,
 *   pitchingCoach: string|null,
 *   firstBaseCoach: string|null,
 *   thirdBaseCoach: string|null,
 * }}
 */
export async function fetchRoster(sportId, teamId) {
  const noMlbStaff = {
    pitchingCoach: null,
    firstBaseCoach: null,
    thirdBaseCoach: null,
  };
  switch (sportId) {
    case "baseball": {
      const players = await fetchMlbRoster(teamId);
      const staff = await fetchMlbCoachingStaff(teamId);
      return { players, ...staff };
    }
    case "hockey": {
      const players = await fetchNhlRoster(teamId);
      const headCoach = await fetchEspnNhlHeadCoachByTriCode(teamId);
      return { players, headCoach, ...noMlbStaff };
    }
    case "basketball": {
      const r = await fetchEspnNbaRoster(teamId);
      return { players: r.players, headCoach: r.headCoach, ...noMlbStaff };
    }
    case "soccer":
      return {
        players: await fetchEspnMlsRoster(teamId),
        headCoach: null,
        ...noMlbStaff,
      };
    default:
      throw new Error(`Unknown sportId: ${sportId}`);
  }
}

/**
 * Reconcile the `players` subcollection: add new, delete gone, update only
 * players whose visible fields changed. Returns counts so callers can report.
 */
export async function reconcilePlayers(db, sportId, teamId, players) {
  const teamRef = db.collection("sports").doc(sportId).collection("teams").doc(teamId);
  const col = teamRef.collection("players");

  const target = new Map();
  for (const p of players) {
    const id = playerDocId(p);
    if (!id) continue;
    target.set(id, p);
  }

  const snap = await col.get();
  const existing = new Map();
  for (const doc of snap.docs) {
    existing.set(doc.id, doc.data() ?? {});
  }

  const adds = [];
  const updates = [];
  const removes = [];

  for (const [id, p] of target) {
    const cur = existing.get(id);
    if (!cur) {
      adds.push({ id, p });
      continue;
    }
    const changed = PLAYER_FIELDS.some((k) => {
      const curV = cur[k] ?? null;
      const newV =
        k === "jerseyNumber" ? (p.jerseyNumber ?? null) : (p[k] ?? null);
      return (curV ?? null) !== (newV ?? null);
    });
    if (changed) updates.push({ id, p });
  }
  for (const id of existing.keys()) {
    if (!target.has(id)) removes.push(id);
  }

  const totalOps = adds.length + updates.length + removes.length;
  if (totalOps === 0) {
    return { added: 0, updated: 0, removed: 0, scanned: existing.size };
  }

  const ops = [
    ...adds.map(({ id, p }) => ({ kind: "set", id, p })),
    ...updates.map(({ id, p }) => ({ kind: "set", id, p })),
    ...removes.map((id) => ({ kind: "del", id })),
  ];
  const chunk = 400;
  for (let i = 0; i < ops.length; i += chunk) {
    const batch = db.batch();
    for (const op of ops.slice(i, i + chunk)) {
      const ref = col.doc(op.id);
      if (op.kind === "set") {
        batch.set(
          ref,
          {
            fullName: op.p.fullName,
            firstName: op.p.firstName,
            jerseyNumber: op.p.jerseyNumber ?? null,
            displayName: op.p.displayName,
            playerId: op.p.playerId != null ? String(op.p.playerId) : op.id,
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true },
        );
      } else {
        batch.delete(ref);
      }
    }
    await batch.commit();
  }

  return {
    added: adds.length,
    updated: updates.length,
    removed: removes.length,
    scanned: existing.size,
  };
}

/**
 * Reconcile team meta: sets `displayName` + coach fields only when a value
 * changed. Advances `teamUpdatedAt` only on display-name changes, and
 * `coachStaffUpdatedAt` only on coach changes.
 */
export async function reconcileTeamMeta(db, sportId, teamId, meta) {
  const teamRef = db.collection("sports").doc(sportId).collection("teams").doc(teamId);
  const snap = await teamRef.get();
  const cur = snap.exists ? snap.data() ?? {} : {};

  const updates = {};
  const changed = { displayName: false, coach: [] };

  const newLabel =
    meta.teamDisplayName != null ? String(meta.teamDisplayName).trim() : "";
  if (newLabel && cur.displayName !== newLabel) {
    updates.displayName = newLabel;
    updates.teamUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
    changed.displayName = true;
  }

  for (const key of COACH_KEYS) {
    const raw = meta[key];
    const next = raw != null ? String(raw).trim() : "";
    if (!next) continue; // never blank out existing coaches
    if (cur[key] !== next) {
      updates[key] = next;
      changed.coach.push(key);
    }
  }
  if (changed.coach.length > 0) {
    updates.coachStaffUpdatedAt = admin.firestore.FieldValue.serverTimestamp();
  }

  if (Object.keys(updates).length === 0) {
    return { changed: false, coachChanged: [], displayNameChanged: false };
  }

  await teamRef.set(updates, { merge: true });
  return {
    changed: true,
    coachChanged: changed.coach,
    displayNameChanged: changed.displayName,
  };
}

export function initAdmin() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw || !raw.trim()) {
    throw new Error(
      "Set FIREBASE_SERVICE_ACCOUNT_JSON to the full JSON of a Firebase service account.",
    );
  }
  const cred = JSON.parse(raw);
  if (admin.apps.length === 0) {
    admin.initializeApp({ credential: admin.credential.cert(cred) });
  }
  return admin.firestore();
}

/** All MLB teams (sportId 1) from the official stats API — same list the app uses. */
export async function fetchMlbAllTeamJobs() {
  const data = await fetchJson(`https://${MLB_HOST}/api/v1/teams?sportId=1`);
  const teams = data.teams ?? [];
  return teams.map((t) => ({
    sportId: "baseball",
    teamId: String(t.id),
  }));
}

export async function syncJobs(db, items, options = {}) {
  const delayMs = options.delayBetweenJobsMs ?? 0;
  const totals = { added: 0, updated: 0, removed: 0, teams: 0, teamsChanged: 0 };
  for (let i = 0; i < items.length; i++) {
    const job = items[i];
    const sportId = job.sportId;
    const teamId = job.teamId;
    if (!sportId || !teamId) {
      console.warn("Skip invalid job (missing sportId or teamId):", job);
      continue;
    }
    try {
      console.log(`Sync ${sportId} / ${teamId} (${i + 1}/${items.length}) …`);
      const {
        players,
        headCoach,
        pitchingCoach,
        firstBaseCoach,
        thirdBaseCoach,
      } = await fetchRoster(String(sportId), String(teamId));
      const teamDisplayName = await fetchTeamDisplayName(String(sportId), String(teamId));

      const rosterResult = await reconcilePlayers(
        db,
        String(sportId),
        String(teamId),
        players,
      );
      const metaResult = await reconcileTeamMeta(db, String(sportId), String(teamId), {
        teamDisplayName,
        headCoach,
        pitchingCoach,
        firstBaseCoach,
        thirdBaseCoach,
      });

      totals.teams += 1;
      totals.added += rosterResult.added;
      totals.updated += rosterResult.updated;
      totals.removed += rosterResult.removed;
      if (metaResult.changed) totals.teamsChanged += 1;

      const parts = [];
      if (rosterResult.added) parts.push(`+${rosterResult.added}`);
      if (rosterResult.removed) parts.push(`-${rosterResult.removed}`);
      if (rosterResult.updated) parts.push(`~${rosterResult.updated}`);
      const delta = parts.length ? parts.join(" ") : "no changes";
      console.log(
        `  roster: ${delta} (of ${players.length} current, was ${rosterResult.scanned})`,
      );
      if (metaResult.displayNameChanged) {
        console.log(`  team name → ${teamDisplayName}`);
      }
      if (metaResult.coachChanged.length > 0) {
        console.log(`  coach update: ${metaResult.coachChanged.join(", ")}`);
      }
    } catch (e) {
      console.error(`  FAILED ${sportId}/${teamId}:`, e.message ?? e);
    }
    if (delayMs > 0 && i < items.length - 1) {
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
  console.log(
    `Totals: teams=${totals.teams} teamMetaChanged=${totals.teamsChanged} ` +
      `players +${totals.added} -${totals.removed} ~${totals.updated}`,
  );
  return totals;
}
