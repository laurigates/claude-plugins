/**
 * Claude Code skill variables for foreign-harness bash calls.
 *
 * Claude Code substitutes `${CLAUDE_SKILL_DIR}` and `${CLAUDE_SESSION_ID}`
 * into a skill's text before the model sees it, and sets
 * `${CLAUDE_PLUGIN_ROOT}` to the skill's plugin directory. pi and OpenCode do
 * none of this, so a skill command such as
 * `bash "${CLAUDE_SKILL_DIR}/../../scripts/ensure-udas.sh"` runs as
 * `bash "/../../scripts/ensure-udas.sh"`. Each binding closes that gap in its
 * pre-execution tool hook (pi `tool_call`, OpenCode `tool.execute.before`): it
 * resolves the skill directory from the command's own relative paths and
 * prepends one `export …` line to the command. The resolution and the rewrite
 * live here so every binding behaves the same; the hook wiring lives in each
 * binding's index.ts.
 */

import { createHash } from "node:crypto";
import { existsSync, realpathSync } from "node:fs";
import { basename, dirname, join, resolve } from "node:path";

/**
 * The Claude Code variables every binding emulates, in export order. A
 * foreign-visible skill that references any other `CLAUDE_*` variable fails
 * the class sweep in tests/claude-env.test.ts.
 */
export const CLAUDE_ENV_VARS = [
  "CLAUDE_SKILL_DIR",
  "CLAUDE_PLUGIN_ROOT",
  "CLAUDE_SESSION_ID",
] as const;
export type ClaudeEnvVar = (typeof CLAUDE_ENV_VARS)[number];

