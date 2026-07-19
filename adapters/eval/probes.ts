/**
 * InvocationProbe seam (DESIGN §5.4).
 *
 * Only RetrievalProxyProbe is implemented — the live-quant probe (pi headless
 * against the mlx quant, OpenCode equivalent) is a seam, not code (§8).
 * Future live grading is deterministic (transcript grep for the SKILL.md
 * read / `/skill:name` invocation) — no LLM judge.
 */

import type { Ranker } from "../core/types.ts";
import type { EvalTask } from "./rankers.ts";

export type Harness = "pi" | "opencode";
export type Arm = "baseline" | "adapter";

export interface ProbeResult {
  /**
   * Necessary-condition proxy: skills the arm made *reachable* for the task
   * (never a claim of actual invocation — the live probe measures that).
   */
  invoked_skills: string[];
  /** Live probes record a transcript; the retrieval proxy has none. */
  transcript_path: string | null;
  /** Standing tokens/turn the arm pays for its listing (chars/4 proxy). */
  standing_tokens: number;
}

export type InvocationProbe = (harness: Harness, arm: Arm, task: EvalTask) => Promise<ProbeResult>;

/**
 * The retrieval proxy: wraps a Ranker + a token renderer. The adapter arm's
 * "reachable" set is the ranker's top-k for the task prompt.
 */
export function makeRetrievalProxyProbe(
  ranker: Ranker,
  k: number,
  standingTokens: (task: EvalTask, rankedIds: string[]) => number,
): InvocationProbe {
  return async (_harness, _arm, task) => {
    const ranked = await ranker(task.prompt, k);
    const ids = ranked.map((r) => r.id);
    return {
      invoked_skills: ids,
      transcript_path: null,
      standing_tokens: standingTokens(task, ids),
    };
  };
}
