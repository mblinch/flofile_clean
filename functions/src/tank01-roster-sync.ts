/**
 * Tank01 RapidAPI → Firestore `sports_tank01/{sport}/teams/{teamAbv}/players/...`
 * used by the scheduled daily (11:00 ET) Cloud Function.
 */

import { FieldValue, Firestore } from "firebase-admin/firestore";
import { logger } from "firebase-functions/v2";

const PLAYER_FIELDS = [
  "fullName",
  "firstName",
  "jerseyNumber",
  "position",
  "displayName",
] as const;

export interface Tank01Player {
  fullName: string;
  firstName: string;
  jerseyNumber: string | null;
  position: string | null;
  displayName: string;
  playerId: string | null;
}

export interface Tank01Team {
  abv: string;
  name: string;
}

export type Tank01SportId = "baseball" | "basketball" | "hockey" | "wnba";

interface LeagueSpec {
  sportId: Tank01SportId;
  host: string;
  teamsPath: string;
  rosterPath: string;
  label: string;
}

const LEAGUES: LeagueSpec[] = [
  {
    sportId: "baseball",
    host: "tank01-mlb-live-in-game-real-time-statistics.p.rapidapi.com",
    teamsPath: "getMLBTeams",
    rosterPath: "getMLBTeamRoster",
    label: "MLB",
  },
  {
    sportId: "basketball",
    host: "tank01-fantasy-stats.p.rapidapi.com",
    teamsPath: "getNBATeams",
    rosterPath: "getNBATeamRoster",
    label: "NBA",
  },
  {
    sportId: "hockey",
    host: "tank01-nhl-live-in-game-real-time-statistics-nhl.p.rapidapi.com",
    teamsPath: "getNHLTeams",
    rosterPath: "getNHLTeamRoster",
    label: "NHL",
  },
  {
    sportId: "wnba",
    host: "tank01-wnba-live-in-game-real-time-statistics-wnba.p.rapidapi.com",
    teamsPath: "getWNBATeams",
    rosterPath: "getWNBATeamRoster",
    label: "WNBA",
  },
];

export const TANK01_ROOT = "sports_tank01";

export interface Tank01MissingJerseyPlayer {
  sportId: string;
  teamId: string;
  teamName: string;
  playerName: string;
  playerId: string | null;
  position: string | null;
}

export interface Tank01DuplicateJerseyPlayer {
  sportId: string;
  teamId: string;
  teamName: string;
  playerName: string;
  jerseyNumber: string;
  alsoWornBy: string;
  playerId: string | null;
  position: string | null;
}

export interface Tank01SportTotals {
  teams: number;
  playersWritten: number;
  added: number;
  updated: number;
  removed: number;
  missingJersey: number;
  duplicateJersey: number;
  errors: string[];
}

export interface Tank01SyncTotals {
  sports: number;
  teams: number;
  playersWritten: number;
  added: number;
  updated: number;
  removed: number;
  missingJersey: number;
  duplicateJersey: number;
  bySport: Record<string, Tank01SportTotals>;
  changedPlayers: Array<{
    sportId: string;
    teamId: string;
    teamName: string;
    changeType: "added" | "updated" | "removed";
    playerName: string;
  }>;
  missingJerseyPlayers: Tank01MissingJerseyPlayer[];
  duplicateJerseyPlayers: Tank01DuplicateJerseyPlayer[];
  errors: string[];
}

