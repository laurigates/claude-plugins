/**
 * The harness-neutral half of session-plugin's two nudges (#2661 pi, #2802
 * OpenCode). Neither pi nor OpenCode evaluates a Claude Code hook manifest,
 * so each binding drives the nudges from its own events and calls in here
 * for what does not depend on the harness:
 *
 * - the spinup hook run (`session-spinup-nudge.sh`, unchanged, fed Claude
 *   Code's SessionStart stdin through a bash here-string, because pi's exec
 *   has no stdin option);
 * - the end hook's gates and offer text, mirrored from
 *   `session-end-nudge.sh` and pinned to it by the parity tests in
 *   tests/pi-session-nudges.test.ts and tests/opencode-session-nudges.test.ts;
 * - the end hook's "something to capture into" probe.
 *
 * Commands run through an injected `NudgeExec`, so the module imports only
 * node:* (core/ may import nothing else).
 */

import { existsSync } from "node:fs";
import { join } from "node:path";

/** Paths relative to the marketplace checkout. */
export const SPINUP_HOOK = ["session-plugin", "hooks", "session-spinup-nudge.sh"] as const;
export const SURVEY_SCRIPT = ["session-plugin", "scripts", "session-survey.sh"] as const;

/** The hooks' own timeouts in session-plugin/.claude-plugin/plugin.json (15 s, 10 s). */
export const SPINUP_TIMEOUT_MS = 15_000;
export const END_TIMEOUT_MS = 10_000;

/** session-end-nudge.sh gates, mirrored. */
export const MIN_USER_TURNS = 6;
export const RECENT_USER_WINDOW = 1;
export const WIND_DOWN_PATTERN =
  /\b(wrap up|wrap this|wrap the session|done for (today|now|the day)|calling it|good night|signing off|end of day|gotta go|heading out|i.?m done|thats it for|that.?s it for)\b/i;
/** The hook's mid-flow guard (#3180): a next-step proposal in the assistant's last text. */
export const MID_FLOW_PATTERN =
  /\b(next steps?|want me to|shall i|should i|would you like|which (option|one|way))\b/i;
export const END_TASK_CUE =
  " Also mention that a taskwarrior state-sync pass looks worth offering.";

/** An end-of-session skill that owns the flow once it is running. */
export const END_SKILL = /session-(wrap|end|distill)/;
/** A read of one of those skills' SKILL.md, the way a binding loads a skill search_skills returned. */
export const END_SKILL_FILE = /session-(wrap|end|distill)\/SKILL\.md$/;

/** The Stop hook's `reason`, verbatim, with or without the taskwarrior cue. */
export function endNudgeReason(taskCue: boolean): string {
  return `The user is winding down the session. Briefly offer to run the session-plugin:session-end orchestrator — it surveys the session once, runs the reversible end-of-session passes (session-wrap loose-thread capture, session-distill durable learnings, updates to tasks the session touched, /feedback:session issues) and asks once at the end for outward-facing items such as journal entries or cross-repo PRs.${taskCue ? END_TASK_CUE : ""} Offer only — never run it without explicit user confirmation. If nothing follow-up-worthy surfaced this session, acknowledge the wind-down and end.`;
}

/**
 * The hook's mid-flow guard: true when the assistant's last text ends with a
 * question or proposes a next step, so the session is not winding down
 * whatever the user's message matched. Same reading as the shell hook: the
 * last five non-blank lines, trailing whitespace and `*_\`)` stripped from
 * the final one before the `?` test.
 */
export function midFlow(lastAssistantText: string): boolean {
  const lines = lastAssistantText.split("\n").filter((line) => line.trim().length > 0);
  if (lines.length === 0) return false;
  const tail = lines.slice(-5);
  const lastLine = (tail[tail.length - 1] as string).replace(/[\s*_`)]*$/, "");
  if (lastLine.endsWith("?")) return true;
  return MID_FLOW_PATTERN.test(tail.join("\n"));
}

export interface NudgeExecResult {
  stdout: string;
  code: number;
  killed?: boolean;
}

/** The exec surface a binding supplies (pi's `pi.exec` has this shape). */
export type NudgeExec = (
  command: string,
  args: string[],
  options: { timeout: number; cwd?: string },
) => Promise<NudgeExecResult>;

async function execQuietly(
  exec: NudgeExec,
  command: string,
  args: string[],
  options: { timeout: number; cwd?: string },
): Promise<NudgeExecResult | Error> {
  try {
    return await exec(command, args, options);
  } catch (err) {
    return err instanceof Error ? err : new Error(String(err));
  }
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

/**
 * The end hook's "something to capture into" gate and its taskwarrior cue:
 * taskwarrior on PATH (then the survey decides the cue), else a distillable
 * surface (`.claude/rules/` or a justfile) at the repo root.
 */
export async function probeCapture(
  exec: NudgeExec,
  cwd: string,
  repoRoot: string,
): Promise<{ surface: boolean; openTasks: boolean }> {
  const which = await execQuietly(exec, "bash", ["-c", "command -v task"], {
    timeout: END_TIMEOUT_MS,
  });
  if (!(which instanceof Error) && which.code === 0) {
    const survey = join(repoRoot, ...SURVEY_SCRIPT);
    if (!existsSync(survey)) return { surface: true, openTasks: false };
    const result = await execQuietly(exec, "bash", [survey, "--summary", "--project-dir", cwd], {
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
  const top = await execQuietly(exec, "git", ["-C", cwd, "rev-parse", "--show-toplevel"], {
    timeout: END_TIMEOUT_MS,
  });
  const root = !(top instanceof Error) && top.code === 0 ? top.stdout.trim() : cwd;
  const surface = [".claude/rules", "justfile", "Justfile"].some((name) =>
    existsSync(join(root, name)),
  );
  return { surface, openTasks: false };
}

/**
 * Run the spinup hook unchanged with a Claude Code SessionStart payload.
 * Returns the hook's `additionalContext`, a warning to log, or nothing when
 * the hook stayed silent (or the checkout has no session-plugin).
 */
export async function runSpinupHook(
  exec: NudgeExec,
  payload: { source: string; sessionId: string; cwd: string },
  repoRoot: string,
): Promise<{ context: string } | { warning: string } | undefined> {
  const hook = join(repoRoot, ...SPINUP_HOOK);
  if (!existsSync(hook)) return undefined;
  const stdin = JSON.stringify({
    hook_event_name: "SessionStart",
    source: payload.source,
    session_id: payload.sessionId,
    cwd: payload.cwd,
  });
  // No stdin option on pi's exec; bash feeds the payload to the hook's `cat`.
  const result = await execQuietly(
    exec,
    "bash",
    ["-c", 'bash "$1" <<<"$2"', "session-nudge", hook, stdin],
    { timeout: SPINUP_TIMEOUT_MS, cwd: payload.cwd },
  );
  if (result instanceof Error || result.code !== 0 || result.killed) {
    const why =
      result instanceof Error
        ? result.message
        : result.killed
          ? `timed out after ${SPINUP_TIMEOUT_MS / 1000} s`
          : `exited ${result.code}`;
    return { warning: `session-nudges: ${SPINUP_HOOK.join("/")} ${why}` };
  }
  const out = result.stdout.trim();
  if (out.length === 0) return undefined;
  let context: unknown;
  try {
    context = JSON.parse(out)?.hookSpecificOutput?.additionalContext;
  } catch {
    return { warning: `session-nudges: ${SPINUP_HOOK.join("/")} printed non-JSON output` };
  }
  if (typeof context !== "string" || context.length === 0) return undefined;
  return { context };
}
