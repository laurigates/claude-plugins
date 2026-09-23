/**
 * session-plugin nudges under pi (#2661). The spinup half runs the real
 * SessionStart hook script; the end half reimplements session-end-nudge.sh's
 * transcript gates over pi's session entries. `pi` is a stub that records
 * exec/sendMessage calls, except in the spinup integration test, which runs
 * the shipped hook through a real child process.
 */

import { describe, expect, test } from "bun:test";
import { execFile, execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { defaultConfig, parseConfigText } from "../pi/config.ts";
import skillDiscovery, { DEFAULT_REPO_ROOT } from "../pi/index.ts";
import {
  END_NUDGE_TYPE,
  END_TASK_CUE,
  endNudgeReason,
  genuineUserMessages,
  MIN_USER_TURNS,
  RECENT_USER_WINDOW,
  registerSessionNudges,
  SPINUP_HOOK,
  SPINUP_NUDGE_TYPE,
  sessionStartSource,
  WIND_DOWN_PATTERN,
} from "../pi/session-nudges.ts";

// --- stub pi --------------------------------------------------------------

interface ExecResult {
  stdout: string;
  stderr: string;
  code: number;
  killed: boolean;
}
interface ExecCall {
  command: string;
  args: string[];
  options?: { timeout?: number; cwd?: string };
}
type Handler = (event: unknown, ctx: unknown) => unknown;

const ok = (stdout = ""): ExecResult => ({ stdout, stderr: "", code: 0, killed: false });
const fail = (code = 1): ExecResult => ({ stdout: "", stderr: "boom", code, killed: false });

function stubPi(respond: (call: ExecCall) => ExecResult | Promise<ExecResult>) {
  const execCalls: ExecCall[] = [];
  const sent: Array<{ message: Record<string, unknown>; options?: Record<string, unknown> }> = [];
  const handlers = new Map<string, Handler[]>();
  const pi = {
    async exec(command: string, args: string[], options?: ExecCall["options"]) {
      const call = { command, args, options };
      execCalls.push(call);
      return respond(call);
    },
    sendMessage(message: Record<string, unknown>, options?: Record<string, unknown>) {
      sent.push({ message, options });
    },
    on(event: string, handler: Handler) {
      handlers.set(event, [...(handlers.get(event) ?? []), handler]);
    },
  };
  const fire = async (event: string, payload: unknown, ctx: unknown) => {
    for (const handler of handlers.get(event) ?? []) await handler(payload, ctx);
  };
  return { pi: pi as unknown as ExtensionAPI, execCalls, sent, handlers, fire };
}

function register(
  respond: (call: ExecCall) => ExecResult | Promise<ExecResult>,
  opts: { enabled?: boolean; repoRoot?: string } = {},
) {
  const stub = stubPi(respond);
  const warnings: string[] = [];
  registerSessionNudges(stub.pi, {
    repoRoot: () => opts.repoRoot ?? DEFAULT_REPO_ROOT,
    enabled: () => opts.enabled ?? true,
    warn: (message) => warnings.push(message),
  });
  return { ...stub, warnings };
}

// --- session entry fixtures ----------------------------------------------

type Entry = Record<string, unknown>;
const user = (text: string): Entry => ({
  type: "message",
  message: { role: "user", content: [{ type: "text", text }] },
});
const userString = (text: string): Entry => ({
  type: "message",
  message: { role: "user", content: text },
});
const skillExpansion = (name: string, args = ""): Entry =>
  user(
    `<skill name="${name}" location="/x/${name}/SKILL.md">\nReferences are relative to /x.\n\nbody\n</skill>${args ? `\n\n${args}` : ""}`,
  );
const assistantRead = (path: string): Entry => ({
  type: "message",
  message: {
    role: "assistant",
    content: [{ type: "toolCall", id: "c1", name: "read", arguments: { path } }],
  },
});
const toolResult = (text: string): Entry => ({
  type: "message",
  message: {
    role: "toolResult",
    toolCallId: "c1",
    toolName: "read",
    content: [{ type: "text", text }],
  },
});
const nudgeEntry: Entry = {
  type: "custom_message",
  customType: END_NUDGE_TYPE,
  content: "earlier nudge",
  display: true,
};

/** Five ordinary turns, then a wind-down message: six genuine user turns. */
const WINDING_DOWN: Entry[] = [
  user("fix the parser"),
  userString("now add a test"),
  user("run it"),
  user("commit that"),
  user("push it"),
  user("ok that's it for today, thanks"),
];

function ctxOf(entries: Entry[], cwd = "/work", sessionId = "pi-session-1") {
  return {
    cwd,
    sessionManager: {
      getSessionId: () => sessionId,
      getEntries: () => entries,
      getBranch: () => entries,
    },
  };
}

const SUMMARY = (fields: Record<string, string>) =>
  [
    "=== SESSION SURVEY SUMMARY ===",
    ...Object.entries(fields).map(([k, v]) => `${k}=${v}`),
    "STATUS=OK",
    "=== END SESSION SURVEY SUMMARY ===",
  ].join("\n");

/** exec responder: taskwarrior present or not, and the survey's summary. */
function endResponder(opts: { task: boolean; summary?: Record<string, string> }) {
  return (call: ExecCall): ExecResult => {
    if (call.command === "bash" && call.args[0] === "-c" && call.args[1]?.includes("command -v")) {
      return opts.task ? ok("/usr/bin/task\n") : fail(1);
    }
    if (call.command === "bash" && call.args[0]?.endsWith("session-survey.sh")) {
      return ok(SUMMARY(opts.summary ?? { OPEN_TASKS: "0", RECENT_TASK_COUNT: "0" }));
    }
    if (call.command === "git") return fail(128);
    throw new Error(`unexpected exec: ${call.command} ${call.args.join(" ")}`);
  };
}

// --- spinup ---------------------------------------------------------------

describe("spinup nudge (session_start)", () => {
  const CONTEXT = "Open threads detected at session start (uncommitted changes).";
  const hookOutput = JSON.stringify({
    hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: CONTEXT },
  });

  test("runs the shipped hook with the SessionStart payload and queues its context", async () => {
    const { execCalls, sent, fire } = register(() => ok(hookOutput));
    await fire("session_start", { type: "session_start", reason: "startup" }, ctxOf([], "/work"));

    expect(execCalls).toHaveLength(1);
    const call = execCalls[0] as ExecCall;
    expect(call.command).toBe("bash");
    expect(call.args[0]).toBe("-c");
    const hookPath = call.args[3] as string;
    expect(hookPath).toBe(join(DEFAULT_REPO_ROOT, ...SPINUP_HOOK));
    expect(JSON.parse(call.args[4] as string)).toEqual({
      hook_event_name: "SessionStart",
      source: "startup",
      session_id: "pi-session-1",
      cwd: "/work",
    });
    expect(call.options?.timeout).toBe(15_000);

    expect(sent).toEqual([
      {
        message: { customType: SPINUP_NUDGE_TYPE, content: CONTEXT, display: true },
        options: { deliverAs: "nextTurn" },
      },
    ]);
  });

  test("a hook that prints nothing sends nothing", async () => {
    const { sent, fire } = register(() => ok(""));
    await fire("session_start", { reason: "startup" }, ctxOf([]));
    expect(sent).toEqual([]);
  });

  test("a failing or timed-out hook sends nothing and warns", async () => {
    for (const result of [fail(2), { ...ok(hookOutput), killed: true }]) {
      const { sent, warnings, fire } = register(() => result);
      await fire("session_start", { reason: "startup" }, ctxOf([]));
      expect(sent).toEqual([]);
      expect(warnings).toHaveLength(1);
      expect(warnings[0]).toContain("session-spinup-nudge.sh");
    }
  });

  test("an exec that throws does not escape the handler", async () => {
    const { sent, warnings, fire } = register(() => {
      throw new Error("spawn bash ENOENT");
    });
    await fire("session_start", { reason: "resume" }, ctxOf([]));
    expect(sent).toEqual([]);
    expect(warnings[0]).toContain("spawn bash ENOENT");
  });

  test("disabled: no exec", async () => {
    const { execCalls, fire } = register(() => ok(hookOutput), { enabled: false });
    await fire("session_start", { reason: "startup" }, ctxOf([]));
    expect(execCalls).toEqual([]);
  });

  test("a checkout without session-plugin: no exec", async () => {
    const { execCalls, fire } = register(() => ok(hookOutput), {
      repoRoot: mkdtempSync(join(tmpdir(), "no-session-plugin-")),
    });
    await fire("session_start", { reason: "startup" }, ctxOf([]));
    expect(execCalls).toEqual([]);
  });

  test("pi reasons map onto the sources the hook gates on", () => {
    expect(sessionStartSource("startup")).toBe("startup");
    expect(sessionStartSource("resume")).toBe("resume");
    expect(sessionStartSource("fork")).toBe("resume");
    expect(sessionStartSource("new")).toBe("clear");
    expect(sessionStartSource("reload")).toBe("reload");
  });

  test("integration: the real hook, fed through the exec stdin bridge, nudges once per session", async () => {
    const home = mkdtempSync(join(tmpdir(), "pi-nudge-home-"));
    const repo = mkdtempSync(join(tmpdir(), "pi-nudge-repo-"));
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
    const env = {
      ...process.env,
      HOME: home,
      SESSION_NUDGE_TASK_BIN: "/nonexistent/task",
      SESSION_NUDGE_GH_BIN: "/nonexistent/gh",
    };
    const realExec = (call: ExecCall) =>
      new Promise<ExecResult>((resolve) => {
        execFile(
          call.command,
          call.args,
          { cwd: call.options?.cwd, timeout: call.options?.timeout, env },
          (error, stdout, stderr) => {
            const code = error ? (typeof error.code === "number" ? error.code : 1) : 0;
            resolve({ stdout, stderr, code, killed: Boolean(error?.killed) });
          },
        );
      });
    const { sent, warnings, fire } = register(realExec);
    const ctx = ctxOf([], repo, "pi-integration-session");

    await fire("session_start", { reason: "startup" }, ctx);
    expect(warnings).toEqual([]);
    expect(sent).toHaveLength(1);
    const content = (sent[0]?.message as { content: string }).content;
    expect(content).toContain("uncommitted changes");
    expect(content).toContain("session-plugin:session-spinup");

    // The hook's own once-per-session state file suppresses a second nudge.
    await fire("session_start", { reason: "resume" }, ctx);
    expect(sent).toHaveLength(1);
  }, 30_000);
});

