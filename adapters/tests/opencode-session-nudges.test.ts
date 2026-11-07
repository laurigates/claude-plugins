/**
 * session-plugin nudges under OpenCode (#2802). The spinup half runs the real
 * SessionStart hook on `session.created` and injects its context into the
 * session's system prompt until the turn settles; the end half applies
 * session-end-nudge.sh's gates to OpenCode's session messages on idle and
 * sends the offer with `session.promptAsync`. `client` and `exec` are stubs
 * that record calls, except in the spinup integration test, which runs the
 * shipped hook through a real child process.
 *
 * Event and message shapes: @opencode-ai/sdk 1.19.5 types (EventSessionCreated,
 * EventSessionIdle, EventSessionStatus, UserMessage, ToolPart) and the upstream
 * publishers in session/status.ts and session/session.ts at v1.18.3 and v1.19.5.
 */

// biome-ignore-all lint/suspicious/noTemplateCurlyInString: the parity block names the shell hook's ${task_cue} literally

import { describe, expect, test } from "bun:test";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { PluginInput } from "@opencode-ai/plugin";
import { deriveSessionId } from "../core/claude-env.ts";
import {
  END_TASK_CUE,
  endNudgeReason,
  MID_FLOW_PATTERN,
  MIN_USER_TURNS,
  type NudgeExecResult,
  RECENT_USER_WINDOW,
  SPINUP_HOOK,
  WIND_DOWN_PATTERN,
} from "../core/session-nudges.ts";
import { DEFAULT_REPO_ROOT, resolveOptions } from "../opencode/config.ts";
import { SkillDiscoveryPlugin } from "../opencode/index.ts";
import {
  createSessionNudges,
  END_NUDGE_TYPE,
  NUDGE_METADATA_KEY,
  type NudgeClient,
  nodeExec,
  type OcMessage,
} from "../opencode/session-nudges.ts";

// --- stubs ----------------------------------------------------------------

interface ExecCall {
  command: string;
  args: string[];
  options: { timeout: number; cwd?: string };
}
type Prompt = { path: { id: string }; body: Record<string, unknown> };

const ok = (stdout = ""): NudgeExecResult => ({ stdout, code: 0, killed: false });
const fail = (code = 1): NudgeExecResult => ({ stdout: "", code, killed: false });

function stubClient(
  messages: OcMessage[],
  session: { directory?: string; parentID?: string } = {},
) {
  const prompts: Prompt[] = [];
  const calls: string[] = [];
  const client: NudgeClient = {
    session: {
      async messages(options) {
        calls.push(`messages ${options.path.id}`);
        return { data: messages };
      },
      async get(options) {
        calls.push(`get ${options.path.id}`);
        return { data: { id: options.path.id, ...session } };
      },
      async promptAsync(options) {
        calls.push(`promptAsync ${options.path.id}`);
        prompts.push(options as Prompt);
        return {};
      },
    },
  };
  return { client, prompts, calls };
}

function setup(
  respond: (call: ExecCall) => NudgeExecResult | Promise<NudgeExecResult>,
  opts: {
    messages?: OcMessage[];
    session?: { directory?: string; parentID?: string };
    enabled?: boolean;
    repoRoot?: string;
    directory?: string;
    client?: NudgeClient;
  } = {},
) {
  const execCalls: ExecCall[] = [];
  const warnings: string[] = [];
  const stub = stubClient(opts.messages ?? [], opts.session);
  const nudges = createSessionNudges({
    client: opts.client ?? stub.client,
    exec: async (command, args, options) => {
      const call = { command, args, options };
      execCalls.push(call);
      return respond(call);
    },
    repoRoot: () => opts.repoRoot ?? DEFAULT_REPO_ROOT,
    enabled: () => opts.enabled ?? true,
    directory: opts.directory ?? "/work",
    warn: (message) => warnings.push(message),
  });
  return { nudges, execCalls, warnings, ...stub };
}

