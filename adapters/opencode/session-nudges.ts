/**
 * session-plugin's two nudges under OpenCode (#2802). OpenCode never
 * evaluates a Claude Code hook manifest, so session-plugin's SessionStart
 * and Stop hooks are inert there without this module. The pi port
 * (pi/session-nudges.ts, #2661) is the reference shape; the harness-neutral
 * half lives in core/session-nudges.ts.
 *
 * - Spinup: `session.created` (root sessions only) runs
 *   `session-spinup-nudge.sh` unchanged with Claude Code's SessionStart
 *   stdin. Its `additionalContext` is queued for the session and pushed onto
 *   the system prompt of every request (`experimental.chat.system.transform`)
 *   until the session next settles, so a tool loop keeps it in view. A
 *   persisted message was rejected: `session.prompt` with `noReply` adds a
 *   user message, and the next step then runs with that message's model,
 *   which is the default model, not the one the user picked.
 * - End: on idle (`session.status` idle, or the deprecated `session.idle`;
 *   both are published by session/status.ts at v1.18.3 and v1.19.5) the
 *   gates of `session-end-nudge.sh` run over `client.session.messages`, and
 *   the offer goes out through `client.session.promptAsync` as a synthetic
 *   text part tagged in `metadata`, carrying the agent, model and variant of
 *   the latest user message so the extra turn runs where the user was.
 *
 * Event and message shapes: @opencode-ai/sdk 1.19.5 types and the upstream
 * publishers; not yet exercised in a live OpenCode session.
 */

import { execFile } from "node:child_process";
import { deriveSessionId } from "../core/claude-env.ts";
import {
  END_SKILL,
  END_SKILL_FILE,
  endNudgeReason,
  MIN_USER_TURNS,
  midFlow,
  type NudgeExec,
  probeCapture,
  RECENT_USER_WINDOW,
  runSpinupHook,
  WIND_DOWN_PATTERN,
} from "../core/session-nudges.ts";

export const END_NUDGE_TYPE = "session-end-nudge";
/** The text-part metadata key that marks the binding's own offer. */
export const NUDGE_METADATA_KEY = "sessionPluginNudge";

/** The slice of an OpenCode message (`{info, parts}`) the gates read. */
export interface OcMessage {
  info: {
    id?: string;
    role: string;
    agent?: string;
    model?: { providerID: string; modelID: string; variant?: string };
  };
  parts: Array<{
    type: string;
    text?: string;
    synthetic?: boolean;
    ignored?: boolean;
    metadata?: Record<string, unknown>;
    tool?: string;
    state?: { status?: string; input?: Record<string, unknown> };
    [key: string]: unknown;
  }>;
}

/** The slice of the plugin input's SDK client the binding calls. */
export interface NudgeClient {
  session: {
    messages(options: { path: { id: string } }): Promise<{ data?: OcMessage[] }>;
    get(options: {
      path: { id: string };
    }): Promise<{ data?: { id?: string; directory?: string; parentID?: string } }>;
    promptAsync(options: { path: { id: string }; body: Record<string, unknown> }): Promise<unknown>;
  };
}

export interface SessionNudgeOptions {
  client: NudgeClient;
  exec: NudgeExec;
  /** Marketplace checkout root (config.repoRoot). */
  repoRoot: () => string;
  /** false turns both nudges off (config.sessionNudges). */
  enabled: () => boolean;
  /** The plugin input's instance directory, used when a session names none. */
  directory: string;
  warn?: (message: string) => void;
}

/** child_process-backed NudgeExec for the live plugin. */
export const nodeExec: NudgeExec = (command, args, options) =>
  new Promise((resolve) => {
    execFile(
      command,
      args,
      { cwd: options.cwd, timeout: options.timeout, maxBuffer: 1024 * 1024 },
      (error, stdout) => {
        const code = error ? (typeof error.code === "number" ? error.code : 1) : 0;
        resolve({ stdout: String(stdout), code, killed: Boolean(error?.killed) });
      },
    );
  });

function genuineText(message: OcMessage): string {
  return message.parts
    .flatMap((part) =>
      part.type === "text" && typeof part.text === "string" && !part.synthetic && !part.ignored
        ? [part.text]
        : [],
    )
    .join("\n")
    .trim();
}

/**
 * User messages the person typed, in order. Text OpenCode generated
 * (`synthetic`: tool-call echoes, the binding's own offer) or excluded from
 * the request (`ignored`) is not a turn, and a message with no text left
 * (a file attachment alone) is not either.
 */
export function genuineUserMessages(messages: readonly OcMessage[]): OcMessage[] {
  return messages.filter(
    (message) => message.info.role === "user" && genuineText(message).length > 0,
  );
}

/** The text of the last assistant message that has any. */
export function lastAssistantText(messages: readonly OcMessage[]): string {
  for (let i = messages.length - 1; i >= 0; i--) {
    const message = messages[i] as OcMessage;
    if (message.info.role !== "assistant") continue;
    const texts = message.parts.flatMap((part) =>
      part.type === "text" && typeof part.text === "string" ? [part.text] : [],
    );
    if (texts.length > 0) return texts[texts.length - 1] as string;
  }
  return "";
}