// --- end ------------------------------------------------------------------

describe("end nudge (agent_settled)", () => {
  test("wind-down after six genuine turns: offers session-end and triggers a turn", async () => {
    const { sent, fire } = register(endResponder({ task: true }));
    await fire("agent_settled", { type: "agent_settled" }, ctxOf(WINDING_DOWN));
    expect(sent).toEqual([
      {
        message: { customType: END_NUDGE_TYPE, content: endNudgeReason(false), display: true },
        options: { triggerTurn: true, deliverAs: "followUp" },
      },
    ]);
    expect(endNudgeReason(false)).toContain("session-plugin:session-end");
  });

  test("open tasks add the taskwarrior cue; the survey runs against the session cwd", async () => {
    const { execCalls, sent, fire } = register(
      endResponder({ task: true, summary: { OPEN_TASKS: "2", RECENT_TASK_COUNT: "0" } }),
    );
    await fire("agent_settled", {}, ctxOf(WINDING_DOWN, "/proj"));
    expect((sent[0]?.message as { content: string }).content).toBe(endNudgeReason(true));
    expect(endNudgeReason(true)).toContain(END_TASK_CUE);
    const survey = execCalls.find((c) => c.args[0]?.endsWith("session-survey.sh"));
    expect(survey?.args.slice(1)).toEqual(["--summary", "--project-dir", "/proj"]);
    expect(survey?.options?.timeout).toBe(10_000);
  });

  test("a low-confidence zero is not a clean queue: the cue stays", async () => {
    const { sent, fire } = register(
      endResponder({
        task: true,
        summary: {
          OPEN_TASKS: "0",
          RECENT_TASK_COUNT: "0",
          TASK_SCOPE: "exact",
          PROJECT_CONFIDENCE: "low",
        },
      }),
    );
    await fire("agent_settled", {}, ctxOf(WINDING_DOWN));
    expect((sent[0]?.message as { content: string }).content).toBe(endNudgeReason(true));
  });

  test("fewer than six genuine turns: silent, nothing executed", async () => {
    const { execCalls, sent, fire } = register(endResponder({ task: true }));
    await fire("agent_settled", {}, ctxOf(WINDING_DOWN.slice(1)));
    expect(sent).toEqual([]);
    expect(execCalls).toEqual([]);
  });

  test("skill expansions and tool results do not count as user turns", async () => {
    const entries = [
      skillExpansion("git-commit", "fix the parser"),
      toolResult("that's it for today"),
      ...WINDING_DOWN.slice(1),
    ];
    expect(genuineUserMessages(entries)).toHaveLength(5);
    const { sent, fire } = register(endResponder({ task: true }));
    await fire("agent_settled", {}, ctxOf(entries));
    expect(sent).toEqual([]);
  });

  test("no wind-down phrase in the last three genuine messages: silent", async () => {
    const early = [
      user("that's it for today"),
      user("actually one more"),
      ...WINDING_DOWN.slice(1, 5),
      user("and another"),
    ];
    const { execCalls, sent, fire } = register(endResponder({ task: true }));
    await fire("agent_settled", {}, ctxOf(early));
    expect(sent).toEqual([]);
    expect(execCalls).toEqual([]);
  });

  test("an end-of-session skill already driving the flow: silent", async () => {
    for (const marker of [
      skillExpansion("session-end"),
      skillExpansion("session-wrap"),
      assistantRead("/repo/session-plugin/skills/session-distill/SKILL.md"),
    ]) {
      const { sent, fire } = register(endResponder({ task: true }));
      await fire("agent_settled", {}, ctxOf([...WINDING_DOWN, marker]));
      expect(sent).toEqual([]);
    }
  });

  test("at most once per session: a persisted nudge or a second settle stays silent", async () => {
    const persisted = register(endResponder({ task: true }));
    await persisted.fire("agent_settled", {}, ctxOf([...WINDING_DOWN, nudgeEntry]));
    expect(persisted.sent).toEqual([]);

    const repeat = register(endResponder({ task: true }));
    await repeat.fire("agent_settled", {}, ctxOf(WINDING_DOWN));
    await repeat.fire("agent_settled", {}, ctxOf(WINDING_DOWN));
    expect(repeat.sent).toHaveLength(1);
  });

  test("no taskwarrior and nothing distillable in the repo: silent", async () => {
    const bare = mkdtempSync(join(tmpdir(), "pi-nudge-bare-"));
    const { sent, fire } = register(endResponder({ task: false }));
    await fire("agent_settled", {}, ctxOf(WINDING_DOWN, bare));
    expect(sent).toEqual([]);
  });

  test("no taskwarrior but a justfile: nudges without the task cue", async () => {
    const withJustfile = mkdtempSync(join(tmpdir(), "pi-nudge-just-"));
    writeFileSync(join(withJustfile, "justfile"), "default:\n");
    const { sent, fire } = register(endResponder({ task: false }));
    await fire("agent_settled", {}, ctxOf(WINDING_DOWN, withJustfile));
    expect((sent[0]?.message as { content: string }).content).toBe(endNudgeReason(false));
  });

  test("disabled: silent", async () => {
    const { execCalls, sent, fire } = register(endResponder({ task: true }), { enabled: false });
    await fire("agent_settled", {}, ctxOf(WINDING_DOWN));
    expect(sent).toEqual([]);
    expect(execCalls).toEqual([]);
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
    expect(WIND_DOWN_PATTERN.source).toBe(capture(/grep -Eiq '([^']+)'/));
    expect(WIND_DOWN_PATTERN.flags).toContain("i");
  });

  test("same turn threshold and recent window", () => {
    expect(MIN_USER_TURNS).toBe(Number(capture(/"\$user_turns" -lt (\d+) \]/)));
    expect(RECENT_USER_WINDOW).toBe(Number(capture(/recent=\$\(.*\| tail -(\d+)\)/)));
  });

  test("same offer text, with and without the taskwarrior cue", () => {
    const reason = capture(/^reason="(.*)"$/m);
    const cue = capture(/^\s*task_cue="(.*)"$/m);
    expect(endNudgeReason(false)).toBe(reason.replace("${task_cue}", ""));
    expect(endNudgeReason(true)).toBe(reason.replace("${task_cue}", cue));
  });
});

// --- wiring ---------------------------------------------------------------

describe("extension factory wiring", () => {
  test("registers the end nudge on agent_settled and a second session_start handler", async () => {
    const { pi, handlers } = stubPi(() => ok());
    const registerTool = () => {};
    await skillDiscovery(Object.assign(pi, { registerTool }));
    expect(handlers.get("agent_settled")).toHaveLength(1);
    expect(handlers.get("session_start")).toHaveLength(2);
  });

  test("sessionNudges config key: boolean, default true", () => {
    expect(defaultConfig("/r").sessionNudges).toBe(true);
    expect(parseConfigText('{"sessionNudges": false}', "p").partial.sessionNudges).toBe(false);
    const bad = parseConfigText('{"sessionNudges": "no"}', "p");
    expect(bad.partial.sessionNudges).toBeUndefined();
    expect(bad.warnings[0]).toContain('"sessionNudges" is not a boolean');
  });
});
