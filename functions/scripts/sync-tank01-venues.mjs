/**
 * One-shot: fetch league stadiums and write venueName onto
 * sports_tank01/{sport}/teams/{abv} using the logged-in Firebase CLI token.
 *
 * Usage (from functions/): node scripts/sync-tank01-venues.mjs
 */
import fs from "node:fs";
import path from "node:path";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const PROJECT = "projectflo-e99c6";
const ROOT = "sports_tank01";
const SPORTS = ["baseball", "basketball", "hockey", "wnba"];
const UA = "caption-writer-venue-sync/1";

const VENUE_ABV_ALIASES = {
  GSW: ["GS"],
  GS: ["GSW"],
  NYK: ["NY"],
  NY: ["NYK"],
  SAS: ["SA"],
  SA: ["SAS"],
  NOP: ["NO"],
  NO: ["NOP"],
  UTA: ["UTAH"],
  UTAH: ["UTA"],
  PHO: ["PHX"],
  PHX: ["PHO"],
  WAS: ["WSH"],
  WSH: ["WAS"],
  BRO: ["BKN"],
  BKN: ["BRO"],
  LA: ["LAK"],
  LAK: ["LA"],
  SJ: ["SJS"],
  SJS: ["SJ"],
  TB: ["TBL"],
  TBL: ["TB"],
  NJ: ["NJD"],
  NJD: ["NJ"],
};

function putVenue(map, abv, name) {
  const key = String(abv || "").trim().toUpperCase();
  const venue = String(name || "").trim();
  if (!key || !venue) return;
  map.set(key, venue);
  for (const alt of VENUE_ABV_ALIASES[key] ?? []) {
    if (!map.has(alt)) map.set(alt, venue);
  }
}

function lookupVenue(map, teamAbv) {
  const key = String(teamAbv || "").trim().toUpperCase();
  if (!key) return null;
  const direct = map.get(key)?.trim();
  if (direct) return direct;
  for (const alt of VENUE_ABV_ALIASES[key] ?? []) {
    const v = map.get(alt)?.trim();
    if (v) return v;
  }
  return null;
}

async function getJson(url) {
  const res = await fetch(url, { headers: { "User-Agent": UA } });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`HTTP ${res.status} for ${url}: ${body.slice(0, 160)}`);
  }
  return res.json();
}

async function fetchMlbVenues() {
  const data = await getJson(
    "https://statsapi.mlb.com/api/v1/teams?sportId=1",
  );
  const out = new Map();
  for (const t of data.teams ?? []) {
    putVenue(out, t?.abbreviation, t?.venue?.name);
  }
  return out;
}

