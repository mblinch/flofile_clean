/**
 * Nightly roster sync (Firebase Cloud Functions v2).
 *
 * - `nightlyRosterSync`: scheduled daily at 06:00 America/New_York (DST-safe).
 * - `runRosterSyncNow`: callable trigger for manual runs from `firebase functions:shell`
 *    or the Firebase console. Requires an authenticated caller (admin-only by default).
 *
 * Firestore config (doc `roster_sync/config`):
 *   enabled?: boolean    default true
 *   syncAllMlb?: boolean if true, runs every MLB team from statsapi.mlb.com
 *   items?: Array<{ sportId, teamId }>  used when syncAllMlb is not true
 */

import { initializeApp } from "firebase-admin/app";
import { FieldValue, getFirestore } from "firebase-admin/firestore";
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

type SyncTrigger = "scheduled" | "manual";
const MAX_CHANGED_PLAYERS_IN_EMAIL = 120;

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
  if (!apiKey || !apiKey.trim()) {
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
  const text = bodyLines.join("\n");

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject,
      text,
    }),
  });
  if (!res.ok) {
    const errorText = await res.text();
    throw new Error(`Resend email failed (${res.status}): ${errorText}`);
  }
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
 * Manual trigger: `firebase functions:shell` → `runRosterSyncNow({})` or call
 * from any authenticated admin client. Requires an authenticated caller.
 */
const ADMIN_EMAILS = new Set(["projectflofile@gmail.com"]);

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
