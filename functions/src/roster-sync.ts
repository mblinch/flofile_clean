/**
 * Roster fetch + Firestore reconcile for nightly Cloud Function.
 *
 * Same reconcile strategy as scripts/roster-sync-core.mjs:
 *   1. Fetch the current roster + coaches + team name from the league API.
 *   2. Read the team's existing players subcollection and team doc.
 *   3. Diff and write only what changed:
 *        - add new players (docId = stable league player id)
 *        - delete players no longer on the roster
 *        - update existing players only if a visible field changed
 *        - team doc: update displayName + coach fields only on change
 */

import { FieldValue, Firestore, WriteBatch } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

const MLB_HOST = "statsapi.mlb.com";
const NHL_HOST = "api-web.nhle.com";
const ESPN = "site.api.espn.com";

const COACH_KEYS = [
  "headCoach",
  "pitchingCoach",
  "firstBaseCoach",
  "thirdBaseCoach",
] as const;
type CoachKey = (typeof COACH_KEYS)[number];

const PLAYER_FIELDS = [
  "fullName",
  "firstName",
  "jerseyNumber",
  "displayName",
] as const;

export interface Player {
  fullName: string;
  firstName: string;
  jerseyNumber: string | null;
  displayName: string;
  playerId: string | null;
}

export interface TeamStaff {
  headCoach: string | null;
  pitchingCoach: string | null;
  firstBaseCoach: string | null;
  thirdBaseCoach: string | null;
}

export interface RosterFetchResult extends TeamStaff {
  players: Player[];
}

export interface TeamMetaInput extends TeamStaff {
  teamDisplayName: string | null;
}

export interface ReconcileResult {
  added: number;
  updated: number;
  removed: number;
  scanned: number;
  addedPlayers: string[];
  updatedPlayers: string[];
  removedPlayers: string[];
}

export interface TeamMetaResult {
  changed: boolean;
  displayNameChanged: boolean;
  coachChanged: CoachKey[];
}

export interface SyncJob {
  sportId: string;
  teamId: string;
}

export interface SyncOptions {
  delayBetweenJobsMs?: number;
}

export interface SyncTotals {
  teams: number;
  teamsChanged: number;
  added: number;
  removed: number;
  updated: number;
  bySport: Record<string, { teams: number; added: number; updated: number; removed: number }>;
  changedPlayers: Array<{
    sportId: string;
    teamId: string;
    teamName: string;
    changeType: "added" | "updated" | "removed";
    playerName: string;
  }>;
}

// ── Generic helpers ──────────────────────────────────────────────────────────