// --- event + message fixtures ----------------------------------------------

const created = (id: string, directory = "/work", parentID?: string) => ({
  event: {
    type: "session.created",
    properties: {
      sessionID: id,
      info: {
        id,
        projectID: "prj",
        directory,
        title: "t",
        version: "1",
        time: { created: 1, updated: 1 },
        ...(parentID ? { parentID } : {}),
      },
    },
  },
});
const idle = (id: string) => ({ event: { type: "session.idle", properties: { sessionID: id } } });
const statusIdle = (id: string) => ({
  event: { type: "session.status", properties: { sessionID: id, status: { type: "idle" } } },
});
const statusBusy = (id: string) => ({
  event: { type: "session.status", properties: { sessionID: id, status: { type: "busy" } } },
});

const MODEL = { providerID: "anthropic", modelID: "claude-x" };
let seq = 0;
const user = (text: string, extra: Record<string, unknown> = {}): OcMessage => ({
  info: { id: `msg_u${++seq}`, role: "user", agent: "build", model: MODEL },
  parts: [{ type: "text", text, ...extra }],
});
const assistant = (text: string, parts: OcMessage["parts"] = []): OcMessage => ({
  info: { id: `msg_a${++seq}`, role: "assistant" },
  parts: [...parts, ...(text ? [{ type: "text", text }] : [])],
});
const readTool = (filePath: string) => ({
  type: "tool",
  tool: "read",
  callID: "c1",
  state: { status: "completed", input: { filePath } },
});

/** Five ordinary turns, then a wind-down message: six genuine user turns. */
function windingDown(lastAssistant = "Pushed."): OcMessage[] {
  return [
    user("fix the parser"),
    assistant("done"),
    user("now add a test"),
    user("run it"),
    user("commit that"),
    user("push it"),
    assistant(lastAssistant),
    user("ok that's it for today, thanks"),
  ];
}

const SUMMARY = (fields: Record<string, string>) =>
  `=== SESSION SURVEY SUMMARY ===\n${Object.entries(fields)
    .map(([k, v]) => `${k}=${v}`)
    .join("\n")}\nSTATUS=OK\n`;

/** No taskwarrior; `git rev-parse` points at a repo that has a justfile. */
function repoWithJustfile(): string {
  const dir = mkdtempSync(join(tmpdir(), "oc-nudge-surface-"));
  writeFileSync(join(dir, "justfile"), "default:\n\techo hi\n");
  return dir;
}
const noTaskButRepo = (root: string) => (call: ExecCall) => {
  if (call.command === "bash" && call.args[1] === "command -v task") return fail();
  if (call.command === "git") return ok(`${root}\n`);
  return fail();
};

// --- spinup ---------------------------------------------------------------

