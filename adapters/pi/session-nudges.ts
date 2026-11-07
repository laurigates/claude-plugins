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
 * The gates, offer text, capture probe and spinup hook run live in
 * core/session-nudges.ts, which the OpenCode binding shares (#2802); this
 * module keeps pi's event wiring and session-entry readers.
 *
 * Runtime imports stay inside the binding's allowed surface (node:*,
 * relative paths and a type-only pi import).
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import {
  END_SKILL,
  END_SKILL_FILE,
  endNudgeReason,
  MIN_USER_TURNS,
  type NudgeExec,
  probeCapture,
  RECENT_USER_WINDOW,
  runSpinupHook,
  WIND_DOWN_PATTERN,
} from "../core/session-nudges.ts";

export {
  END_TASK_CUE,
  END_TIMEOUT_MS,
  endNudgeReason,
  MIN_USER_TURNS,
  RECENT_USER_WINDOW,
  SPINUP_HOOK,
  SPINUP_TIMEOUT_MS,
  SURVEY_SCRIPT,
  WIND_DOWN_PATTERN,
} from "../core/session-nudges.ts";

export const SPINUP_NUDGE_TYPE = "session-spinup-nudge";
export const END_NUDGE_TYPE = "session-end-nudge";

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

/** pi.exec as the core's NudgeExec (pi's result carries stdout, code and killed). */
function execOf(api: NudgeApi): NudgeExec {
  return (command, args, options) => api.exec(command, args, options);
}

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
        if (typeof path === "string" && END_SKILL_FILE.test(path)) {
          return true;
        }
      }
    }
  }
  return false;
}

/** session_start body: run the spinup hook and queue what it prints. */
export async function runSpinupNudge(
  api: NudgeApi,
  event: { reason: string },
  ctx: NudgeContext,
  repoRoot: string,
  warn: (message: string) => void,
): Promise<void> {
  const result = await runSpinupHook(
    execOf(api),
    {
      source: sessionStartSource(event.reason),
      sessionId: ctx.sessionManager.getSessionId(),
      cwd: ctx.cwd,
    },
    repoRoot,
  );
  if (result === undefined) return;
  if ("warning" in result) {
    warn(result.warning);
    return;
  }
  api.sendMessage(
    { customType: SPINUP_NUDGE_TYPE, content: result.context, display: true },
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
    const capture = await probeCapture(execOf(api), ctx.cwd, repoRoot);
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
