/**
 * Claude Code skill variables for pi bash calls.
 *
 * Claude Code substitutes `${CLAUDE_SKILL_DIR}` and `${CLAUDE_SESSION_ID}`
 * into a skill's text before the model sees it. pi does no substitution and
 * its bash tool exports neither variable, so a skill command such as
 * `bash "${CLAUDE_SKILL_DIR}/../../scripts/ensure-udas.sh"` runs as
 * `bash "/../../scripts/ensure-udas.sh"`. The pi binding closes that gap in its
 * `tool_call` handler: it resolves the skill directory from the command's own
 * relative paths and prepends one `export …` line to the command. pi clones
 * tool arguments before `tool_call` runs, so the rewrite reaches execution but
 * not the transcript. Pure helpers only; the wiring lives in index.ts.
 */

import { createHash } from "node:crypto";
import { join, resolve } from "node:path";

const SKILL_DIR_REF = /\$\{CLAUDE_SKILL_DIR\}|\$CLAUDE_SKILL_DIR(?![A-Za-z0-9_])/;
const SESSION_ID_REF = /\$\{CLAUDE_SESSION_ID(?:[}:])|\$CLAUDE_SESSION_ID(?![A-Za-z0-9_])/;
/** `${CLAUDE_SKILL_DIR}/rel` or `$CLAUDE_SKILL_DIR/rel`; rel stops at shell metacharacters. */
const SKILL_DIR_PATH_REF =
  /(?:\$\{CLAUDE_SKILL_DIR\}|\$CLAUDE_SKILL_DIR(?![A-Za-z0-9_]))\/([^\s"'`;|&<>()]+)/g;

export function referencesSkillDir(command: string): boolean {
  return SKILL_DIR_REF.test(command);
}

export function referencesSessionId(command: string): boolean {
  return SESSION_ID_REF.test(command);
}

/**
 * Every relative path appended to the skill-dir variable. Paths carrying their
 * own expansions or globs (`$x`, `*`) cannot be existence-checked and are
 * dropped.
 */
export function extractSkillDirPaths(command: string): string[] {
  const rels = new Set<string>();
  for (const match of command.matchAll(SKILL_DIR_PATH_REF)) {
    const rel = (match[1] as string).replace(/\/+$/, "");
    if (rel.length === 0 || /[$*?[\]{}]/.test(rel)) continue;
    rels.add(rel);
  }
  return [...rels];
}

/** Candidate skill directories, one list per tier, each most-relevant first. */
export interface SkillDirCandidates {
  /** Directories of SKILL.md files read via the `read` tool, most recent first. */
  read: readonly string[];
  /** Directories from `/skill:` expansions (`<skill … location="…">`), most recent first. */
  expanded: readonly string[];
  /** `dirname(path)` of every indexed skill. */
  indexed: readonly string[];
}

export type SkillDirResolution = { dir: string } | { unresolved: true } | { ambiguous: string[] };

/**
 * Pick the skill directory a command's `${CLAUDE_SKILL_DIR}/<rel>` references
 * belong to: the first candidate under which every `<rel>` exists.
 *
 * Session tiers (read history, then `/skill:` expansions) win outright by
 * order — the model is following the skill it last loaded. The index tier is
 * a fallback: several matching directories whose referenced files are
 * different real files is `ambiguous` (e.g. two skills each shipping
 * `scripts/run.sh`); matches that point at the same files (sibling skills
 * reaching `../../scripts/` in one plugin) resolve to the first.
 */
export function resolveSkillDir(
  command: string,
  candidates: SkillDirCandidates,
  exists: (path: string) => boolean,
  realpath: (path: string) => string = resolve,
): SkillDirResolution {
  const rels = extractSkillDirPaths(command);
  const matches = (dir: string) => rels.every((rel) => exists(join(dir, rel)));

  for (const dir of [...candidates.read, ...candidates.expanded]) {
    if (matches(dir)) return { dir };
  }

  const byTarget = new Map<string, string>();
  for (const dir of candidates.indexed) {
    if (!matches(dir)) continue;
    const targets = rels.length > 0 ? rels.map((rel) => realpath(join(dir, rel))) : [realpath(dir)];
    const key = targets.join("\0");
    if (!byTarget.has(key)) byTarget.set(key, dir);
  }
  if (byTarget.size === 1) return { dir: [...byTarget.values()][0] as string };
  if (byTarget.size > 1) return { ambiguous: [...byTarget.values()] };
  return { unresolved: true };
}

/** Directories of every `<skill name="…" location="<SKILL.md path>">` block in a prompt, in order. */
export function extractSkillLocations(prompt: string): string[] {
  const locations: string[] = [];
  for (const match of prompt.matchAll(/<skill name="[^"]*" location="([^"]+)">/g)) {
    locations.push(match[1] as string);
  }
  return locations;
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * A deterministic Claude-style session id for a pi session id. pi mints
 * UUIDv7 ids, whose first 8 hex characters are the high timestamp bits, so
 * `claude-${CLAUDE_SESSION_ID:0:8}` (the agent identity task-claim and
 * git-coworker-check build) would collide for sessions started within ~65
 * seconds. The derived id is a permutation that moves the random tail to the
 * front. A non-UUID input is hashed instead. Never the raw pi id.
 */
export function deriveSessionId(piId: string): string {
  const hex = UUID_RE.test(piId)
    ? (() => {
        const raw = piId.replace(/-/g, "").toLowerCase();
        // raw[0..12) timestamp, raw[12] version, raw[13..32) random tail.
        return raw.slice(13) + raw.slice(0, 13);
      })()
    : createHash("sha256").update(piId).digest("hex").slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

/** POSIX single-quote escaping: `'` becomes `'\''`. */
export function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

export interface ClaudeEnvValues {
  skillDir?: string;
  sessionId?: string;
  sessionFile?: string;
}

/**
 * Prepend one `export …` line when the command references `CLAUDE_SKILL_DIR`
 * or `CLAUDE_SESSION_ID`; otherwise return it unchanged. Only values that are
 * known are exported. `PI_SESSION_FILE` rides along so a skill script can find
 * pi's transcript. A prepended line (not a wrapper) matches pi's own
 * `commandPrefix` and leaves heredocs, `set -e`, and a leading `cd` intact.
 */
export function withClaudeEnv(command: string, values: ClaudeEnvValues): string {
  if (!referencesSkillDir(command) && !referencesSessionId(command)) return command;
  const assignments: string[] = [];
  if (values.skillDir !== undefined) {
    assignments.push(`CLAUDE_SKILL_DIR=${shellQuote(values.skillDir)}`);
  }
  if (values.sessionId !== undefined) {
    assignments.push(`CLAUDE_SESSION_ID=${shellQuote(values.sessionId)}`);
  }
  if (values.sessionFile !== undefined) {
    assignments.push(`PI_SESSION_FILE=${shellQuote(values.sessionFile)}`);
  }
  if (assignments.length === 0) return command;
  return `export ${assignments.join(" ")}\n${command}`;
}

/** Reason returned with a blocked bash call whose skill directory could not be resolved. */
export function unresolvedSkillDirReason(resolution: SkillDirResolution): string {
  const base =
    "CLAUDE_SKILL_DIR is a Claude Code variable that pi does not set, and this command's skill directory could not be determined";
  const detail =
    "ambiguous" in resolution ? ` (several skills match: ${resolution.ambiguous.join(", ")})` : "";
  return `${base}${detail}. Replace \${CLAUDE_SKILL_DIR} with the absolute directory of the SKILL.md you are following, then re-run the command.`;
}