describe("spinup nudge on session.created", () => {
  const CONTEXT = "Open threads detected at session start (uncommitted changes).";
  const hookOutput = ok(
    JSON.stringify({
      hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: CONTEXT },
    }),
  );

  test("runs the shipped hook with the SessionStart payload and injects its context until the turn settles", async () => {
    const { nudges, execCalls } = setup(() => hookOutput);
    await nudges.event(created("ses_one", "/proj"));
    expect(execCalls).toHaveLength(1);
    const call = execCalls[0] as ExecCall;
    expect(call.args.slice(0, 3)).toEqual(["-c", 'bash "$1" <<<"$2"', "session-nudge"]);
    expect(call.args[3]).toBe(join(DEFAULT_REPO_ROOT, ...SPINUP_HOOK));
    expect(JSON.parse(call.args[4] as string)).toEqual({
      hook_event_name: "SessionStart",
      source: "startup",
      session_id: deriveSessionId("ses_one"),
      cwd: "/proj",
    });
    expect(call.options).toEqual({ timeout: 15_000, cwd: "/proj" });

    // Every request of the next turn carries it (tool loops are several requests).
    const first = ["base"];
    nudges.injectSpinup("ses_one", first);
    expect(first).toEqual(["base", CONTEXT]);
    const second = ["base"];
    nudges.injectSpinup("ses_one", second);
    expect(second).toEqual(["base", CONTEXT]);
    // Another session never sees it.
    const other = ["base"];
    nudges.injectSpinup("ses_two", other);
    expect(other).toEqual(["base"]);
    // The turn settles: gone.
    await nudges.event(idle("ses_one"));
    const after = ["base"];
    nudges.injectSpinup("ses_one", after);
    expect(after).toEqual(["base"]);
  });

  test("idle before the context was ever injected keeps it for the next turn", async () => {
    const { nudges } = setup(() => hookOutput);
    await nudges.event(created("ses_one"));
    await nudges.event(statusIdle("ses_one"));
    const system: string[] = [];
    nudges.injectSpinup("ses_one", system);
    expect(system).toEqual([CONTEXT]);
  });

  test("the first root session is startup, later ones are /new (clear), and the hook decides", async () => {
    const { nudges, execCalls } = setup(() => ok());
    await nudges.event(created("ses_a"));
    await nudges.event(created("ses_b"));
    const sources = execCalls.map((c) => JSON.parse(c.args[4] as string).source);
    expect(sources).toEqual(["startup", "clear"]);
  });

  test("a subagent session (parentID) runs nothing", async () => {
    const { nudges, execCalls } = setup(() => hookOutput);
    await nudges.event(created("ses_child", "/work", "ses_parent"));
    expect(execCalls).toHaveLength(0);
  });

  test("a session without a directory falls back to the plugin's directory", async () => {
    const { nudges, execCalls } = setup(() => ok(), { directory: "/instance" });
    await nudges.event(created("ses_one", ""));
    expect(execCalls[0]?.options.cwd).toBe("/instance");
  });

  test("a failing hook injects nothing and warns", async () => {
    const { nudges, warnings } = setup(() => fail(3));
    await nudges.event(created("ses_one"));
    const system: string[] = [];
    nudges.injectSpinup("ses_one", system);
    expect(system).toEqual([]);
    expect(warnings[0]).toContain("exited 3");
  });

  test("disabled: no exec", async () => {
    const { nudges, execCalls } = setup(() => hookOutput, { enabled: false });
    await nudges.event(created("ses_one"));
    expect(execCalls).toHaveLength(0);
  });

  test("integration: the real hook, fed through nodeExec, nudges once per session", async () => {
    const home = mkdtempSync(join(tmpdir(), "oc-nudge-home-"));
    const repo = mkdtempSync(join(tmpdir(), "oc-nudge-repo-"));
    execFileSync("git", ["-C", repo, "init", "-q"]);
    execFileSync("git", [
      "-C",
      repo,
      "-c",
      "user.email=t@t",
      "-c",
      "user.name=t",
      "commit",
      "-q",
      "--allow-empty",
      "-m",
      "init",
    ]);
    writeFileSync(join(repo, "wip.txt"), "wip\n");
    const saved = {
      HOME: process.env.HOME,
      task: process.env.SESSION_NUDGE_TASK_BIN,
      gh: process.env.SESSION_NUDGE_GH_BIN,
    };
    process.env.HOME = home;
    process.env.SESSION_NUDGE_TASK_BIN = "/nonexistent/task";
    process.env.SESSION_NUDGE_GH_BIN = "/nonexistent/gh";
    try {
      const warnings: string[] = [];
      const fresh = () =>
        createSessionNudges({
          client: stubClient([]).client,
          exec: nodeExec,
          repoRoot: () => DEFAULT_REPO_ROOT,
          enabled: () => true,
          directory: repo,
          warn: (m) => warnings.push(m),
        });
      const nudges = fresh();
      await nudges.event(created("ses_integration", repo));
      expect(warnings).toEqual([]);
      const system: string[] = [];
      nudges.injectSpinup("ses_integration", system);
      expect(system).toHaveLength(1);
      expect(system[0]).toContain("uncommitted changes");
      expect(system[0]).toContain("session-plugin:session-spinup");

      // The hook's own once-per-session state file suppresses a second nudge,
      // even from a fresh instance whose first session reads as startup.
      const restarted = fresh();
      await restarted.event(created("ses_integration", repo));
      const again: string[] = [];
      restarted.injectSpinup("ses_integration", again);
      expect(again).toEqual([]);
      expect(warnings).toEqual([]);
    } finally {
      for (const [key, env] of [
        ["HOME", saved.HOME],
        ["SESSION_NUDGE_TASK_BIN", saved.task],
        ["SESSION_NUDGE_GH_BIN", saved.gh],
      ] as const) {
        if (env === undefined) delete process.env[key];
        else process.env[key] = env;
      }
    }
  }, 30_000);
});