function playerDocId(p: Tank01Player): string {
  const pid = p.playerId != null ? String(p.playerId).trim() : "";
  if (pid) return pid;
  const j = (p.jerseyNumber ?? "").toString().trim();
  const slug = (p.fullName ?? "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "_")
    .replace(/^_+|_+$/g, "");
  return j ? `${j}_${slug}` : slug || "unknown";
}

function playerChanged(
  cur: Record<string, unknown>,
  p: Tank01Player,
): boolean {
  for (const key of PLAYER_FIELDS) {
    if (cur[key] !== p[key]) return true;
  }
  return false;
}

/**
 * A manually entered jersey stays in force on this team, even when Tank01
 * sends a different number. A player who moves teams is a new doc on the
 * new team, so this does not follow them — Tank01's number is used there.
 *
 * When Tank01's number differs, `tank01Conflict` is that number so admins
 * can review it. Null means clear any stored conflict on the player doc.
 */
function withPreservedManualJersey(
  cur: Record<string, unknown>,
  incoming: Tank01Player,
): {
  player: Tank01Player;
  keptManual: boolean;
  tank01Conflict: string | null;
} {
  const source = String(cur.jerseySource ?? "").trim();
  const existingJersey = String(cur.jerseyNumber ?? "").trim();
  const incomingJersey = (incoming.jerseyNumber ?? "").toString().trim();
  if (source !== "manual" || !existingJersey) {
    return { player: incoming, keptManual: false, tank01Conflict: null };
  }
  if (!incomingJersey || incomingJersey === existingJersey) {
    return { player: incoming, keptManual: true, tank01Conflict: null };
  }
  return {
    player: {
      ...incoming,
      jerseyNumber: existingJersey,
      displayName: `${incoming.fullName} #${existingJersey}`,
    },
    keptManual: true,
    tank01Conflict: incomingJersey,
  };
}

async function tank01GetJson(
  host: string,
  path: string,
  apiKey: string,
  params: Record<string, string> = {},
): Promise<Record<string, unknown>> {
  const url = new URL(`https://${host}/${path}`);
  for (const [k, v] of Object.entries(params)) {
    url.searchParams.set(k, v);
  }
  const res = await fetch(url, {
    headers: {
      "x-rapidapi-key": apiKey,
      "x-rapidapi-host": host,
      "User-Agent": "caption-writer-tank01-sync/1",
    },
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Tank01 HTTP ${res.status} for ${url}: ${body.slice(0, 200)}`);
  }
  const decoded = (await res.json()) as Record<string, unknown>;
  if (decoded.error) {
    throw new Error(`Tank01 error: ${String(decoded.error)}`);
  }
  return decoded;
}

async function fetchTeams(
  league: LeagueSpec,
  apiKey: string,
): Promise<Tank01Team[]> {
  const payload = await tank01GetJson(league.host, league.teamsPath, apiKey);
  const body = payload.body;
  if (!Array.isArray(body)) {
    throw new Error(`Tank01 ${league.label} teams response missing body list`);
  }
  const out: Tank01Team[] = [];
  for (const raw of body) {
    if (!raw || typeof raw !== "object") continue;
    const row = raw as Record<string, unknown>;
    const abv = String(row.teamAbv ?? row.teamABV ?? "").trim();
    if (!abv) continue;
    const city = String(row.teamCity ?? row.city ?? "").trim();
    const name = String(row.teamName ?? row.name ?? abv).trim();
    const display =
      city && name && !name.toLowerCase().startsWith(city.toLowerCase())
        ? `${city} ${name}`
        : name || abv;
    out.push({ abv, name: display });
  }
  return out;
}

async function fetchRoster(
  league: LeagueSpec,
  apiKey: string,
  teamAbv: string,
): Promise<Tank01Player[]> {
  const payload = await tank01GetJson(league.host, league.rosterPath, apiKey, {
    teamAbv,
  });
  const body = payload.body;
  if (!body || typeof body !== "object") {
    throw new Error(
      `Tank01 ${league.label} roster response missing body for ${teamAbv}`,
    );
  }
  const roster = (body as Record<string, unknown>).roster;
  if (!Array.isArray(roster)) {
    throw new Error(`Tank01 ${league.label} roster empty for ${teamAbv}`);
  }
  const players: Tank01Player[] = [];
  for (const raw of roster) {
    if (!raw || typeof raw !== "object") continue;
    const map = raw as Record<string, unknown>;
    const fullName = String(map.longName ?? "").trim();
    if (!fullName) continue;
    const jerseyRaw = map.jerseyNum != null ? String(map.jerseyNum).trim() : "";
    const jersey = jerseyRaw || null;
    const firstName = fullName.split(/\s+/)[0] ?? fullName;
    const positionRaw = map.pos != null ? String(map.pos).trim() : "";
    const position = positionRaw || null;
    const playerIdRaw =
      map.mlbID ?? map.nbaComID ?? map.nhlComID ?? map.playerID;
    const playerId =
      playerIdRaw != null && String(playerIdRaw).trim()
        ? String(playerIdRaw).trim()
        : null;
    players.push({
      fullName,
      firstName,
      jerseyNumber: jersey,
      position,
      displayName: jersey ? `${fullName} #${jersey}` : fullName,
      playerId,
    });
  }
  return players;
}