function playerDocId(p: Player): string {
  const pid = p.playerId != null ? String(p.playerId).trim() : "";
  if (pid) return pid;
  const j = (p.jerseyNumber ?? "").toString().trim();
  const slug = (p.fullName ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return j ? `${j}_${slug}` : slug || "unknown";
}

async function fetchJson<T = unknown>(url: string): Promise<T> {
  const res = await fetch(url, {
    headers: { "User-Agent": "caption-writer-roster-sync/1" },
  });
  if (!res.ok) throw new Error(`${url} → ${res.status}`);
  return (await res.json()) as T;
}

// ── League-specific roster fetchers ──────────────────────────────────────────

async function fetchMlbRoster(teamId: string): Promise<Player[]> {
  const url = `https://${MLB_HOST}/api/v1/teams/${teamId}/roster?rosterType=active`;
  const data = await fetchJson<{ roster?: Array<Record<string, any>> }>(url);
  const rosterList = data.roster ?? [];
  return rosterList.map((row) => {
    const person = row.person ?? {};
    const fullName: string = person.fullName ?? "";
    const firstName = fullName.split(" ")[0] ?? fullName;
    const jerseyNumber =
      row.jerseyNumber != null ? String(row.jerseyNumber) : null;
    const displayName = jerseyNumber
      ? `${fullName} #${jerseyNumber}`
      : fullName;
    const playerId = person.id != null ? String(person.id) : null;
    return { fullName, firstName, jerseyNumber, displayName, playerId };
  });
}

async function fetchMlbCoachingStaff(teamId: string): Promise<TeamStaff> {
  const data = await fetchJson<{ roster?: Array<Record<string, any>> }>(
    `https://${MLB_HOST}/api/v1/teams/${teamId}/coaches`,
  );
  const roster = data.roster ?? [];
  const nameForJob = (job: string): string | null => {
    const row = roster.find(
      (c) => String(c.job ?? "").toLowerCase() === job.toLowerCase(),
    );
    const name = row?.person?.fullName?.trim();
    return name || null;
  };
  return {
    headCoach: nameForJob("Manager"),
    pitchingCoach: nameForJob("Pitching Coach"),
    firstBaseCoach: nameForJob("First Base Coach"),
    thirdBaseCoach: nameForJob("Third Base Coach"),
  };
}

function nhlParsePlayer(playerJson: any): Player {
  const firstName: string = playerJson.firstName?.default ?? "";
  const lastName: string = playerJson.lastName?.default ?? "";
  const jerseyNumber =
    playerJson.sweaterNumber != null ? String(playerJson.sweaterNumber) : null;
  const fullName = `${firstName} ${lastName}`.trim();
  const displayName = jerseyNumber ? `${fullName} #${jerseyNumber}` : fullName;
  const playerId = playerJson.id != null ? String(playerJson.id) : null;
  return { fullName, firstName, jerseyNumber, displayName, playerId };
}

async function fetchNhlRoster(triCode: string): Promise<Player[]> {
  const code = triCode.length <= 3 ? triCode : triCode.slice(0, 3);
  const url = `https://${NHL_HOST}/v1/roster/${code}/current`;
  const data = await fetchJson<Record<string, any[]>>(url);
  const lists = ["forwards", "defensemen", "goalies"];
  const all: Player[] = [];
  for (const key of lists) {
    const arr = data[key];
    if (Array.isArray(arr)) {
      for (const p of arr) all.push(nhlParsePlayer(p));
    }
  }
  return all;
}

function extractEspnAthletes(data: any): any[] {
  const raw = data.athletes;
  if (!raw || !Array.isArray(raw)) return [];
  const out: any[] = [];
  for (const el of raw) {
    if (el.items && Array.isArray(el.items)) {
      for (const a of el.items) out.push(a);
    } else {
      out.push(el);
    }
  }
  return out;
}

function parseEspnRosterCoach(coachField: unknown): string | null {
  if (!Array.isArray(coachField) || coachField.length === 0) return null;
  const m = coachField[0];
  if (!m || typeof m !== "object") return null;
  const obj = m as Record<string, unknown>;
  const full = obj.fullName;
  if (typeof full === "string" && full.trim()) return full.trim();
  const first = String(obj.firstName ?? "").trim();
  const last = String(obj.lastName ?? "").trim();
  const combined = `${first} ${last}`.trim();
  return combined || null;
}

async function fetchEspnNhlHeadCoachByTriCode(
  triCode: string,
): Promise<string | null> {
  const code = String(triCode).trim().toUpperCase();
  if (code.length !== 3) return null;
  const teamsData = await fetchJson<any>(
    `https://${ESPN}/apis/site/v2/sports/hockey/nhl/teams?limit=100`,
  );
  const teamsList = teamsData.sports?.[0]?.leagues?.[0]?.teams;
  if (!Array.isArray(teamsList)) return null;
  const row = teamsList.find(
    (t: any) =>
      String(t.team?.abbreviation ?? "").toUpperCase() === code,
  );
  if (!row?.team?.id) return null;
  const id = String(row.team.id);
  const rosterData = await fetchJson<any>(
    `https://${ESPN}/apis/site/v2/sports/hockey/nhl/teams/${id}/roster`,
  );
  return parseEspnRosterCoach(rosterData.coach);
}

function parseEspnAthlete(map: any): Player {
  const fullName: string = map.fullName ?? "";
  const jersey = map.jersey != null ? String(map.jersey) : null;
  const firstName =
    (map.firstName as string | undefined) ?? fullName.split(" ")[0] ?? fullName;
  const displayName = jersey ? `${fullName} #${jersey}` : fullName;
  const playerId = map.id != null ? String(map.id) : null;
  return {
    fullName,
    firstName,
    jerseyNumber: jersey,
    displayName,
    playerId,
  };
}

async function fetchEspnNbaRoster(
  teamId: string,
): Promise<{ players: Player[]; headCoach: string | null }> {
  const path = `/apis/site/v2/sports/basketball/nba/teams/${teamId}/roster`;
  const data = await fetchJson<any>(`https://${ESPN}${path}`);
  const players = extractEspnAthletes(data).map(parseEspnAthlete);
  const headCoach = parseEspnRosterCoach(data.coach);
  return { players, headCoach };
}

async function fetchEspnMlsRoster(teamId: string): Promise<Player[]> {
  const path = `/apis/site/v2/sports/soccer/usa.1/teams/${teamId}/roster`;
  const data = await fetchJson<any>(`https://${ESPN}${path}`);
  return extractEspnAthletes(data).map(parseEspnAthlete);
}

async function fetchEspnTeamDisplayNameById(
  leaguePath: string,
  teamId: string,
): Promise<string | null> {
  const idStr = String(teamId);
  const data = await fetchJson<any>(
    `https://${ESPN}/apis/site/v2/sports/${leaguePath}/teams?limit=100`,
  );
  const teamsList = data.sports?.[0]?.leagues?.[0]?.teams;
  if (!Array.isArray(teamsList)) return null;
  const row = teamsList.find((x: any) => String(x.team?.id) === idStr);
  const t = row?.team;
  const n = String(t?.displayName || t?.name || "").trim();
  return n || null;
}

async function fetchEspnNhlTeamDisplayNameByTri(
  triCode: string,
): Promise<string | null> {
  const code = String(triCode).trim().toUpperCase();
  if (code.length !== 3) return null;
  const data = await fetchJson<any>(
    `https://${ESPN}/apis/site/v2/sports/hockey/nhl/teams?limit=100`,
  );
  const teamsList = data.sports?.[0]?.leagues?.[0]?.teams;
  const row = teamsList?.find(
    (x: any) =>
      String(x.team?.abbreviation ?? "").toUpperCase() === code,
  );
  const t = row?.team;
  const n = String(t?.displayName || t?.name || "").trim();
  return n || null;
}

export async function fetchTeamDisplayName(
  sportId: string,
  teamId: string,
): Promise<string | null> {
  switch (String(sportId)) {
    case "baseball": {
      const data = await fetchJson<any>(
        `https://${MLB_HOST}/api/v1/teams/${teamId}`,
      );
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

export async function fetchRoster(
  sportId: string,
  teamId: string,
): Promise<RosterFetchResult> {
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

// ── Firestore reconcile ─────────────────────────────────────────────────────

export async function reconcilePlayers(
  db: Firestore,
  sportId: string,
  teamId: string,
  players: Player[],
): Promise<ReconcileResult> {
  const teamRef = db
    .collection("sports")
    .doc(sportId)
    .collection("teams")
    .doc(teamId);
  const col = teamRef.collection("players");

  const target = new Map<string, Player>();
  for (const p of players) {
    const id = playerDocId(p);
    if (!id) continue;
    target.set(id, p);
  }

  const snap = await col.get();
  const existing = new Map<string, Record<string, unknown>>();
  for (const doc of snap.docs) {
    existing.set(doc.id, (doc.data() ?? {}) as Record<string, unknown>);
  }

  const adds: Array<{ id: string; p: Player }> = [];
  const updates: Array<{ id: string; p: Player }> = [];
  const removes: string[] = [];

  for (const [id, p] of target) {
    const cur = existing.get(id);
    if (!cur) {
      adds.push({ id, p });
      continue;
    }
    const changed = PLAYER_FIELDS.some((k) => {
      const curV = cur[k] ?? null;
      const newV = p[k] ?? null;
      return curV !== newV;
    });
    if (changed) updates.push({ id, p });
  }
  for (const id of existing.keys()) {
    if (!target.has(id)) removes.push(id);
  }

  const totalOps = adds.length + updates.length + removes.length;
  if (totalOps === 0) {
    return {
      added: 0,
      updated: 0,
      removed: 0,
      scanned: existing.size,
      addedPlayers: [],
      updatedPlayers: [],
      removedPlayers: [],
    };
  }

  type Op =
    | { kind: "set"; id: string; p: Player }
    | { kind: "del"; id: string };
  const ops: Op[] = [
    ...adds.map((x) => ({ kind: "set" as const, id: x.id, p: x.p })),
    ...updates.map((x) => ({ kind: "set" as const, id: x.id, p: x.p })),
    ...removes.map((id) => ({ kind: "del" as const, id })),
  ];

  const chunk = 400;
  for (let i = 0; i < ops.length; i += chunk) {
    const batch: WriteBatch = db.batch();
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
            updatedAt: FieldValue.serverTimestamp(),
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
    addedPlayers: adds.map((x) => x.p.fullName).filter((n) => !!n),
    updatedPlayers: updates.map((x) => x.p.fullName).filter((n) => !!n),
    removedPlayers: removes
      .map((id) => {
        const row = existing.get(id);
        const fullName = row?.fullName;
        return typeof fullName === "string" && fullName.trim() ? fullName.trim() : id;
      })
      .filter((n) => !!n),
  };
}

export async function reconcileTeamMeta(
  db: Firestore,
  sportId: string,
  teamId: string,
  meta: TeamMetaInput,
): Promise<TeamMetaResult> {
  const teamRef = db
    .collection("sports")
    .doc(sportId)
    .collection("teams")
    .doc(teamId);
  const snap = await teamRef.get();
  const cur = (snap.exists ? (snap.data() ?? {}) : {}) as Record<
    string,
    unknown
  >;

  const updates: Record<string, unknown> = {};
  let displayNameChanged = false;
  const coachChanged: CoachKey[] = [];

  const newLabel =
    meta.teamDisplayName != null ? String(meta.teamDisplayName).trim() : "";
  if (newLabel && cur.displayName !== newLabel) {
    updates.displayName = newLabel;
    updates.teamUpdatedAt = FieldValue.serverTimestamp();
    displayNameChanged = true;
  }

  for (const key of COACH_KEYS) {
    const raw = meta[key];
    const next = raw != null ? String(raw).trim() : "";
    if (!next) continue; // never blank out existing coaches
    if (cur[key] !== next) {
      updates[key] = next;
      coachChanged.push(key);
    }
  }
  if (coachChanged.length > 0) {
    updates.coachStaffUpdatedAt = FieldValue.serverTimestamp();
  }

  if (Object.keys(updates).length === 0) {
    return { changed: false, coachChanged: [], displayNameChanged: false };
  }
  await teamRef.set(updates, { merge: true });
  return { changed: true, coachChanged, displayNameChanged };
}

export async function fetchMlbAllTeamJobs(): Promise<SyncJob[]> {
  const data = await fetchJson<any>(
    `https://${MLB_HOST}/api/v1/teams?sportId=1`,
  );
  const teams = data.teams ?? [];
  return teams.map((t: any) => ({
    sportId: "baseball",
    teamId: String(t.id),
  }));
}

async function fetchEspnLeagueTeamJobs(
  leaguePath: string,
  sportId: "basketball" | "soccer",
): Promise<SyncJob[]> {
  const data = await fetchJson<any>(
    `https://${ESPN}/apis/site/v2/sports/${leaguePath}/teams?limit=100`,
  );
  const teamsList = data.sports?.[0]?.leagues?.[0]?.teams;
  if (!Array.isArray(teamsList)) return [];
  return teamsList
    .map((row: any) => String(row?.team?.id ?? "").trim())
    .filter((id: string) => id.length > 0)
    .map((teamId: string) => ({ sportId, teamId }));
}

async function fetchNhlAllTriCodeJobs(): Promise<SyncJob[]> {
  const data = await fetchJson<any>(
    `https://${ESPN}/apis/site/v2/sports/hockey/nhl/teams?limit=100`,
  );
  const teamsList = data.sports?.[0]?.leagues?.[0]?.teams;
  if (!Array.isArray(teamsList)) return [];
  return teamsList
    .map((row: any) => String(row?.team?.abbreviation ?? "").trim().toUpperCase())
    .filter((tri: string) => tri.length === 3)
    .map((teamId: string) => ({ sportId: "hockey", teamId }));
}

export async function fetchAllSportsJobs(): Promise<SyncJob[]> {
  const [mlb, nba, nhl, mls] = await Promise.all([
    fetchMlbAllTeamJobs(),
    fetchEspnLeagueTeamJobs("basketball/nba", "basketball"),
    fetchNhlAllTriCodeJobs(),
    fetchEspnLeagueTeamJobs("soccer/usa.1", "soccer"),
  ]);
  return [...mlb, ...nba, ...nhl, ...mls];
}

export async function syncJobs(
  db: Firestore,
  items: SyncJob[],
  options: SyncOptions = {},
): Promise<SyncTotals> {
  const delayMs = options.delayBetweenJobsMs ?? 0;
  const totals: SyncTotals = {
    teams: 0,
    teamsChanged: 0,
    added: 0,
    removed: 0,
    updated: 0,
    bySport: {},
    changedPlayers: [],
  };
  for (let i = 0; i < items.length; i++) {
    const job = items[i];
    const sportId = job.sportId;
    const teamId = job.teamId;
    if (!sportId || !teamId) {
      logger.warn("Skip invalid job (missing sportId or teamId)", { job });
      continue;
    }
    try {
      logger.info(`Sync ${sportId} / ${teamId} (${i + 1}/${items.length})`);
      const {
        players,
        headCoach,
        pitchingCoach,
        firstBaseCoach,
        thirdBaseCoach,
      } = await fetchRoster(String(sportId), String(teamId));
      const teamDisplayName = await fetchTeamDisplayName(
        String(sportId),
        String(teamId),
      );

      const rosterResult = await reconcilePlayers(
        db,
        String(sportId),
        String(teamId),
        players,
      );
      const metaResult = await reconcileTeamMeta(
        db,
        String(sportId),
        String(teamId),
        {
          teamDisplayName,
          headCoach,
          pitchingCoach,
          firstBaseCoach,
          thirdBaseCoach,
        },
      );

      totals.teams += 1;
      totals.added += rosterResult.added;
      totals.updated += rosterResult.updated;
      totals.removed += rosterResult.removed;
      if (metaResult.changed) totals.teamsChanged += 1;
      const sportBucket = (totals.bySport[sportId] ??= {
        teams: 0,
        added: 0,
        updated: 0,
        removed: 0,
      });
      sportBucket.teams += 1;
      sportBucket.added += rosterResult.added;
      sportBucket.updated += rosterResult.updated;
      sportBucket.removed += rosterResult.removed;

      const label = (teamDisplayName ?? teamId).trim();
      for (const name of rosterResult.addedPlayers) {
        totals.changedPlayers.push({
          sportId,
          teamId,
          teamName: label,
          changeType: "added",
          playerName: name,
        });
      }
      for (const name of rosterResult.updatedPlayers) {
        totals.changedPlayers.push({
          sportId,
          teamId,
          teamName: label,
          changeType: "updated",
          playerName: name,
        });
      }
      for (const name of rosterResult.removedPlayers) {
        totals.changedPlayers.push({
          sportId,
          teamId,
          teamName: label,
          changeType: "removed",
          playerName: name,
        });
      }

      const parts: string[] = [];
      if (rosterResult.added) parts.push(`+${rosterResult.added}`);
      if (rosterResult.removed) parts.push(`-${rosterResult.removed}`);
      if (rosterResult.updated) parts.push(`~${rosterResult.updated}`);
      const delta = parts.length ? parts.join(" ") : "no changes";
      logger.info(
        `roster: ${delta} (of ${players.length} current, was ${rosterResult.scanned})`,
        { sportId, teamId },
      );
      if (metaResult.displayNameChanged) {
        logger.info(`team name → ${teamDisplayName}`, { sportId, teamId });
      }
      if (metaResult.coachChanged.length > 0) {
        logger.info(`coach update: ${metaResult.coachChanged.join(", ")}`, {
          sportId,
          teamId,
        });
      }
    } catch (e: any) {
      logger.error(`FAILED ${sportId}/${teamId}`, {
        message: e?.message ?? String(e),
      });
    }
    if (delayMs > 0 && i < items.length - 1) {
      await new Promise((r) => setTimeout(r, delayMs));
    }
  }
  logger.info("Totals", totals);
  return totals;
}
