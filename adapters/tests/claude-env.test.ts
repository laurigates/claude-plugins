/**
 * Shared Claude Code variable resolver (core/claude-env.ts) — the
 * ${CLAUDE_PLUGIN_ROOT} additions (#2662) — and the class sweep behind them.
 *
 * The class: a Claude Code variable referenced by a skill that pi or OpenCode
 * can see, which a foreign binding does not emulate. Such a command runs with
 * the variable unset, so `bash "${CLAUDE_PLUGIN_ROOT}/scripts/x.sh"` becomes
 * `bash "/scripts/x.sh"`. The sweep walks the marketplace the way the
 * adapters index it (scanSkills, "foreign" target, so skills marked
 * `compatibility: claude-code` are out of scope) and checks three things:
 * every referenced CLAUDE_* variable is one the shared resolver emulates, the
 * resolver detects each occurrence as written, and both bindings export each
 * variable a skill references once its SKILL.md has been read. The last check
 * runs the rewritten command in bash, so it tests the value the shell sees.
 * The per-binding helper tests live in pi-binding.test.ts and
 * opencode-binding.test.ts.
 */

// biome-ignore-all lint/suspicious/noTemplateCurlyInString: the fixtures are literal shell commands containing ${CLAUDE_*}

import { describe, expect, test } from "bun:test";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import type { Hooks, PluginInput } from "@opencode-ai/plugin";
import {
  CLAUDE_ENV_VARS,
  type ClaudeEnvVar,
  deriveSessionId,
  extractPluginRootPaths,
  pluginRootOf,
  referencedClaudeVars,
  resolveSkillDir,
  unresolvedSkillDirReason,
  withClaudeEnv,
} from "../core/claude-env.ts";
import { scanSkills } from "../core/indexer.ts";
import { SkillDiscoveryPlugin } from "../opencode/index.ts";
import skillDiscovery, { DEFAULT_REPO_ROOT } from "../pi/index.ts";

// --- CLAUDE_PLUGIN_ROOT helpers -------------------------------------------

/**
 * Two plugins shipping a plugin-level `scripts/shared.py` (so the index tier
 * can be ambiguous across plugins), one skill with its own script, and a
 * SKILL.md outside the `<plugin>/skills/<name>` layout (no plugin root).
 */
function pluginRootFixture() {
  const root = mkdtempSync(join(tmpdir(), "claude-env-root-"));
  const touch = (rel: string) => {
    const path = join(root, rel);
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, "x");
  };
  touch("alpha-plugin/scripts/shared.py");
  touch("alpha-plugin/skills/one/SKILL.md");
  touch("alpha-plugin/skills/one/scripts/own.sh");
  touch("alpha-plugin/skills/two/SKILL.md");
  touch("beta-plugin/scripts/shared.py");
  touch("beta-plugin/skills/three/SKILL.md");
  touch("loose/SKILL.md");
  touch("loose/scripts/shared.py");
  const dir = (rel: string) => join(root, rel);
  return {
    alpha: dir("alpha-plugin"),
    one: dir("alpha-plugin/skills/one"),
    two: dir("alpha-plugin/skills/two"),
    three: dir("beta-plugin/skills/three"),
    loose: dir("loose"),
  };
}

const NONE = { read: [], expanded: [], indexed: [] };
const SHARED = 'python3 "${CLAUDE_PLUGIN_ROOT}/scripts/shared.py" --audit';

