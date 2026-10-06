/**
 * Nightly roster sync (Firebase Cloud Functions v2).
 *
 * - `nightlyRosterSync`: scheduled daily at 06:00 America/New_York (DST-safe).
 * - `runRosterSyncNow`: callable trigger for manual runs from `firebase functions:shell`
 *    or the Firebase console. Requires an authenticated caller (admin-only by default).
 * - `tank01RosterSync`: Tank01 → sports_tank01, daily at 11:00 ET; emails
 *    `dev@flofilecaptions.com` (same Resend setup as nightly roster sync).
 * - `runTank01RosterSyncNow`: admin callable for a manual Tank01 mirror run.
 * - `onRosterIssueReportCreated`: emails admins when a user files a
 *    `roster_issue_reports/{id}` doc (duplicate jersey or player data issue).
 *
 * Firestore config (doc `roster_sync/config`):
 *   enabled?: boolean    default true
 *   syncAllMlb?: boolean if true, runs every MLB team from statsapi.mlb.com
 *   items?: Array<{ sportId, teamId }>  used when syncAllMlb is not true
 *   emailSummaryEnabled / emailSummaryTo / emailSummaryFrom / resendApiKey
 *
 * Firestore config (doc `tank01_sync/config`):
 *   enabled?: boolean           default true
 *   rapidApiKey?: string        Tank01 RapidAPI key (required unless env set)
 *   emailSummaryEnabled?: bool  default true
 *   emailSummaryTo?: string     default `dev@flofilecaptions.com`
 *   emailSummaryFrom?: string   falls back to roster_sync/config
 *   resendApiKey?: string       falls back to roster_sync/config
 */

import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import { logger } from "firebase-functions/v2";

import {
  SyncJob,
  SyncTotals,
  fetchAllSportsJobs,
  fetchMlbAllTeamJobs,
  syncJobs,
} from "./roster-sync";
import {
  syncAllTank01Rosters,
  Tank01SyncTotals,
} from "./tank01-roster-sync";

initializeApp();

interface RosterSyncConfig {
  enabled?: boolean;
  syncAllSports?: boolean;
  syncAllMlb?: boolean;
  items?: SyncJob[];
  emailSummaryEnabled?: boolean;
  emailSummaryTo?: string;
  emailSummaryFrom?: string;
  resendApiKey?: string;
}

interface Tank01SyncConfig {
  enabled?: boolean;
  rapidApiKey?: string;
  emailSummaryEnabled?: boolean;
  emailSummaryTo?: string;
  emailSummaryFrom?: string;
  resendApiKey?: string;
}

type SyncTrigger = "scheduled" | "manual";
const MAX_CHANGED_PLAYERS_IN_EMAIL = 120;
const MAX_MISSING_JERSEY_IN_EMAIL = 80;
const MAX_DUPLICATE_JERSEY_IN_EMAIL = 80;
const TANK01_EMAIL_DEFAULT_TO = "dev@flofilecaptions.com";