// --- end ------------------------------------------------------------------

describe("end nudge on idle", () => {
  test("wind-down after six genuine turns: offers session-end with the user's agent and model", async () => {
    const root = repoWithJustfile();
    const { nudges, prompts, execCalls } = setup(noTaskButRepo(root), {
      messages: windingDown(),
      session: { directory: root },
    });
    await nudges.event(idle("ses_one"));
    expect(prompts).toHaveLength(1);
    const prompt = prompts[0] as Prompt;
    expect(prompt.path.id).toBe("ses_one");
    expect(prompt.body.agent).toBe("build");
    expect(prompt.body.model).toEqual(MODEL);
    expect(prompt.body.noReply).toBeUndefined();
    expect(prompt.body.parts).toEqual([
      {
        type: "text",
        text: endNudgeReason(false),
        synthetic: true,
        metadata: { [NUDGE_METADATA_KEY]: END_NUDGE_TYPE },
      },
    ]);
    // The capture probe ran against the session's own directory.
    expect(execCalls.find((c) => c.command === "git")?.args).toEqual([
      "-C",
      root,
      "rev-parse",
      "--show-toplevel",
    ]);
  });

  test("the user's model variant rides along", async () => {
    const root = repoWithJustfile();
    const messages = windingDown();
    const last = messages[messages.length - 1] as OcMessage;
    last.info.model = { ...MODEL, variant: "high" };
    const { nudges, prompts } = setup(noTaskButRepo(root), {
      messages,
      session: { directory: root },
    });
    await nudges.event(idle("ses_one"));
    expect(prompts[0]?.body.model).toEqual(MODEL);
    expect(prompts[0]?.body.variant).toBe("high");
  });

  test("open tasks add the taskwarrior cue; the survey runs in the session directory", async () => {
    const { nudges, prompts, execCalls } = setup(
      (call) =>
        call.args[1] === "command -v task" ? ok("/usr/bin/task") : ok(SUMMARY({ OPEN_TASKS: "2" })),
      { messages: windingDown(), session: { directory: "/proj" } },
    );
    await nudges.event(idle("ses_one"));
    expect(prompts).toHaveLength(1);
    const parts = (prompts[0] as Prompt).body.parts as { text: string }[];
    expect(parts[0]?.text).toBe(endNudgeReason(true));
    const survey = execCalls.find((c) => c.args.includes("--summary"));
    expect(survey?.options.cwd).toBe("/proj");
    expect(survey?.args).toContain("/proj");
  });

  test("fewer than six genuine turns: silent, nothing executed or fetched beyond the messages", async () => {
    const { nudges, prompts, execCalls, calls } = setup(() => ok(), {
      messages: windingDown().slice(2),
    });
    await nudges.event(idle("ses_one"));
    expect(prompts).toHaveLength(0);
    expect(execCalls).toHaveLength(0);
    expect(calls).toEqual(["messages ses_one"]);
  });

  test("synthetic and ignored text, and file-only messages, are not user turns", async () => {
    const root = repoWithJustfile();
    const messages: OcMessage[] = [
      user("one"),
      user("two"),
      user("three"),
      user("four"),
      user("Called the Read tool with the following input: {}", { synthetic: true }),
      user("hidden", { ignored: true }),
      {
        info: { id: "msg_f", role: "user", agent: "build", model: MODEL },
        parts: [{ type: "file", url: "x" }],
      },
      user("ok that's it for today"),
    ];
    const { nudges, prompts } = setup(noTaskButRepo(root), {
      messages,
      session: { directory: root },
    });
    await nudges.event(idle("ses_one"));
    expect(prompts).toHaveLength(0);
  });

  test("wind-down phrase only before the latest genuine message: silent (#3180)", async () => {
    const messages = [...windingDown(), user("actually, one more thing: rename the flag")];
    const { nudges, prompts } = setup(() => ok(), { messages });
    await nudges.event(idle("ses_one"));
    expect(prompts).toHaveLength(0);
  });

  test("assistant mid-flow (question or next-step proposal): silent (#3180)", async () => {
    for (const text of [
      "Done. Should I also update the docs?",
      "Pushed.\n\nNext steps: open the PR.",
      "Want me to open the PR? **",
    ]) {
      const { nudges, prompts } = setup(noTaskButRepo(repoWithJustfile()), {
        messages: windingDown(text),
      });
      await nudges.event(idle("ses_one"));
      expect(prompts).toHaveLength(0);
    }
  });

  test("an end-of-session skill already loaded (read of its SKILL.md, or the skill tool): silent", async () => {
    const viaRead = [...windingDown()];
    viaRead.splice(
      2,
      0,
      assistant("", [readTool("/x/session-plugin/skills/session-end/SKILL.md")]),
    );
    const viaSkill = [...windingDown()];
    viaSkill.splice(
      2,
      0,
      assistant("", [
        {
          type: "tool",
          tool: "skill",
          callID: "c",
          state: { status: "completed", input: { name: "session-plugin:session-wrap" } },
        },
      ]),
    );
    for (const messages of [viaRead, viaSkill]) {
      const { nudges, prompts } = setup(noTaskButRepo(repoWithJustfile()), { messages });
      await nudges.event(idle("ses_one"));
      expect(prompts).toHaveLength(0);
    }
  });

  test("at most once per session: a persisted nudge or a second idle stays silent", async () => {
    const persisted = [
      ...windingDown(),
      user(endNudgeReason(false), {
        synthetic: true,
        metadata: { [NUDGE_METADATA_KEY]: END_NUDGE_TYPE },
      }),
      assistant("Sure."),
      user("that's it for today"),
    ];
    const first = setup(noTaskButRepo(repoWithJustfile()), { messages: persisted });
    await first.nudges.event(idle("ses_one"));
    expect(first.prompts).toHaveLength(0);

    const root = repoWithJustfile();
    const second = setup(noTaskButRepo(root), {
      messages: windingDown(),
      session: { directory: root },
    });
    await second.nudges.event(idle("ses_one"));
    await second.nudges.event(idle("ses_one"));
    expect(second.prompts).toHaveLength(1);
  });

  test("session.idle and session.status idle for one settle send one offer", async () => {
    const root = repoWithJustfile();
    const { nudges, prompts } = setup(noTaskButRepo(root), {
      messages: windingDown(),
      session: { directory: root },
    });
    await Promise.all([nudges.event(statusIdle("ses_one")), nudges.event(idle("ses_one"))]);
    expect(prompts).toHaveLength(1);
  });

  test("a busy status is not a settle", async () => {
    const { nudges, calls } = setup(() => ok(), { messages: windingDown() });
    await nudges.event(statusBusy("ses_one"));
    expect(calls).toEqual([]);
  });

  test("a subagent session: silent", async () => {
    const { nudges, prompts } = setup(noTaskButRepo(repoWithJustfile()), {
      messages: windingDown(),
      session: { parentID: "ses_parent" },
    });
    await nudges.event(idle("ses_child"));
    expect(prompts).toHaveLength(0);
  });

  test("no taskwarrior and nothing distillable in the repo: silent", async () => {
    const bare = mkdtempSync(join(tmpdir(), "oc-nudge-bare-"));
    mkdirSync(join(bare, "src"));
    const { nudges, prompts } = setup(noTaskButRepo(bare), { messages: windingDown() });
    await nudges.event(idle("ses_one"));
    expect(prompts).toHaveLength(0);
  });

  test("a client error warns and never escapes the handler", async () => {
    const broken: NudgeClient = {
      session: {
        messages: async () => {
          throw new Error("server gone");
        },
        get: async () => ({ data: undefined }),
        promptAsync: async () => ({}),
      },
    };
    const { nudges, warnings } = setup(() => ok(), { client: broken });
    await nudges.event(idle("ses_one"));
    expect(warnings[0]).toContain("server gone");
  });

  test("disabled: silent, no fetch", async () => {
    const { nudges, calls } = setup(() => ok(), { messages: windingDown(), enabled: false });
    await nudges.event(idle("ses_one"));
    expect(calls).toEqual([]);
  });
});