const SKILL_DIR_REF = /\$\{CLAUDE_SKILL_DIR\}|\$CLAUDE_SKILL_DIR(?![A-Za-z0-9_])/;
const PLUGIN_ROOT_REF = /\$\{CLAUDE_PLUGIN_ROOT\}|\$CLAUDE_PLUGIN_ROOT(?![A-Za-z0-9_])/;
const SESSION_ID_REF = /\$\{CLAUDE_SESSION_ID(?:[}:])|\$CLAUDE_SESSION_ID(?![A-Za-z0-9_])/;
/** `${CLAUDE_SKILL_DIR}/rel` or `$CLAUDE_SKILL_DIR/rel`; rel stops at shell metacharacters. */
const SKILL_DIR_PATH_REF =
  /(?:\$\{CLAUDE_SKILL_DIR\}|\$CLAUDE_SKILL_DIR(?![A-Za-z0-9_]))\/([^\s"'`;|&<>()]+)/g;
/** The same shape for `${CLAUDE_PLUGIN_ROOT}/rel`. */
const PLUGIN_ROOT_PATH_REF =
  /(?:\$\{CLAUDE_PLUGIN_ROOT\}|\$CLAUDE_PLUGIN_ROOT(?![A-Za-z0-9_]))\/([^\s"'`;|&<>()]+)/g;

export function referencesSkillDir(command: string): boolean {
  return SKILL_DIR_REF.test(command);
}

export function referencesPluginRoot(command: string): boolean {
  return PLUGIN_ROOT_REF.test(command);
}

export function referencesSessionId(command: string): boolean {
  return SESSION_ID_REF.test(command);
}

/** The emulated variables a command references, in CLAUDE_ENV_VARS order. */
export function referencedClaudeVars(command: string): ClaudeEnvVar[] {
  const found: ClaudeEnvVar[] = [];
  if (referencesSkillDir(command)) found.push("CLAUDE_SKILL_DIR");
  if (referencesPluginRoot(command)) found.push("CLAUDE_PLUGIN_ROOT");
  if (referencesSessionId(command)) found.push("CLAUDE_SESSION_ID");
  return found;
}

/**
 * Every relative path appended to a directory variable. Paths carrying their
 * own expansions or globs (`$x`, `*`) cannot be existence-checked and are
 * dropped.
 */
function extractRelPaths(command: string, pattern: RegExp): string[] {
  const rels = new Set<string>();
  for (const match of command.matchAll(pattern)) {
    const rel = (match[1] as string).replace(/\/+$/, "");
    if (rel.length === 0 || /[$*?[\]{}]/.test(rel)) continue;
    rels.add(rel);
  }
  return [...rels];
}

export function extractSkillDirPaths(command: string): string[] {
  return extractRelPaths(command, SKILL_DIR_PATH_REF);
}

export function extractPluginRootPaths(command: string): string[] {
  return extractRelPaths(command, PLUGIN_ROOT_PATH_REF);
}

/**
 * The plugin root of a skill directory: `<plugin>/skills/<name>` → `<plugin>`,
 * the layout the indexer scans (`<source>/skills/<dir>/SKILL.md`). Claude Code
 * sets `CLAUDE_PLUGIN_ROOT` to that directory. A SKILL.md outside the layout
 * has no plugin root.
 */
export function pluginRootOf(skillDir: string): string | undefined {
  const parent = dirname(skillDir);
  return basename(parent) === "skills" ? dirname(parent) : undefined;
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
 * Pick the skill directory a command's `${CLAUDE_SKILL_DIR}/<rel>` and
 * `${CLAUDE_PLUGIN_ROOT}/<rel>` references belong to: the first candidate
 * under which every skill-dir `<rel>` exists and, under its plugin root
 * (pluginRootOf), every plugin-root `<rel>` exists. A command that
 * references `CLAUDE_PLUGIN_ROOT` skips candidates with no plugin root.
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
  const rootRels = extractPluginRootPaths(command);
  const needsDir = referencesSkillDir(command);
  const needsRoot = referencesPluginRoot(command);
  /** The paths a candidate must provide, or undefined when it cannot. */
  const targetsOf = (dir: string): string[] | undefined => {
    const root = pluginRootOf(dir);
    if (needsRoot && root === undefined) return undefined;
    const paths = [
      ...rels.map((rel) => join(dir, rel)),
      ...rootRels.map((rel) => join(root as string, rel)),
    ];
    return paths.every(exists) ? paths : undefined;
  };

  for (const dir of [...candidates.read, ...candidates.expanded]) {
    if (targetsOf(dir) !== undefined) return { dir };
  }

  const byTarget = new Map<string, string>();
  for (const dir of candidates.indexed) {
    const paths = targetsOf(dir);
    if (paths === undefined) continue;
    // No relative paths: the directory itself (or, for a command that
    // references only the plugin root, that root) is what it points at.
    const fallback = needsRoot && !needsDir ? [pluginRootOf(dir) as string] : [dir];
    const key = (paths.length > 0 ? paths : fallback).map((path) => realpath(path)).join("\0");
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
 * A deterministic Claude-style session id for a harness session id. pi mints
 * UUIDv7 ids, whose first 8 hex characters are the high timestamp bits, so
 * `claude-${CLAUDE_SESSION_ID:0:8}` (the agent identity task-claim and
 * git-coworker-check build) would collide for sessions started within ~65
 * seconds. The derived id is a permutation that moves the random tail to the
 * front. A non-UUID input (OpenCode's `ses_…` ids, whose prefix is also
 * time-ordered) is hashed instead. Never the raw harness id.
 */
export function deriveSessionId(harnessId: string): string {
  const hex = UUID_RE.test(harnessId)
    ? (() => {
        const raw = harnessId.replace(/-/g, "").toLowerCase();
        // raw[0..12) timestamp, raw[12] version, raw[13..32) random tail.
        return raw.slice(13) + raw.slice(0, 13);
      })()
    : createHash("sha256").update(harnessId).digest("hex").slice(0, 32);
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20, 32)}`;
}

/** POSIX single-quote escaping: `'` becomes `'\''`. */
export function shellQuote(value: string): string {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

export interface ClaudeEnvValues {
  skillDir?: string;
  pluginRoot?: string;
  sessionId?: string;
  sessionFile?: string;
}

/**
 * Prepend one `export …` line when the command references any of
 * CLAUDE_ENV_VARS; otherwise return it unchanged. Only values that are known
 * are exported. `PI_SESSION_FILE` rides along when the binding supplies a
 * session file (pi does) so a skill script can find pi's transcript. A
 * prepended line (not a wrapper) matches pi's own `commandPrefix` and leaves
 * heredocs, `set -e`, and a leading `cd` intact.
 */
export function withClaudeEnv(command: string, values: ClaudeEnvValues): string {
  if (referencedClaudeVars(command).length === 0) return command;
  const assignments: string[] = [];
  if (values.skillDir !== undefined) {
    assignments.push(`CLAUDE_SKILL_DIR=${shellQuote(values.skillDir)}`);
  }
  if (values.pluginRoot !== undefined) {
    assignments.push(`CLAUDE_PLUGIN_ROOT=${shellQuote(values.pluginRoot)}`);
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

/**
 * Reason returned with a blocked bash call whose skill directory could not be
 * resolved. `vars` are the directory variables the command references.
 */
export function unresolvedSkillDirReason(
  resolution: SkillDirResolution,
  harness = "pi",
  vars: readonly ClaudeEnvVar[] = ["CLAUDE_SKILL_DIR"],
): string {
  const named = vars.filter((v) => v !== "CLAUDE_SESSION_ID");
  const subject =
    named.length > 1
      ? `${named.join(" and ")} are Claude Code variables`
      : `${named[0] ?? "CLAUDE_SKILL_DIR"} is a Claude Code variable`;
  const base = `${subject} that ${harness} does not set, and this command's skill directory could not be determined`;
  const detail =
    "ambiguous" in resolution ? ` (several skills match: ${resolution.ambiguous.join(", ")})` : "";
  const fixes: string[] = [];
  if (named.includes("CLAUDE_SKILL_DIR") || named.length === 0) {
    fixes.push(
      `\${CLAUDE_SKILL_DIR} with the absolute directory of the SKILL.md you are following`,
    );
  }
  if (named.includes("CLAUDE_PLUGIN_ROOT")) {
    fixes.push(
      `\${CLAUDE_PLUGIN_ROOT} with the plugin directory two levels above that SKILL.md (<plugin>/skills/<name>/SKILL.md)`,
    );
  }
  return `${base}${detail}. Replace ${fixes.join(", and ")}, then re-run the command.`;
}

/** Session-scoped skill directories the model has loaded, most recent first. */
export interface ClaudeEnvState {
  readDirs: string[];
  expandedDirs: string[];
}

export function createClaudeEnvState(): ClaudeEnvState {
  return { readDirs: [], expandedDirs: [] };
}

/** Move `dir` to the front of `dirs` (most recent first, no duplicates). */
export function recordSkillDir(dirs: string[], dir: string): void {
  const existing = dirs.indexOf(dir);
  if (existing !== -1) dirs.splice(existing, 1);
  dirs.unshift(dir);
}

export function realpathOrResolve(path: string): string {
  try {
    return realpathSync(path);
  } catch {
    return resolve(path);
  }
}

/** Session values a binding exports alongside the resolved skill directory. */
export interface ClaudeEnvSession {
  /** Already derived (see deriveSessionId), never the harness's raw id. */
  sessionId: string;
  sessionFile?: string;
}

/** A rewritten command to run, or the reason the call must not run. */
export type ClaudeEnvRewrite = { command: string } | { reason: string };

/**
 * The bash-call half of every binding's pre-execution hook. A command that
 * references none of CLAUDE_ENV_VARS returns `undefined` (leave it alone).
 * Otherwise the skill directory, when `CLAUDE_SKILL_DIR` or
 * `CLAUDE_PLUGIN_ROOT` is referenced, is resolved from the session tiers
 * first and the index only when those find nothing (`indexedDirs` is called
 * lazily, at most once); an unresolvable or ambiguous directory returns a
 * `reason` naming the fix. Only the variables the command references are
 * exported.
 */
export function rewriteClaudeEnvCommand(
  command: string,
  state: ClaudeEnvState,
  indexedDirs: () => readonly string[],
  session: ClaudeEnvSession,
  harness: string,
  exists: (path: string) => boolean = existsSync,
  realpath: (path: string) => string = realpathOrResolve,
): ClaudeEnvRewrite | undefined {
  const vars = referencedClaudeVars(command);
  if (vars.length === 0) return undefined;
  const needsSkillDir = vars.includes("CLAUDE_SKILL_DIR");
  const needsPluginRoot = vars.includes("CLAUDE_PLUGIN_ROOT");

  let dir: string | undefined;
  if (needsSkillDir || needsPluginRoot) {
    const tiers = { read: state.readDirs, expanded: state.expandedDirs, indexed: [] };
    let resolution = resolveSkillDir(command, tiers, exists, realpath);
    if ("unresolved" in resolution) {
      resolution = resolveSkillDir(command, { ...tiers, indexed: indexedDirs() }, exists, realpath);
    }
    if (!("dir" in resolution)) {
      return { reason: unresolvedSkillDirReason(resolution, harness, vars) };
    }
    dir = resolution.dir;
  }

  return {
    command: withClaudeEnv(command, {
      skillDir: needsSkillDir ? dir : undefined,
      pluginRoot: needsPluginRoot && dir !== undefined ? pluginRootOf(dir) : undefined,
      sessionId: session.sessionId,
      sessionFile: session.sessionFile,
    }),
  };
}
