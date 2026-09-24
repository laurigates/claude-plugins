/**
 * session-plugin's two nudges under pi (#2661). pi never evaluates a Claude
 * Code hook manifest, so session-plugin's SessionStart and Stop hooks are
 * inert there without this module.
 *
 * - Spinup: `session_start` runs `session-spinup-nudge.sh` unchanged, fed the
 *   Claude Code SessionStart stdin shape, and queues its `additionalContext`
 *   for the next turn. The hook keeps its own survey call, gating and
 *   once-per-session state file.
 * - End: `session-end-nudge.sh` reads Claude Code's transcript JSONL and
 *   answers with a Stop `decision: block`, neither of which exists in pi. Its
 *   gates are reimplemented over pi's session entries on `agent_settled` (pi
 *   will not continue on its own), and the offer is sent as a follow-up that
 *   triggers one more turn. The phrase list, thresholds and offer text are
 *   pinned to the shell hook by tests/pi-session-nudges.test.ts.
 *
 * Runtime imports stay inside the binding's allowed surface (node:* and a
 * type-only pi import).
 */

import { existsSync } from "node:fs";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export const SPINUP_NUDGE_TYPE = "session-spinup-nudge";
export const END_NUDGE_TYPE = "session-end-nudge";

/** Paths relative to the marketplace checkout. */
export const SPINUP_HOOK = ["session-plugin", "hooks", "session-spinup-nudge.sh"] as const;
export const SURVEY_SCRIPT = ["session-plugin", "scripts", "session-survey.sh"] as const;

/** The hooks' own timeouts in session-plugin/.claude-plugin/plugin.json (15 s, 10 s). */
export const SPINUP_TIMEOUT_MS = 15_000;
export const END_TIMEOUT_MS = 10_000;

/** session-end-nudge.sh gates, mirrored. */
export const MIN_USER_TURNS = 6;
export const RECENT_USER_WINDOW = 3;
export const WIND_DOWN_PATTERN =
  /\b(wrap up|wrap this|wrap the session|done for (today|now|the day)|calling it|good night|signing off|end of day|gotta go|heading out|i.?m done|thats it for|that.?s it for)\b/i;
export const END_TASK_CUE =
  " Also mention that a taskwarrior state-sync pass looks worth offering.";

/** The Stop hook's `reason`, verbatim, with or without the taskwarrior cue. */
export function endNudgeReason(taskCue: boolean): string {
  return `The user is winding down the session. Briefly offer to run the session-plugin:session-end orchestrator — it surveys the session once, previews which end-of-session passes qualify (session-wrap loose-thread capture, session-distill durable learnings, /feedback:session plugin feedback) and runs only what the user confirms in a single prompt.${taskCue ? END_TASK_CUE : ""} Offer only — never run it without explicit user confirmation. If nothing follow-up-worthy surfaced this session, acknowledge the wind-down and end.`;
}

/** An end-of-session skill that owns the flow once it is running. */
const END_SKILL = /session-(wrap|end|distill)/;
const SKILL_EXPANSION = /^<skill name="([^"]*)"/;

/** The slice of a pi session entry the gates read. */
export interface NudgeEntry {
  type: string;
  customType?: string;
  message?: unknown;
}

export interface NudgeContext {
  cwd: string;
  sessionManager: {
    getSessionId(): string;
    getEntries(): readonly NudgeEntry[];
    getBranch(): readonly NudgeEntry[];
  };
}

export type NudgeApi = Pick<ExtensionAPI, "exec" | "sendMessage">;

export interface SessionNudgeOptions {
  /** Marketplace checkout root (config.repoRoot). */
  repoRoot: () => string;
  /** false turns both nudges off (config.sessionNudges). */
  enabled: () => boolean;
  warn?: (message: string) => void;
}

/**
 * pi `session_start` reason → the Claude Code SessionStart `source` the hook
 * gates on. Same mapping as the #2634 hook bridge: `/new` is Claude Code's
 * `/clear`, and a fork continues an existing conversation.
 */
export function sessionStartSource(reason: string): string {
  if (reason === "new") return "clear";
  if (reason === "fork") return "resume";
  return reason;
}

interface Message {
  role?: unknown;
  content?: unknown;
}