describe("CLAUDE_PLUGIN_ROOT helpers", () => {
  test("pluginRootOf is the plugin above a <plugin>/skills/<name> directory, else undefined", () => {
    const f = pluginRootFixture();
    expect(pluginRootOf(f.one)).toBe(f.alpha);
    expect(pluginRootOf(f.loose)).toBeUndefined();
  });

  test("referencedClaudeVars lists each emulated variable once, in CLAUDE_ENV_VARS order", () => {
    const command =
      'bash "${CLAUDE_PLUGIN_ROOT}/x.sh" "claude-${CLAUDE_SESSION_ID:0:8}" $CLAUDE_SKILL_DIR/y ${CLAUDE_SKILL_DIR}/z';
    expect(referencedClaudeVars(command)).toEqual([...CLAUDE_ENV_VARS]);
    for (const near of [
      "echo $CLAUDE_PLUGIN_ROOTS",
      "echo ${CLAUDE_PLUGIN_ROOT_X}",
      "echo $HOME",
    ]) {
      expect(referencedClaudeVars(near)).toEqual([]);
    }
  });

  test("extractPluginRootPaths reads braced and bare forms and drops globs", () => {
    expect(
      extractPluginRootPaths(
        'python3 "${CLAUDE_PLUGIN_ROOT}/scripts/a.py" && bash $CLAUDE_PLUGIN_ROOT/hooks/b.sh; ls ${CLAUDE_PLUGIN_ROOT}/*.md',
      ),
    ).toEqual(["scripts/a.py", "hooks/b.sh"]);
  });

  test("a read skill's plugin root satisfies ${CLAUDE_PLUGIN_ROOT}/<rel>", () => {
    const f = pluginRootFixture();
    expect(resolveSkillDir(SHARED, { ...NONE, read: [f.one] }, existsSync)).toEqual({ dir: f.one });
  });

  test("a read SKILL.md outside the plugin layout has no plugin root and is skipped", () => {
    const f = pluginRootFixture();
    // loose/scripts/shared.py exists, but loose/ is not <plugin>/skills/<name>.
    expect(resolveSkillDir(SHARED, { ...NONE, read: [f.loose, f.three] }, existsSync)).toEqual({
      dir: f.three,
    });
  });

  test("index siblings in one plugin reach the same real file and are not ambiguous", () => {
    const f = pluginRootFixture();
    expect(resolveSkillDir(SHARED, { ...NONE, indexed: [f.one, f.two] }, existsSync)).toEqual({
      dir: f.one,
    });
  });

  test("index matches in different plugins are ambiguous", () => {
    const f = pluginRootFixture();
    expect(resolveSkillDir(SHARED, { ...NONE, indexed: [f.one, f.three] }, existsSync)).toEqual({
      ambiguous: [f.one, f.three],
    });
  });

  test("a command using both variables needs a directory that satisfies both", () => {
    const f = pluginRootFixture();
    const command =
      'bash "${CLAUDE_SKILL_DIR}/scripts/own.sh" "${CLAUDE_PLUGIN_ROOT}/scripts/shared.py"';
    expect(
      resolveSkillDir(command, { ...NONE, indexed: [f.two, f.three, f.one] }, existsSync),
    ).toEqual({ dir: f.one });
  });

  test("withClaudeEnv exports CLAUDE_PLUGIN_ROOT for a command that references only it", () => {
    const rewritten = withClaudeEnv('printf %s "$CLAUDE_PLUGIN_ROOT"', {
      pluginRoot: "/tmp/it's a plugin",
      sessionId: "abc",
    });
    expect(rewritten).toBe(
      `export CLAUDE_PLUGIN_ROOT='/tmp/it'\\''s a plugin' CLAUDE_SESSION_ID='abc'\nprintf %s "$CLAUDE_PLUGIN_ROOT"`,
    );
    const run = Bun.spawnSync(["bash", "-c", rewritten]);
    expect(run.stdout.toString()).toBe("/tmp/it's a plugin");
  });

  test("the unresolved reason names the harness and every unresolved variable's fix", () => {
    const reason = unresolvedSkillDirReason({ unresolved: true }, "OpenCode", [
      "CLAUDE_SKILL_DIR",
      "CLAUDE_PLUGIN_ROOT",
    ]);
    expect(reason).toContain("OpenCode does not set");
    expect(reason).toContain("absolute directory of the SKILL.md");
    expect(reason).toContain("${CLAUDE_PLUGIN_ROOT}");
  });
});

// --- class sweep ------------------------------------------------------------