/**
 * An end-of-session skill already loaded: a `read` of its SKILL.md (how the
 * model loads a skill search_skills returned) or OpenCode's own `skill` tool.
 */
export function endSkillLoaded(messages: readonly OcMessage[]): boolean {
  for (const message of messages) {
    if (message.info.role !== "assistant") continue;
    for (const part of message.parts) {
      if (part.type !== "tool") continue;
      const input = part.state?.input ?? {};
      if (part.tool === "read" && typeof input.filePath === "string") {
        if (END_SKILL_FILE.test(input.filePath)) return true;
      }
      if (part.tool === "skill" && typeof input.name === "string" && END_SKILL.test(input.name)) {
        return true;
      }
    }
  }
  return false;
}

/** The binding's own offer is persisted, so this holds across a restart. */
export function alreadyNudged(messages: readonly OcMessage[]): boolean {
  return messages.some((message) =>
    message.parts.some((part) => part.metadata?.[NUDGE_METADATA_KEY] === END_NUDGE_TYPE),
  );
}

interface PluginEvent {
  event: { type: string; properties?: unknown };
}

export function createSessionNudges(options: SessionNudgeOptions) {
  const warn = options.warn ?? ((message: string) => console.warn(message));
  /** Spinup context per session, and whether a request has carried it yet. */
  const spinup = new Map<string, { context: string; injected: boolean }>();
  const nudged = new Set<string>();
  const pending = new Set<string>();
  let rootSeen = false;

  async function onCreated(info: { id?: string; directory?: string; parentID?: string }) {
    if (typeof info.id !== "string" || info.parentID) return;
    // OpenCode has no start reason. The first root session this instance sees
    // is the launch; a later one is /new, which pi and Claude Code (/clear)
    // both report as a continuation the hook stays silent on.
    const source = rootSeen ? "clear" : "startup";
    rootSeen = true;
    const result = await runSpinupHook(
      options.exec,
      {
        source,
        sessionId: deriveSessionId(info.id),
        cwd: info.directory || options.directory,
      },
      options.repoRoot(),
    );
    if (result === undefined) return;
    if ("warning" in result) {
      warn(result.warning);
      return;
    }
    spinup.set(info.id, { context: result.context, injected: false });
  }

  async function runEndNudge(sessionID: string) {
    const { client } = options;
    const messages = (await client.session.messages({ path: { id: sessionID } })).data ?? [];
    if (alreadyNudged(messages) || endSkillLoaded(messages)) return;
    const users = genuineUserMessages(messages);
    if (users.length < MIN_USER_TURNS) return;
    const recent = users.slice(-RECENT_USER_WINDOW);
    if (!recent.some((message) => WIND_DOWN_PATTERN.test(genuineText(message)))) return;
    if (midFlow(lastAssistantText(messages))) return;
    const session = (await client.session.get({ path: { id: sessionID } })).data;
    if (session?.parentID) return;
    const capture = await probeCapture(
      options.exec,
      session?.directory || options.directory,
      options.repoRoot(),
    );
    if (!capture.surface) return;
    nudged.add(sessionID);
    const last = (users[users.length - 1] as OcMessage).info;
    const body: Record<string, unknown> = {
      parts: [
        {
          type: "text",
          text: endNudgeReason(capture.openTasks),
          synthetic: true,
          metadata: { [NUDGE_METADATA_KEY]: END_NUDGE_TYPE },
        },
      ],
    };
    if (last.agent) body.agent = last.agent;
    if (last.model) {
      body.model = { providerID: last.model.providerID, modelID: last.model.modelID };
      if (last.model.variant) body.variant = last.model.variant;
    }
    await client.session.promptAsync({ path: { id: sessionID }, body });
  }

  async function onIdle(sessionID: string) {
    if (spinup.get(sessionID)?.injected) spinup.delete(sessionID);
    // Both idle events fire for one settle; the synchronous pending check
    // keeps the second from running the gates again.
    if (nudged.has(sessionID) || pending.has(sessionID)) return;
    pending.add(sessionID);
    try {
      await runEndNudge(sessionID);
    } catch (error) {
      warn(`session-nudges: end nudge failed: ${String(error)}`);
    } finally {
      pending.delete(sessionID);
    }
  }

  return {
    /** The plugin's `event` hook. OpenCode does not await it. */
    async event({ event }: PluginEvent): Promise<void> {
      if (!options.enabled()) return;
      const properties = (event.properties ?? {}) as Record<string, unknown>;
      try {
        if (event.type === "session.created") {
          await onCreated((properties.info ?? {}) as { id?: string });
          return;
        }
        const sessionID = properties.sessionID;
        if (typeof sessionID !== "string") return;
        const settled =
          event.type === "session.idle" ||
          (event.type === "session.status" &&
            (properties.status as { type?: string } | undefined)?.type === "idle");
        if (settled) await onIdle(sessionID);
      } catch (error) {
        warn(`session-nudges: ${String(error)}`);
      }
    },

    /**
     * Push a session's queued spinup context onto a request's system prompt,
     * in place (Plugin.trigger does no copy-back).
     */
    injectSpinup(sessionID: string | undefined, system: string[]): void {
      if (sessionID === undefined) return;
      const entry = spinup.get(sessionID);
      if (entry === undefined) return;
      entry.injected = true;
      system.push(entry.context);
    },
  };
}