function messageOf(entry: NudgeEntry): Message | undefined {
  if (entry.type !== "message" || typeof entry.message !== "object" || entry.message === null) {
    return undefined;
  }
  return entry.message as Message;
}

function textOf(content: unknown): string {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .filter((part) => part?.type === "text" && typeof part.text === "string")
    .map((part) => part.text as string)
    .join("\n");
}

/**
 * Text of every user message the person typed, in order. `/skill:` expansions
 * are skill markdown, not a user turn (Claude Code's `command-name>` filter);
 * tool results are their own role in pi, so they never appear here.
 */
export function genuineUserMessages(entries: readonly NudgeEntry[]): string[] {
  const texts: string[] = [];
  for (const entry of entries) {
    const message = messageOf(entry);
    if (message?.role !== "user") continue;
    const text = textOf(message.content);
    if (SKILL_EXPANSION.test(text)) continue;
    texts.push(text);
  }
  return texts;
}

/**
 * An end-of-session skill already loaded this session: a `/skill:` expansion
 * of one, or a `read` of its SKILL.md (how the model loads a skill that
 * `search_skills` returned).
 */
export function endSkillLoaded(entries: readonly NudgeEntry[]): boolean {
  for (const entry of entries) {
    const message = messageOf(entry);
    if (message?.role === "user") {
      const name = textOf(message.content).match(SKILL_EXPANSION)?.[1];
      if (name !== undefined && END_SKILL.test(name)) return true;
    }
    if (message?.role === "assistant" && Array.isArray(message.content)) {
      for (const part of message.content) {
        if (part?.type !== "toolCall" || part.name !== "read") continue;
        const path = part.arguments?.path;
        if (typeof path === "string" && /session-(wrap|end|distill)\/SKILL\.md$/.test(path)) {
          return true;
        }
      }
    }
  }
  return false;
}

function parseSummary(stdout: string): Map<string, string> {
  const fields = new Map<string, string>();
  for (const line of stdout.split("\n")) {
    const eq = line.indexOf("=");
    if (eq > 0 && !fields.has(line.slice(0, eq))) fields.set(line.slice(0, eq), line.slice(eq + 1));
  }
  return fields;
}

function positive(value: string | undefined): boolean {
  return Number(value ?? "0") > 0;
}

type ExecResult = Awaited<ReturnType<NudgeApi["exec"]>>;

async function execQuietly(
  api: NudgeApi,
  command: string,
  args: string[],
  options: { timeout: number; cwd?: string },
): Promise<ExecResult | Error> {
  try {
    return await api.exec(command, args, options);
  } catch (err) {
    return err instanceof Error ? err : new Error(String(err));
  }
}

/**
 * The end hook's "something to capture into" gate and its taskwarrior cue:
 * taskwarrior on PATH (then the survey decides the cue), else a distillable
 * surface (`.claude/rules/` or a justfile) at the repo root.
 */
async function probeCapture(
  api: NudgeApi,
  cwd: string,
  repoRoot: string,
): Promise<{ surface: boolean; openTasks: boolean }> {
  const which = await execQuietly(api, "bash", ["-c", "command -v task"], {
    timeout: END_TIMEOUT_MS,
  });
  if (!(which instanceof Error) && which.code === 0) {
    const survey = join(repoRoot, ...SURVEY_SCRIPT);
    if (!existsSync(survey)) return { surface: true, openTasks: false };
    const result = await execQuietly(api, "bash", [survey, "--summary", "--project-dir", cwd], {
      timeout: END_TIMEOUT_MS,
      cwd,
    });
    const summary = parseSummary(result instanceof Error ? "" : result.stdout);
    const openTasks =
      positive(summary.get("OPEN_TASKS")) ||
      positive(summary.get("RECENT_TASK_COUNT")) ||
      // A low-confidence zero is an unqueried project, never a clean queue.
      ((summary.get("TASK_SCOPE") ?? "") !== "none" && summary.get("PROJECT_CONFIDENCE") === "low");
    return { surface: true, openTasks };
  }
  const top = await execQuietly(api, "git", ["-C", cwd, "rev-parse", "--show-toplevel"], {
    timeout: END_TIMEOUT_MS,
  });
  const root = !(top instanceof Error) && top.code === 0 ? top.stdout.trim() : cwd;
  const surface = [".claude/rules", "justfile", "Justfile"].some((name) =>
    existsSync(join(root, name)),
  );
  return { surface, openTasks: false };
}