/** Any `$CLAUDE_X` / `${CLAUDE_X…}` token, cut at the first shell metacharacter. */
const CLAUDE_VAR_TOKEN = /\$\{?(CLAUDE_[A-Z_]+)[^\s"'`;|&<>()]*/g;

interface Occurrence {
  id: string;
  variable: string;
  token: string;
}

const FOREIGN_SKILLS = scanSkills(DEFAULT_REPO_ROOT).entries;
const OCCURRENCES: Occurrence[] = FOREIGN_SKILLS.flatMap((entry) =>
  [...readFileSync(entry.path, "utf8").matchAll(CLAUDE_VAR_TOKEN)].map((match) => ({
    id: entry.id,
    variable: match[1] as string,
    token: match[0],
  })),
);

/** Each foreign skill that references an emulated variable, with the variables it references. */
const REFERENCING = FOREIGN_SKILLS.flatMap((entry) => {
  const found = new Set(OCCURRENCES.filter((o) => o.id === entry.id).map((o) => o.variable));
  const vars = CLAUDE_ENV_VARS.filter((v) => found.has(v));
  return vars.length > 0 ? [{ entry, vars }] : [];
});

const PI_SESSION = "01a08aa2-cd0e-7a31-9f4c-1b2d3e4f5a6b";
const OC_SESSION = "ses_1a2b3c4d5e6fQ7rS8tU9vW0xYz";
/** Unbound port: the OpenCode binding's health probe and embed calls fail fast. */
const DEAD_ENDPOINT = "http://127.0.0.1:1";
/** Each binding sweep spawns one bash per referencing skill (~1 s locally for ~60). */
const SWEEP_TIMEOUT_MS = 30_000;

/** Prints each referenced variable on its own line, in CLAUDE_ENV_VARS order. */
function probeCommand(vars: readonly ClaudeEnvVar[]): string {
  return `printf '%s\\n' ${vars.map((v) => `"\${${v}}"`).join(" ")}`;
}

function expectedLines(skillPath: string, vars: readonly ClaudeEnvVar[], sessionId: string) {
  const skillDir = dirname(skillPath);
  const values: Record<ClaudeEnvVar, string> = {
    CLAUDE_SKILL_DIR: skillDir,
    CLAUDE_PLUGIN_ROOT: dirname(dirname(skillDir)),
    CLAUDE_SESSION_ID: deriveSessionId(sessionId),
  };
  return vars.map((v) => values[v]).join("\n");
}

/** Runs a rewritten command with none of the variables inherited from this process. */
function runInBash(command: string): string {
  const run = Bun.spawnSync(["bash", "-c", command], { env: { PATH: process.env.PATH ?? "" } });
  return run.stdout.toString().trimEnd();
}

describe("class sweep: Claude variables in foreign-visible skills are emulated by every binding", () => {
  test("the sweep sees the marketplace (non-vacuous)", () => {
    expect(FOREIGN_SKILLS.length).toBeGreaterThan(300);
    expect(OCCURRENCES.length).toBeGreaterThan(50);
    // Control: the token pattern matches a variable known to be referenced.
    expect(OCCURRENCES.some((o) => o.variable === "CLAUDE_SKILL_DIR")).toBe(true);
    expect(REFERENCING.length).toBeGreaterThan(50);
  });

  test("every CLAUDE_* variable a foreign-visible skill references is emulated", () => {
    const emulated = new Set<string>(CLAUDE_ENV_VARS);
    const gaps = OCCURRENCES.filter((o) => !emulated.has(o.variable)).map(
      (o) => `${o.id}: ${o.token}`,
    );
    // A gap means pi and OpenCode run that command with the variable unset.
    // Either emulate it in core/claude-env.ts (both bindings share it) or
    // mark the skill `compatibility: claude-code`.
    expect(gaps).toEqual([]);
  });

  test("the resolver detects every occurrence as written", () => {
    const missed = OCCURRENCES.filter(
      (o) =>
        CLAUDE_ENV_VARS.includes(o.variable as ClaudeEnvVar) &&
        !referencedClaudeVars(o.token).includes(o.variable as ClaudeEnvVar),
    ).map((o) => `${o.id}: ${o.token}`);
    expect(missed).toEqual([]);
  });

  test(
    "pi exports each referenced variable after the skill's SKILL.md is read",
    async () => {
      const handlers = new Map<string, (event: unknown, ctx: unknown) => unknown>();
      const pi = {
        registerTool() {},
        on(event: string, handler: (event: unknown, ctx: unknown) => unknown) {
          handlers.set(event, handler);
        },
      } as unknown as ExtensionAPI;
      await skillDiscovery(pi);
      const toolCall = handlers.get("tool_call");
      expect(toolCall).toBeDefined();
      const ctx = {
        cwd: DEFAULT_REPO_ROOT,
        sessionManager: { getSessionId: () => PI_SESSION, getSessionFile: () => undefined },
      };
      const call = toolCall as (event: unknown, ctx: unknown) => unknown;

      const failures: string[] = [];
      for (const { entry, vars } of REFERENCING) {
        await call(
          { type: "tool_call", toolCallId: "r", toolName: "read", input: { path: entry.path } },
          ctx,
        );
        const input = { command: probeCommand(vars) };
        const result = (await call(
          { type: "tool_call", toolCallId: "b", toolName: "bash", input },
          ctx,
        )) as { reason: string } | undefined;
        if (result !== undefined) {
          failures.push(`${entry.id}: blocked: ${result.reason}`);
          continue;
        }
        const printed = runInBash(input.command);
        const expected = expectedLines(entry.path, vars, PI_SESSION);
        if (printed !== expected) failures.push(`${entry.id}: printed ${JSON.stringify(printed)}`);
      }
      expect(failures).toEqual([]);
    },
    SWEEP_TIMEOUT_MS,
  );

  test(
    "OpenCode exports each referenced variable after the skill's SKILL.md is read",
    async () => {
      const hooks: Hooks = await SkillDiscoveryPlugin(
        {
          serverUrl: new URL(DEAD_ENDPOINT),
          directory: DEFAULT_REPO_ROOT,
          worktree: DEFAULT_REPO_ROOT,
        } as unknown as PluginInput,
        { repoRoot: DEFAULT_REPO_ROOT, endpoint: DEAD_ENDPOINT },
      );
      const before = hooks["tool.execute.before"];
      expect(before).toBeDefined();

      const failures: string[] = [];
      for (const { entry, vars } of REFERENCING) {
        const input = (tool: string) => ({ tool, sessionID: OC_SESSION, callID: "c" });
        const args = { command: probeCommand(vars) };
        try {
          await before?.(input("read"), { args: { filePath: entry.path } });
          await before?.(input("bash"), { args });
        } catch (error) {
          failures.push(`${entry.id}: threw: ${String(error)}`);
          continue;
        }
        const printed = runInBash(args.command);
        const expected = expectedLines(entry.path, vars, OC_SESSION);
        if (printed !== expected) failures.push(`${entry.id}: printed ${JSON.stringify(printed)}`);
      }
      expect(failures).toEqual([]);
    },
    SWEEP_TIMEOUT_MS,
  );
});