// --- parity with the Claude Code hook -----------------------------------

describe("parity with session-end-nudge.sh", () => {
  const script = readFileSync(
    join(DEFAULT_REPO_ROOT, "session-plugin", "hooks", "session-end-nudge.sh"),
    "utf8",
  );
  const capture = (re: RegExp): string => {
    const match = script.match(re);
    expect(match).not.toBeNull();
    return (match as RegExpMatchArray)[1] as string;
  };

  test("same wind-down phrases", () => {
    expect(WIND_DOWN_PATTERN.source).toBe(capture(/grep -Eiq '([^']+)' <<<"\$recent"/));
  });

  test("same mid-flow phrases", () => {
    expect(MID_FLOW_PATTERN.source).toBe(capture(/grep -Eiq '([^']+)' <<<"\$tail_text"/));
    expect(MID_FLOW_PATTERN.flags).toContain("i");
  });

  test("same turn threshold and recent window", () => {
    expect(MIN_USER_TURNS).toBe(Number(capture(/"\$user_turns" -lt (\d+) \]/)));
    expect(RECENT_USER_WINDOW).toBe(Number(capture(/recent=\$\(.*\| tail -(\d+)\)/)));
  });

  test("same offer text, with and without the taskwarrior cue", () => {
    const reason = capture(/^reason="(.*)"$/m);
    const cue = capture(/^\s+task_cue="(.+)"$/m);
    expect(END_TASK_CUE).toBe(cue);
    expect(endNudgeReason(false)).toBe(reason.replace("${task_cue}", ""));
    expect(endNudgeReason(true)).toBe(reason.replace("${task_cue}", cue));
  });
});

// --- wiring ---------------------------------------------------------------

describe("plugin wiring", () => {
  test("SkillDiscoveryPlugin registers the event hook", async () => {
    const hooks = await SkillDiscoveryPlugin(
      {
        serverUrl: new URL("http://127.0.0.1:1"),
        directory: "/work",
        worktree: "/work",
        client: stubClient([]).client,
      } as unknown as PluginInput,
      { repoRoot: "/nonexistent", sessionNudges: false },
    );
    expect(typeof hooks.event).toBe("function");
  });

  test("sessionNudges option: boolean, default true", () => {
    expect(resolveOptions({}).config.sessionNudges).toBe(true);
    const off = resolveOptions({ sessionNudges: false });
    expect(off.config.sessionNudges).toBe(false);
    expect(off.warnings).toEqual([]);
    const bad = resolveOptions({ sessionNudges: "no" });
    expect(bad.config.sessionNudges).toBe(true);
    expect(bad.warnings[0]).toContain('"sessionNudges"');
  });
});