async function fetchNhlVenues(teamAbvs) {
  const out = new Map();
  const codes = new Set();
  for (const raw of teamAbvs) {
    const abv = String(raw || "").trim().toUpperCase();
    if (!abv) continue;
    codes.add(abv);
    for (const alt of VENUE_ABV_ALIASES[abv] ?? []) codes.add(alt);
  }
  for (const code of codes) {
    try {
      const data = await getJson(
        `https://api-web.nhle.com/v1/club-schedule-season/${code}/now`,
      );
      const counts = new Map();
      for (const g of data.games ?? []) {
        const homeAbv = String(g?.homeTeam?.abbrev ?? "")
          .trim()
          .toUpperCase();
        if (homeAbv !== code) continue;
        const name = String(g?.venue?.default ?? "").trim();
        if (!name) continue;
        counts.set(name, (counts.get(name) ?? 0) + 1);
      }
      let best = null;
      let bestN = 0;
      for (const [name, n] of counts) {
        if (n > bestN) {
          best = name;
          bestN = n;
        }
      }
      if (best) putVenue(out, code, best);
    } catch (e) {
      console.warn(`NHL venue failed for ${code}: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 40));
  }
  return out;
}

async function fetchEspnScheduleVenues(leaguePath) {
  const listing = await getJson(
    `https://site.api.espn.com/apis/site/v2/sports/${leaguePath}/teams?limit=50`,
  );
  const teamsList = listing?.sports?.[0]?.leagues?.[0]?.teams;
  const out = new Map();
  if (!Array.isArray(teamsList)) return out;
  for (const row of teamsList) {
    const team = row?.team;
    const tid = String(team?.id ?? "").trim();
    const abv = String(team?.abbreviation ?? "").trim().toUpperCase();
    if (!tid || !abv) continue;
    try {
      const schedule = await getJson(
        `https://site.api.espn.com/apis/site/v2/sports/${leaguePath}/teams/${tid}/schedule`,
      );
      const counts = new Map();
      for (const event of schedule?.events ?? []) {
        const comp = event?.competitions?.[0];
        if (!comp) continue;
        const name = String(comp?.venue?.fullName ?? "").trim();
        if (!name) continue;
        const competitors = Array.isArray(comp.competitors)
          ? comp.competitors
          : [];
        const isHome = competitors.some(
          (c) => c?.homeAway === "home" && String(c?.team?.id ?? "") === tid,
        );
        if (!isHome) continue;
        counts.set(name, (counts.get(name) ?? 0) + 1);
      }
      let best = null;
      let bestN = 0;
      for (const [name, n] of counts) {
        if (n > bestN) {
          best = name;
          bestN = n;
        }
      }
      if (best) putVenue(out, abv, best);
    } catch (e) {
      console.warn(`ESPN venue failed for ${leaguePath}/${abv}: ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 40));
  }
  return out;
}

function loadAccessToken() {
  const p = path.join(
    process.env.HOME || "",
    ".config/configstore/firebase-tools.json",
  );
  const j = JSON.parse(fs.readFileSync(p, "utf8"));
  const token = j?.tokens?.access_token;
  if (!token) throw new Error("No Firebase CLI access_token found — run firebase login");
  if (j.tokens.expires_at && Date.now() > j.tokens.expires_at - 60_000) {
    throw new Error(
      "Firebase CLI access token expired — run any firebase command to refresh, then retry",
    );
  }
  return token;
}

async function listTeamIds(token, sportId) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${ROOT}/${sportId}/teams?pageSize=300`;
  const res = await fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) {
    throw new Error(`List teams ${sportId}: ${res.status} ${await res.text()}`);
  }
  const data = await res.json();
  const docs = data.documents ?? [];
  return docs.map((d) => {
    const id = d.name.split("/").pop();
    const displayName =
      d.fields?.displayName?.stringValue ?? id;
    const venueName = d.fields?.venueName?.stringValue ?? "";
    return { id, displayName, venueName };
  });
}

async function patchVenue(token, sportId, teamId, venueName) {
  const url =
    `https://firestore.googleapis.com/v1/projects/${PROJECT}/databases/(default)/documents/${ROOT}/${sportId}/teams/${encodeURIComponent(teamId)}` +
    `?updateMask.fieldPaths=venueName&updateMask.fieldPaths=venueUpdatedAt&updateMask.fieldPaths=source`;
  const now = new Date().toISOString();
  const body = {
    fields: {
      venueName: { stringValue: venueName },
      venueUpdatedAt: { timestampValue: now },
      source: { stringValue: "tank01" },
    },
  };
  const res = await fetch(url, {
    method: "PATCH",
    headers: {
      Authorization: `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  if (!res.ok) {
    throw new Error(
      `Patch ${sportId}/${teamId}: ${res.status} ${await res.text()}`,
    );
  }
}

async function main() {
  const token = loadAccessToken();
  const changes = [];
  for (const sportId of SPORTS) {
    console.log(`\n=== ${sportId} ===`);
    const teams = await listTeamIds(token, sportId);
    console.log(`teams in Firestore: ${teams.length}`);
    let venues;
    if (sportId === "baseball") venues = await fetchMlbVenues();
    else if (sportId === "hockey") {
      venues = await fetchNhlVenues(teams.map((t) => t.id));
    } else if (sportId === "basketball") {
      venues = await fetchEspnScheduleVenues("basketball/nba");
    } else {
      venues = await fetchEspnScheduleVenues("basketball/wnba");
    }
    console.log(`venues fetched: ${venues.size}`);
    let updated = 0;
    for (const team of teams) {
      const venue = lookupVenue(venues, team.id);
      if (!venue) continue;
      if (team.venueName === venue) continue;
      await patchVenue(token, sportId, team.id, venue);
      changes.push({
        sportId,
        team: team.displayName,
        abv: team.id,
        from: team.venueName || "(none)",
        to: venue,
      });
      updated += 1;
      process.stdout.write(".");
    }
    console.log(`\nupdated ${updated}`);
  }
  console.log(`\nDone. ${changes.length} stadium writes.`);
  for (const c of changes.slice(0, 40)) {
    console.log(`  ${c.sportId}/${c.abv} ${c.team}: ${c.from} → ${c.to}`);
  }
  if (changes.length > 40) {
    console.log(`  ... +${changes.length - 40} more`);
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