function formatDurationHuman(ms: number): string {
  const totalSeconds = Math.max(0, Math.round(ms / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`;
  if (minutes > 0) return `${minutes}m ${seconds}s`;
  return `${seconds}s`;
}

function formatSportName(sportId: string): string {
  const s = sportId.trim().toLowerCase();
  if (!s) return sportId;
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function formatTimestampForEmail(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  return new Intl.DateTimeFormat("en-US", {
    timeZone: "America/New_York",
    month: "short",
    day: "2-digit",
    year: "numeric",
    hour: "numeric",
    minute: "2-digit",
    second: "2-digit",
    hour12: true,
    timeZoneName: "short",
  }).format(d);
}

interface SyncRunSummary {
  ok: boolean;
  reason: string;
  trigger: SyncTrigger;
  jobCount: number;
  totals: SyncTotals | null;
  startedAtIso: string;
  finishedAtIso: string;
  durationMs: number;
}

interface Tank01RunSummary {
  ok: boolean;
  reason: string;
  trigger: SyncTrigger;
  totals: Tank01SyncTotals | null;
  startedAtIso: string;
  finishedAtIso: string;
  durationMs: number;
}

async function writeRunSummary(summary: SyncRunSummary): Promise<void> {
  const db = getFirestore();
  const runId = summary.startedAtIso.replace(/[:.]/g, "-");
  const payload = {
    ...summary,
    updatedAt: FieldValue.serverTimestamp(),
  };

  await Promise.all([
    db.doc("roster_sync/status").set(payload, { merge: true }),
    db.collection("roster_sync_runs").doc(runId).set({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
    }),
  ]);
}

async function writeTank01RunSummary(summary: Tank01RunSummary): Promise<void> {
  const db = getFirestore();
  const runId = summary.startedAtIso.replace(/[:.]/g, "-");
  const payload = {
    ...summary,
    updatedAt: FieldValue.serverTimestamp(),
  };

  await Promise.all([
    db.doc("tank01_sync/status").set(payload, { merge: true }),
    db.collection("tank01_sync_runs").doc(runId).set({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
    }),
  ]);
}

/** Resend account owner — only allowed recipient while using onboarding@resend.dev. */
const RESEND_ONBOARDING_FALLBACK_TO = "dev@flofilecaptions.com";

async function sendResendEmail(args: {
  apiKey: string;
  from: string;
  to: string;
  subject: string;
  text: string;
}): Promise<void> {
  const sendOnce = async (to: string, subject: string, text: string) => {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${args.apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: args.from,
        to: [to],
        subject,
        text,
      }),
    });
    if (!res.ok) {
      const errorText = await res.text();
      throw new Error(`Resend email failed (${res.status}): ${errorText}`);
    }
  };

  try {
    await sendOnce(args.to, args.subject, args.text);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    const canFallback =
      /only send testing emails to your own email address/i.test(msg) &&
      args.to.trim().toLowerCase() !== RESEND_ONBOARDING_FALLBACK_TO;
    if (!canFallback) throw e;

    logger.warn(
      `Resend blocked ${args.to} (unverified domain). Falling back to ${RESEND_ONBOARDING_FALLBACK_TO}. Verify flofilecaptions.com at resend.com/domains and set emailSummaryFrom to that domain.`,
    );
    await sendOnce(
      RESEND_ONBOARDING_FALLBACK_TO,
      args.subject,
      [
        `NOTE: Intended recipient was ${args.to}, but Resend only allows ${RESEND_ONBOARDING_FALLBACK_TO} until flofilecaptions.com is verified.`,
        "",
        args.text,
      ].join("\n"),
    );
  }
}

async function sendRunSummaryEmail(
  summary: SyncRunSummary,
  cfg: RosterSyncConfig,
): Promise<void> {
  if (cfg.emailSummaryEnabled !== true) return;
  const to = (cfg.emailSummaryTo ?? "").trim();
  if (!to) {
    logger.warn("emailSummaryEnabled=true but emailSummaryTo is missing.");
    return;
  }
  const apiKey = (cfg.resendApiKey ?? "").trim();
  if (!apiKey) {
    logger.warn("resendApiKey missing on roster_sync/config; skipping summary email.");
    return;
  }
  const from = (cfg.emailSummaryFrom ?? "Roster Sync <onboarding@resend.dev>").trim();
  const totals = summary.totals;
  const subject = summary.ok
    ? `[Roster Sync] ${summary.trigger} run complete`
    : `[Roster Sync] ${summary.trigger} run: ${summary.reason}`;
  const durationPretty = formatDurationHuman(summary.durationMs);
  const perSportLines = totals
    ? Object.entries(totals.bySport)
        .sort(([a], [b]) => a.localeCompare(b))
        .flatMap(([sport, s]) => [
          `  - ${formatSportName(sport)}:`,
          `      Teams scanned: ${s.teams}`,
          `      Players added: ${s.added}`,
          `      Players updated: ${s.updated}`,
          `      Players removed: ${s.removed}`,
        ])
    : [];
  const changed = totals?.changedPlayers ?? [];
  const shownChanged = changed.slice(0, MAX_CHANGED_PLAYERS_IN_EMAIL);
  const changedBySport = new Map<string, typeof shownChanged>();
  for (const c of shownChanged) {
    const list = changedBySport.get(c.sportId) ?? [];
    list.push(c);
    changedBySport.set(c.sportId, list);
  }
  const changedLines =
    shownChanged.length === 0
      ? ["  - none"]
      : Array.from(changedBySport.entries())
          .sort(([a], [b]) => a.localeCompare(b))
          .flatMap(([sport, rows]) => [
            `  - ${formatSportName(sport)}:`,
            ...rows.map(
              (c) =>
                `      ${c.teamName}: ${c.changeType.toUpperCase()} ${c.playerName}`,
            ),
          ]);
  const resultLine =
    summary.ok && summary.reason === "success"
      ? "Result: success"
      : `Result: ${summary.ok ? "success" : "noop/error"} (${summary.reason})`;
  const bodyLines = [
    resultLine,
    `Trigger: ${summary.trigger}`,
    `Started: ${formatTimestampForEmail(summary.startedAtIso)}`,
    `Finished: ${formatTimestampForEmail(summary.finishedAtIso)}`,
    `Duration: ${durationPretty}`,
    `Jobs: ${summary.jobCount}`,
    "Overall totals:",
    ...(totals
      ? [
          `  - Teams scanned: ${totals.teams}`,
          `  - Team records changed: ${totals.teamsChanged}`,
          `  - Players added: ${totals.added}`,
          `  - Players updated: ${totals.updated}`,
          `  - Players removed: ${totals.removed}`,
        ]
      : ["  - n/a"]),
    "",
    "By sport (subset of overall totals):",
    ...(perSportLines.length > 0 ? perSportLines : ["  - n/a"]),
    "",
    `Changed players (${changed.length}):`,
    ...changedLines,
    ...(changed.length > MAX_CHANGED_PLAYERS_IN_EMAIL
      ? [
          `  - ... truncated ${changed.length - MAX_CHANGED_PLAYERS_IN_EMAIL} additional player changes`,
        ]
      : []),
  ];

  await sendResendEmail({
    apiKey,
    from,
    to,
    subject,
    text: bodyLines.join("\n"),
  });
}

async function sendTank01SummaryEmail(
  summary: Tank01RunSummary,
  cfg: Tank01SyncConfig,
  rosterCfg: RosterSyncConfig,
): Promise<void> {
  const emailEnabled = cfg.emailSummaryEnabled !== false;
  if (!emailEnabled) return;

  const to = (cfg.emailSummaryTo ?? TANK01_EMAIL_DEFAULT_TO).trim();
  const apiKey = (cfg.resendApiKey ?? rosterCfg.resendApiKey ?? "").trim();
  if (!apiKey) {
    logger.warn(
      "resendApiKey missing on tank01_sync/config and roster_sync/config; skipping Tank01 email.",
    );
    return;
  }
  const from = (
    cfg.emailSummaryFrom ??
    rosterCfg.emailSummaryFrom ??
    "Tank01 Sync <onboarding@resend.dev>"
  ).trim();

  const totals = summary.totals;
  const missingCount = totals?.missingJersey ?? 0;
  const duplicateCount = totals?.duplicateJersey ?? 0;
  const issueCount = missingCount + duplicateCount;
  const subject = !summary.ok
    ? `[Tank01 Sync] ${summary.trigger} run: ${summary.reason}`
    : issueCount > 0
      ? `[Tank01 Sync] ${issueCount} jersey issue(s) — verify in app`
      : `[Tank01 Sync] ${summary.trigger} run complete`;
  const durationPretty = formatDurationHuman(summary.durationMs);
  const perSportLines = totals
    ? Object.entries(totals.bySport)
        .sort(([a], [b]) => a.localeCompare(b))
        .flatMap(([sport, s]) => [
          `  - ${formatSportName(sport)}:`,
          `      Teams scanned: ${s.teams}`,
          `      Players written: ${s.playersWritten}`,
          `      Players added: ${s.added}`,
          `      Players updated: ${s.updated}`,
          `      Players removed: ${s.removed}`,
          `      Missing jersey: ${s.missingJersey ?? 0}`,
          `      Duplicate jersey: ${s.duplicateJersey ?? 0}`,
          ...(s.errors.length ? [`      Errors: ${s.errors.length}`] : []),
        ])
    : [];
  const changed = totals?.changedPlayers ?? [];
  const shownChanged = changed.slice(0, MAX_CHANGED_PLAYERS_IN_EMAIL);
  const changedBySport = new Map<string, typeof shownChanged>();
  for (const c of shownChanged) {
    const list = changedBySport.get(c.sportId) ?? [];
    list.push(c);
    changedBySport.set(c.sportId, list);
  }
  const changedLines =
    shownChanged.length === 0
      ? ["  - none"]
      : Array.from(changedBySport.entries())
          .sort(([a], [b]) => a.localeCompare(b))
          .flatMap(([sport, rows]) => [
            `  - ${formatSportName(sport)}:`,
            ...rows.map(
              (c) =>
                `      ${c.teamName}: ${c.changeType.toUpperCase()} ${c.playerName}`,
            ),
          ]);
  const missing = totals?.missingJerseyPlayers ?? [];
  const shownMissing = missing.slice(0, MAX_MISSING_JERSEY_IN_EMAIL);
  const missingBySport = new Map<string, typeof shownMissing>();
  for (const m of shownMissing) {
    const list = missingBySport.get(m.sportId) ?? [];
    list.push(m);
    missingBySport.set(m.sportId, list);
  }
  const missingLines =
    shownMissing.length === 0
      ? ["  - none"]
      : Array.from(missingBySport.entries())
          .sort(([a], [b]) => a.localeCompare(b))
          .flatMap(([sport, rows]) => [
            `  - ${formatSportName(sport)}:`,
            ...rows.map((m) => {
              const pos = (m.position ?? "").trim();
              return `      ${m.teamName}: ${m.playerName}${
                pos ? ` (${pos})` : ""
              }`;
            }),
          ]);
  const duplicates = totals?.duplicateJerseyPlayers ?? [];
  const shownDuplicates = duplicates.slice(0, MAX_DUPLICATE_JERSEY_IN_EMAIL);
  const duplicateBySport = new Map<string, typeof shownDuplicates>();
  for (const d of shownDuplicates) {
    const list = duplicateBySport.get(d.sportId) ?? [];
    list.push(d);
    duplicateBySport.set(d.sportId, list);
  }
  const duplicateLines =
    shownDuplicates.length === 0
      ? ["  - none"]
      : Array.from(duplicateBySport.entries())
          .sort(([a], [b]) => a.localeCompare(b))
          .flatMap(([sport, rows]) => [
            `  - ${formatSportName(sport)}:`,
            ...rows.map((d) => {
              const pos = (d.position ?? "").trim();
              const also = (d.alsoWornBy ?? "").trim();
              return `      ${d.teamName}: #${d.jerseyNumber} ${d.playerName}${
                pos ? ` (${pos})` : ""
              }${also ? ` — also ${also}` : ""}`;
            }),
          ]);
  const errorLines =
    totals?.errors?.length
      ? totals.errors.slice(0, 40).map((e) => `  - ${e}`)
      : ["  - none"];
  const resultLine =
    summary.ok && summary.reason === "success"
      ? "Result: success"
      : `Result: ${summary.ok ? "success" : "noop/error"} (${summary.reason})`;
  const bodyLines = [
    resultLine,
    `Trigger: ${summary.trigger}`,
    `Started: ${formatTimestampForEmail(summary.startedAtIso)}`,
    `Finished: ${formatTimestampForEmail(summary.finishedAtIso)}`,
    `Duration: ${durationPretty}`,
    "Overall totals:",
    ...(totals
      ? [
          `  - Sports: ${totals.sports}`,
          `  - Teams scanned: ${totals.teams}`,
          `  - Players written: ${totals.playersWritten}`,
          `  - Players added: ${totals.added}`,
          `  - Players updated: ${totals.updated}`,
          `  - Players removed: ${totals.removed}`,
          `  - Missing jersey: ${missingCount}`,
          `  - Duplicate jersey: ${duplicateCount}`,
        ]
      : ["  - n/a"]),
    "",
    "By sport:",
    ...(perSportLines.length > 0 ? perSportLines : ["  - n/a"]),
    "",
    `Players missing jersey (${missing.length}):`,
    "  Verify / enter numbers in Admin → Roster Issues.",
    ...missingLines,
    ...(missing.length > MAX_MISSING_JERSEY_IN_EMAIL
      ? [
          `  - ... truncated ${
            missing.length - MAX_MISSING_JERSEY_IN_EMAIL
          } additional players`,
        ]
      : []),
    "",
    `Players with duplicate jersey (${duplicates.length}):`,
    "  Verify / change numbers in Admin → Roster Issues.",
    ...duplicateLines,
    ...(duplicates.length > MAX_DUPLICATE_JERSEY_IN_EMAIL
      ? [
          `  - ... truncated ${
            duplicates.length - MAX_DUPLICATE_JERSEY_IN_EMAIL
          } additional players`,
        ]
      : []),
    "",
    `Changed players (${changed.length}):`,
    ...changedLines,
    ...(changed.length > MAX_CHANGED_PLAYERS_IN_EMAIL
      ? [
          `  - ... truncated ${changed.length - MAX_CHANGED_PLAYERS_IN_EMAIL} additional player changes`,
        ]
      : []),
    "",
    `Errors (${totals?.errors?.length ?? 0}):`,
    ...errorLines,
  ];

  await sendResendEmail({
    apiKey,
    from,
    to,
    subject,
    text: bodyLines.join("\n"),
  });
}

/** Shared core used by both the scheduled function and the manual trigger. */
async function runSync(trigger: SyncTrigger): Promise<{
  ok: boolean;
  reason?: string;
  totals?: SyncTotals;
  jobCount?: number;
}> {
  const started = Date.now();
  const startedAtIso = new Date(started).toISOString();
  const db = getFirestore();
  let cfg: RosterSyncConfig = { enabled: true, syncAllSports: true };

  let result: {
    ok: boolean;
    reason?: string;
    totals?: SyncTotals;
    jobCount?: number;
  } = { ok: false, reason: "unknown" };

  try {
    const snap = await db.doc("roster_sync/config").get();
    const data = (snap.exists ? snap.data() : null) as RosterSyncConfig | null;
    if (!data) {
      logger.warn(
        "roster_sync/config missing — falling back to syncAllSports=true (all 4 leagues).",
      );
    }
    cfg = data ?? { enabled: true, syncAllSports: true };
    if (cfg.enabled === false) {
      logger.info("roster_sync/config.enabled is false — skipping.");
      result = { ok: false, reason: "disabled" };
      return result;
    }

    let items: SyncJob[] = Array.isArray(cfg.items) ? cfg.items : [];
    if (cfg.syncAllSports === true) {
      logger.info("syncAllSports: loading all team IDs for MLB, NBA, NHL, MLS");
      items = await fetchAllSportsJobs();
      logger.info(`${items.length} total teams loaded across 4 sports`);
    } else if (cfg.syncAllMlb === true) {
      logger.info("syncAllMlb: loading all MLB team IDs from statsapi.mlb.com");
      items = await fetchMlbAllTeamJobs();
      logger.info(`${items.length} MLB teams loaded`);
    }

    if (items.length === 0) {
      logger.warn(
        "Nothing to sync. Set syncAllSports: true, or syncAllMlb: true, or items: [{ sportId, teamId }, …] on roster_sync/config.",
      );
      result = { ok: false, reason: "no-items" };
      return result;
    }

    const delayMs =
      cfg.syncAllSports === true || cfg.syncAllMlb === true ? 400 : 0;
    const totals = await syncJobs(db, items, { delayBetweenJobsMs: delayMs });
    result = { ok: true, totals, jobCount: items.length };
    return result;
  } finally {
    const finished = Date.now();
    const summary: SyncRunSummary = {
      ok: result.ok,
      reason: result.reason ?? "success",
      trigger,
      jobCount: result.jobCount ?? 0,
      totals: result.totals ?? null,
      startedAtIso,
      finishedAtIso: new Date(finished).toISOString(),
      durationMs: finished - started,
    };
    await writeRunSummary(summary);
    try {
      await sendRunSummaryEmail(summary, cfg);
    } catch (e) {
      logger.error("Failed to send roster summary email", {
        message: e instanceof Error ? e.message : String(e),
      });
    }
  }
}

async function loadTank01Config(): Promise<{
  tank01: Tank01SyncConfig;
  roster: RosterSyncConfig;
}> {
  const db = getFirestore();
  const [tank01Snap, rosterSnap] = await Promise.all([
    db.doc("tank01_sync/config").get(),
    db.doc("roster_sync/config").get(),
  ]);
  const tank01 = (tank01Snap.exists ? tank01Snap.data() : null) as
    | Tank01SyncConfig
    | null;
  const roster = (rosterSnap.exists ? rosterSnap.data() : null) as
    | RosterSyncConfig
    | null;
  return {
    tank01: tank01 ?? {},
    roster: roster ?? {},
  };
}

async function runTank01Sync(trigger: SyncTrigger): Promise<{
  ok: boolean;
  reason?: string;
  totals?: Tank01SyncTotals;
}> {
  const started = Date.now();
  const startedAtIso = new Date(started).toISOString();
  const db = getFirestore();
  let tank01Cfg: Tank01SyncConfig = {};
  let rosterCfg: RosterSyncConfig = {};

  let result: {
    ok: boolean;
    reason?: string;
    totals?: Tank01SyncTotals;
  } = { ok: false, reason: "unknown" };

  try {
    const loaded = await loadTank01Config();
    tank01Cfg = loaded.tank01;
    rosterCfg = loaded.roster;

    if (tank01Cfg.enabled === false) {
      logger.info("tank01_sync/config.enabled is false — skipping.");
      result = { ok: false, reason: "disabled" };
      return result;
    }

    const apiKey = (
      tank01Cfg.rapidApiKey ??
      process.env.TANK01_RAPIDAPI_KEY ??
      ""
    ).trim();
    if (!apiKey) {
      logger.error(
        "Tank01 RapidAPI key missing. Set tank01_sync/config.rapidApiKey or TANK01_RAPIDAPI_KEY.",
      );
      result = { ok: false, reason: "missing-api-key" };
      return result;
    }

    const totals = await syncAllTank01Rosters(db, apiKey, {
      delayBetweenTeamsMs: 150,
    });
    const hardFail = totals.teams === 0 && (totals.errors?.length ?? 0) > 0;
    result = {
      ok: !hardFail,
      reason: hardFail ? "all-sports-failed" : "success",
      totals,
    };
    return result;
  } finally {
    const finished = Date.now();
    const summary: Tank01RunSummary = {
      ok: result.ok,
      reason: result.reason ?? "success",
      trigger,
      totals: result.totals ?? null,
      startedAtIso,
      finishedAtIso: new Date(finished).toISOString(),
      durationMs: finished - started,
    };
    await writeTank01RunSummary(summary);
    try {
      await sendTank01SummaryEmail(summary, tank01Cfg, rosterCfg);
    } catch (e) {
      logger.error("Failed to send Tank01 summary email", {
        message: e instanceof Error ? e.message : String(e),
      });
    }
  }
}

/**
 * Scheduled nightly run. 06:00 America/New_York — Cloud Scheduler handles DST
 * automatically, so it's always 6 AM Eastern regardless of the time of year.
 */
export const nightlyRosterSync = onSchedule(
  {
    schedule: "every day 06:00",
    timeZone: "America/New_York",
    memory: "512MiB",
    timeoutSeconds: 540,
    retryCount: 1,
  },
  async () => {
    const result = await runSync("scheduled");
    if (!result.ok) {
      logger.info(`Scheduled run noop: ${result.reason}`);
      return;
    }
    logger.info("Scheduled run complete", {
      jobCount: result.jobCount,
      totals: result.totals,
    });
  },
);

/**
 * Tank01 → sports_tank01, once daily at 11:00 ET.
 */
export const tank01RosterSync = onSchedule(
  {
    schedule: "0 11 * * *",
    timeZone: "America/New_York",
    memory: "512MiB",
    timeoutSeconds: 540,
    retryCount: 1,
  },
  async () => {
    const result = await runTank01Sync("scheduled");
    if (!result.ok) {
      logger.info(`Tank01 scheduled run noop: ${result.reason}`);
      return;
    }
    logger.info("Tank01 scheduled run complete", { totals: result.totals });
  },
);

/**
 * Manual trigger: `firebase functions:shell` → `runRosterSyncNow({})` or call
 * from any authenticated admin client. Requires an authenticated caller.
 */
const ADMIN_EMAILS = new Set([
  "projectflofile@gmail.com",
  "dev@flofilecaptions.com",
]);

function isAdminCaller(auth: { token?: { email?: string; admin?: boolean } }): boolean {
  if (auth.token?.admin === true) return true;
  const email = auth.token?.email?.trim().toLowerCase();
  return !!email && ADMIN_EMAILS.has(email);
}

export const runRosterSyncNow = onCall(
  { memory: "512MiB", timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in as an admin to run the roster sync manually.",
      );
    }
    if (!isAdminCaller(request.auth)) {
      throw new HttpsError(
        "permission-denied",
        "Only admin accounts may run manual roster sync.",
      );
    }
    const result = await runSync("manual");
    return result;
  },
);

export const runTank01RosterSyncNow = onCall(
  { memory: "512MiB", timeoutSeconds: 540 },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError(
        "unauthenticated",
        "Sign in as an admin to run the Tank01 roster sync manually.",
      );
    }
    if (!isAdminCaller(request.auth)) {
      throw new HttpsError(
        "permission-denied",
        "Only admin accounts may run manual Tank01 roster sync.",
      );
    }
    return runTank01Sync("manual");
  },
);

/**
 * Emails admins when a signed-in caption user files a roster issue report
 * (duplicate dialog, session jersey edit, or player wrong-number / spelling).
 * Triggered by client writes to `roster_issue_reports/{id}`.
 */
export const onRosterIssueReportCreated = onDocumentCreated(
  {
    document: "roster_issue_reports/{reportId}",
    memory: "256MiB",
    timeoutSeconds: 60,
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const db = getFirestore();
    const [rosterSnap, tank01Snap] = await Promise.all([
      db.doc("roster_sync/config").get(),
      db.doc("tank01_sync/config").get(),
    ]);
    const rosterCfg = (rosterSnap.data() ?? {}) as RosterSyncConfig;
    const tank01Cfg = (tank01Snap.data() ?? {}) as Tank01SyncConfig;
    const apiKey = (
      tank01Cfg.resendApiKey ??
      rosterCfg.resendApiKey ??
      ""
    ).trim();
    if (!apiKey) {
      logger.warn("resendApiKey missing; skipping roster issue report email.");
      return;
    }
    const to = (
      tank01Cfg.emailSummaryTo ??
      rosterCfg.emailSummaryTo ??
      TANK01_EMAIL_DEFAULT_TO
    ).trim();
    const from = (
      tank01Cfg.emailSummaryFrom ??
      rosterCfg.emailSummaryFrom ??
      "FloFile Roster Issues <onboarding@resend.dev>"
    ).trim();

    const kind = String(data.kind ?? "unknown");
    const teamName = String(data.teamName ?? "Unknown team");
    const sportId = String(data.sportId ?? "unknown");
    const userEmail = String(data.userEmail ?? "(unknown user)");
    const userName = String(data.userDisplayName ?? "").trim();
    const userLine = userName
      ? `${userName} <${userEmail}>`
      : userEmail;

    let subject = `[Roster issue] ${teamName} · ${sportId}`;
    let text: string;

    if (kind === "playerDataIssue") {
      const side = String(data.side ?? "unknown");
      const note = String(data.note ?? "").trim();
      const issueTypes = Array.isArray(data.issueTypes)
        ? data.issueTypes.map((x) => String(x))
        : [];
      const labels = issueTypes.map((t) => {
        if (t === "wrongNumber") return "wrong jersey number";
        if (t === "spelling") return "spelling mistake";
        if (t === "dontUsePlayer") return "don't use this player";
        return t;
      });
      const issueLabel =
        labels.length > 0 ? labels.join(" + ") : "player data issue";
      const player =
        data.player && typeof data.player === "object"
          ? (data.player as {
              fullName?: unknown;
              jerseyNumber?: unknown;
              playerId?: unknown;
              position?: unknown;
            })
          : {};
      const fullName = String(player.fullName ?? "").trim() || "(unknown)";
      const jersey = String(player.jerseyNumber ?? "").trim() || "?";
      const playerId = String(player.playerId ?? "").trim();
      const position = String(player.position ?? "").trim();

      subject = `[Roster issue] ${issueLabel} · ${teamName}`;
      text = [
        "A signed-in FloFile user reported a player data problem.",
        "",
        `Issue: ${issueLabel}`,
        `User: ${userLine}`,
        `Sport: ${sportId}`,
        `Team: ${teamName}`,
        `Side: ${side}`,
        `Player: #${jersey} ${fullName}`,
        ...(position ? [`Position: ${position}`] : []),
        ...(playerId ? [`Player id: ${playerId}`] : []),
        `Report id: ${event.params.reportId}`,
        "",
        note ? `Note:\n${note}` : "Note: (none)",
        "",
        "Check the website admin Roster issues tab or Tank01 mirror if a permanent fix is needed.",
      ].join("\n");
    } else if (kind === "sessionJerseyEdit") {
      const changes = Array.isArray(data.changes) ? data.changes : [];
      const changeLines = changes
        .map((raw) => {
          if (!raw || typeof raw !== "object") return "";
          const row = raw as {
            fullName?: unknown;
            fromJersey?: unknown;
            toJersey?: unknown;
            position?: unknown;
          };
          const name = String(row.fullName ?? "").trim() || "(unknown)";
          const from = String(row.fromJersey ?? "").trim() || "?";
          const to = String(row.toJersey ?? "").trim() || "?";
          const pos = String(row.position ?? "").trim();
          const base = `  #${from} → #${to}  ${name}`;
          return pos ? `${base} (${pos})` : base;
        })
        .filter(Boolean);

      subject = `[Roster issue] session jersey edit · ${teamName}`;
      text = [
        "A signed-in FloFile user changed jersey number(s) for this session.",
        "",
        `User: ${userLine}`,
        `Sport: ${sportId}`,
        `Team: ${teamName}`,
        `Report id: ${event.params.reportId}`,
        "",
        "Changes:",
        ...(changeLines.length ? changeLines : ["  (none listed)"]),
        "",
        "These edits are session-only in the app (not written to the shared roster).",
        "Update the website admin roster / Tank01 mirror if a permanent fix is needed.",
      ].join("\n");
    } else {
      const conflicts = Array.isArray(data.conflicts) ? data.conflicts : [];
      const conflictLines = conflicts.flatMap((raw) => {
        if (!raw || typeof raw !== "object") return [] as string[];
        const c = raw as { jersey?: unknown; players?: unknown };
        const jersey = String(c.jersey ?? "?").trim();
        const players = Array.isArray(c.players) ? c.players : [];
        const names = players
          .map((p) => {
            if (!p || typeof p !== "object") return "";
            const row = p as { fullName?: unknown; position?: unknown };
            const name = String(row.fullName ?? "").trim();
            const pos = String(row.position ?? "").trim();
            if (!name) return "";
            return pos ? `  - ${name} (${pos})` : `  - ${name}`;
          })
          .filter(Boolean);
        return [`#${jersey}`, ...names, ""];
      });

      text = [
        "A signed-in FloFile user hit a duplicate jersey conflict.",
        "",
        `User: ${userLine}`,
        `Sport: ${sportId}`,
        `Team: ${teamName}`,
        `Report id: ${event.params.reportId}`,
        "",
        "Conflicts:",
        ...(conflictLines.length ? conflictLines : ["  (none listed)"]),
        "Session-only jersey edits may have been applied in the app.",
        "Check the website admin Roster issues tab or Tank01 mirror if a permanent fix is needed.",
      ].join("\n");
    }

    try {
      await sendResendEmail({ apiKey, from, to, subject, text });
      logger.info("Sent roster issue report email", {
        reportId: event.params.reportId,
        kind,
        to,
        teamName,
        sportId,
      });
    } catch (e) {
      logger.error("Failed to send roster issue report email", {
        message: e instanceof Error ? e.message : String(e),
        reportId: event.params.reportId,
        kind,
      });
      throw e;
    }
  },
);