async function reconcileTeamPlayers(
  db: Firestore,
  sportId: string,
  teamAbv: string,
  teamDisplayName: string,
  players: Tank01Player[],
): Promise<{
  added: number;
  updated: number;
  removed: number;
  changedPlayers: Tank01SyncTotals["changedPlayers"];
  missingJerseyPlayers: Tank01MissingJerseyPlayer[];
  duplicateJerseyPlayers: Tank01DuplicateJerseyPlayer[];
}> {
  const teamRef = db
    .collection(TANK01_ROOT)
    .doc(sportId)
    .collection("teams")
    .doc(teamAbv);
  const playersCol = teamRef.collection("players");

  const target = new Map<string, Tank01Player>();
  for (const p of players) {
    const id = playerDocId(p);
    if (id) target.set(id, p);
  }

  const existingSnap = await playersCol.get();
  const existing = new Map<string, Record<string, unknown>>();
  for (const doc of existingSnap.docs) {
    existing.set(doc.id, doc.data());
  }

  const adds: Array<[string, Tank01Player]> = [];
  const updates: Array<[string, Tank01Player]> = [];
  const removes: string[] = [];
  const changedPlayers: Tank01SyncTotals["changedPlayers"] = [];
  const preservedManual = new Set<string>();
  /** Doc id → Tank01 number that differs from the manual override. */
  const tank01Conflicts = new Map<string, string>();
  /** Doc ids whose stored Tank01 conflict field should be cleared. */
  const clearTank01Conflicts = new Set<string>();
  const effectiveById = new Map<string, Tank01Player>();

  for (const [id, p] of target) {
    const cur = existing.get(id);
    if (!cur) {
      adds.push([id, p]);
      effectiveById.set(id, p);
      changedPlayers.push({
        sportId,
        teamId: teamAbv,
        teamName: teamDisplayName,
        changeType: "added",
        playerName: p.fullName,
      });
      continue;
    }
    const { player: effective, keptManual, tank01Conflict } =
      withPreservedManualJersey(cur, p);
    if (keptManual) preservedManual.add(id);
    const curConflict = String(cur.tank01JerseyNumber ?? "").trim();
    let conflictFieldChanged = false;
    if (tank01Conflict) {
      tank01Conflicts.set(id, tank01Conflict);
      conflictFieldChanged = curConflict !== tank01Conflict;
    } else if (curConflict) {
      clearTank01Conflicts.add(id);
      conflictFieldChanged = true;
    }
    effectiveById.set(id, effective);
    if (playerChanged(cur, effective) || conflictFieldChanged) {
      updates.push([id, effective]);
      changedPlayers.push({
        sportId,
        teamId: teamAbv,
        teamName: teamDisplayName,
        changeType: "updated",
        playerName: effective.fullName,
      });
    }
  }
  for (const id of existing.keys()) {
    if (!target.has(id)) {
      removes.push(id);
      const name = String(existing.get(id)?.fullName ?? id);
      changedPlayers.push({
        sportId,
        teamId: teamAbv,
        teamName: teamDisplayName,
        changeType: "removed",
        playerName: name,
      });
    }
  }

  const missingJerseyPlayers: Tank01MissingJerseyPlayer[] = [];
  const byJersey = new Map<string, Tank01Player[]>();
  for (const p of effectiveById.values()) {
    const jersey = (p.jerseyNumber ?? "").toString().trim();
    if (!jersey) {
      missingJerseyPlayers.push({
        sportId,
        teamId: teamAbv,
        teamName: teamDisplayName,
        playerName: p.fullName,
        playerId: p.playerId,
        position: p.position,
      });
      continue;
    }
    const list = byJersey.get(jersey) ?? [];
    list.push(p);
    byJersey.set(jersey, list);
  }
  const duplicateJerseyPlayers: Tank01DuplicateJerseyPlayer[] = [];
  for (const [jersey, players] of byJersey) {
    if (players.length < 2) continue;
    for (const p of players) {
      const others = players
        .filter((x) => x !== p)
        .map((x) => x.fullName)
        .join(", ");
      duplicateJerseyPlayers.push({
        sportId,
        teamId: teamAbv,
        teamName: teamDisplayName,
        playerName: p.fullName,
        jerseyNumber: jersey,
        alsoWornBy: others,
        playerId: p.playerId,
        position: p.position,
      });
    }
  }

  const teamDoc = await teamRef.get();
  const curData = teamDoc.data() ?? {};
  const teamDocPatch: Record<string, unknown> = {};
  if (teamDisplayName && curData.displayName !== teamDisplayName) {
    teamDocPatch.displayName = teamDisplayName;
    teamDocPatch.teamUpdatedAt = FieldValue.serverTimestamp();
  }
  if (curData.source !== "tank01") {
    teamDocPatch.source = "tank01";
  }

  if (
    adds.length === 0 &&
    updates.length === 0 &&
    removes.length === 0 &&
    Object.keys(teamDocPatch).length === 0
  ) {
    return {
      added: 0,
      updated: 0,
      removed: 0,
      changedPlayers: [],
      missingJerseyPlayers,
      duplicateJerseyPlayers,
    };
  }

  const chunkSize = 400;
  const ops: Array<
    | { type: "set"; id: string; player: Tank01Player }
    | { type: "delete"; id: string }
  > = [
    ...adds.map(([id, player]) => ({ type: "set" as const, id, player })),
    ...updates.map(([id, player]) => ({ type: "set" as const, id, player })),
    ...removes.map((id) => ({ type: "delete" as const, id })),
  ];

  if (ops.length === 0) {
    await teamRef.set(teamDocPatch, { merge: true });
    return {
      added: 0,
      updated: 0,
      removed: 0,
      changedPlayers: [],
      missingJerseyPlayers,
      duplicateJerseyPlayers,
    };
  }

  for (let i = 0; i < ops.length; i += chunkSize) {
    const batch = db.batch();
    if (i === 0 && Object.keys(teamDocPatch).length > 0) {
      batch.set(teamRef, teamDocPatch, { merge: true });
    }
    for (const op of ops.slice(i, i + chunkSize)) {
      const ref = playersCol.doc(op.id);
      if (op.type === "set") {
        const p = op.player;
        const keepManual = preservedManual.has(op.id);
        const conflict = tank01Conflicts.get(op.id);
        const clearConflict = clearTank01Conflicts.has(op.id) || !keepManual;
        const incomingHasJersey =
          !!(p.jerseyNumber ?? "").toString().trim() && !keepManual;
        batch.set(
          ref,
          {
            fullName: p.fullName,
            firstName: p.firstName,
            jerseyNumber: p.jerseyNumber,
            displayName: p.displayName,
            ...(p.playerId ? { playerId: p.playerId } : {}),
            ...(p.position ? { position: p.position } : {}),
            ...(keepManual ? { jerseySource: "manual" } : {}),
            ...(incomingHasJersey ? { jerseySource: "tank01" } : {}),
            ...(conflict
              ? { tank01JerseyNumber: conflict }
              : clearConflict
                ? { tank01JerseyNumber: FieldValue.delete() }
                : {}),
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
    changedPlayers,
    missingJerseyPlayers,
    duplicateJerseyPlayers,
  };
}

export async function syncAllTank01Rosters(
  db: Firestore,
  apiKey: string,
  options?: { delayBetweenTeamsMs?: number },
): Promise<Tank01SyncTotals> {
  const delayMs = options?.delayBetweenTeamsMs ?? 150;
  const totals: Tank01SyncTotals = {
    sports: 0,
    teams: 0,
    playersWritten: 0,
    added: 0,
    updated: 0,
    removed: 0,
    missingJersey: 0,
    duplicateJersey: 0,
    bySport: {},
    changedPlayers: [],
    missingJerseyPlayers: [],
    duplicateJerseyPlayers: [],
    errors: [],
  };

  for (const league of LEAGUES) {
    const sportTotals: Tank01SportTotals = {
      teams: 0,
      playersWritten: 0,
      added: 0,
      updated: 0,
      removed: 0,
      missingJersey: 0,
      duplicateJersey: 0,
      errors: [],
    };
    logger.info(`Tank01 sync: fetching ${league.label} teams`);
    let teams: Tank01Team[] = [];
    try {
      teams = await fetchTeams(league, apiKey);
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      sportTotals.errors.push(`Teams fetch failed: ${msg}`);
      totals.errors.push(`${league.sportId}: ${msg}`);
      totals.bySport[league.sportId] = sportTotals;
      continue;
    }

    for (const team of teams) {
      try {
        const players = await fetchRoster(league, apiKey, team.abv);
        const result = await reconcileTeamPlayers(
          db,
          league.sportId,
          team.abv,
          team.name,
          players,
        );
        sportTotals.teams += 1;
        sportTotals.playersWritten += players.length;
        sportTotals.added += result.added;
        sportTotals.updated += result.updated;
        sportTotals.removed += result.removed;
        sportTotals.missingJersey += result.missingJerseyPlayers.length;
        sportTotals.duplicateJersey += result.duplicateJerseyPlayers.length;
        totals.changedPlayers.push(...result.changedPlayers);
        totals.missingJerseyPlayers.push(...result.missingJerseyPlayers);
        totals.duplicateJerseyPlayers.push(...result.duplicateJerseyPlayers);
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        sportTotals.errors.push(`${team.name} (${team.abv}): ${msg}`);
        totals.errors.push(`${league.sportId}/${team.abv}: ${msg}`);
      }
      if (delayMs > 0) {
        await new Promise((r) => setTimeout(r, delayMs));
      }
    }

    totals.sports += 1;
    totals.teams += sportTotals.teams;
    totals.playersWritten += sportTotals.playersWritten;
    totals.added += sportTotals.added;
    totals.updated += sportTotals.updated;
    totals.removed += sportTotals.removed;
    totals.missingJersey += sportTotals.missingJersey;
    totals.duplicateJersey += sportTotals.duplicateJersey;
    totals.bySport[league.sportId] = sportTotals;
    logger.info(`Tank01 sync: ${league.label} done`, sportTotals);
  }

  return totals;
}