/** session_start body: run the spinup hook and queue what it prints. */
export async function runSpinupNudge(
  api: NudgeApi,
  event: { reason: string },
  ctx: NudgeContext,
  repoRoot: string,
  warn: (message: string) => void,
): Promise<void> {
  const hook = join(repoRoot, ...SPINUP_HOOK);
  if (!existsSync(hook)) return;
  const payload = JSON.stringify({
    hook_event_name: "SessionStart",
    source: sessionStartSource(event.reason),
    session_id: ctx.sessionManager.getSessionId(),
    cwd: ctx.cwd,
  });
  // pi.exec has no stdin option; bash feeds the payload to the hook's `cat`.
  const result = await execQuietly(
    api,
    "bash",
    ["-c", 'bash "$1" <<<"$2"', "session-nudge", hook, payload],
    { timeout: SPINUP_TIMEOUT_MS, cwd: ctx.cwd },
  );
  if (result instanceof Error || result.code !== 0 || result.killed) {
    const why =
      result instanceof Error
        ? result.message
        : result.killed
          ? `timed out after ${SPINUP_TIMEOUT_MS / 1000} s`
          : `exited ${result.code}`;
    warn(`session-nudges: ${SPINUP_HOOK.join("/")} ${why}`);
    return;
  }
  const out = result.stdout.trim();
  if (out.length === 0) return;
  let context: unknown;
  try {
    context = JSON.parse(out)?.hookSpecificOutput?.additionalContext;
  } catch {
    warn(`session-nudges: ${SPINUP_HOOK.join("/")} printed non-JSON output`);
    return;
  }
  if (typeof context !== "string" || context.length === 0) return;
  api.sendMessage(
    { customType: SPINUP_NUDGE_TYPE, content: context, display: true },
    { deliverAs: "nextTurn" },
  );
}

/** Per-registration state: sessions already nudged, and sessions mid-probe. */
export interface EndNudgeState {
  nudged: Set<string>;
  pending: Set<string>;
}

/**
 * agent_settled body. Cheap gates run before the probe that execs anything,
 * because `agent_settled` fires after every turn.
 */
export async function runEndNudge(
  api: NudgeApi,
  ctx: NudgeContext,
  repoRoot: string,
  state: EndNudgeState,
): Promise<void> {
  const sessionId = ctx.sessionManager.getSessionId();
  if (state.nudged.has(sessionId) || state.pending.has(sessionId)) return;
  const entries = ctx.sessionManager.getEntries();
  // At most once per session: the nudge is persisted as a custom message, so
  // this also holds across a resume.
  if (
    entries.some((entry) => entry.type === "custom_message" && entry.customType === END_NUDGE_TYPE)
  ) {
    return;
  }
  if (endSkillLoaded(entries)) return;
  const users = genuineUserMessages(ctx.sessionManager.getBranch());
  if (users.length < MIN_USER_TURNS) return;
  if (!users.slice(-RECENT_USER_WINDOW).some((text) => WIND_DOWN_PATTERN.test(text))) return;

  state.pending.add(sessionId);
  try {
    const capture = await probeCapture(api, ctx.cwd, repoRoot);
    if (!capture.surface) return;
    state.nudged.add(sessionId);
    api.sendMessage(
      { customType: END_NUDGE_TYPE, content: endNudgeReason(capture.openTasks), display: true },
      { triggerTurn: true, deliverAs: "followUp" },
    );
  } finally {
    state.pending.delete(sessionId);
  }
}

export function registerSessionNudges(
  pi: Pick<ExtensionAPI, "on" | "exec" | "sendMessage">,
  options: SessionNudgeOptions,
): void {
  const warn = options.warn ?? ((message: string) => console.warn(message));
  const state: EndNudgeState = { nudged: new Set(), pending: new Set() };

  pi.on("session_start", async (event, ctx) => {
    if (!options.enabled()) return;
    await runSpinupNudge(pi, event, ctx, options.repoRoot(), warn);
  });

  pi.on("agent_settled", async (_event, ctx) => {
    if (!options.enabled()) return;
    await runEndNudge(pi, ctx, options.repoRoot(), state);
  });
}
