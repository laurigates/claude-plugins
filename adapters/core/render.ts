/**
 * Shared injected-block / tool-result formatting (DESIGN §3.3), used by both
 * bindings (#2090/#2091) and by the eval harness's token accounting.
 *
 * The injected entry mirrors pi's native XML item shape
 * (name/description/location, location = absolute SKILL.md path) so the
 * model's trained behavior toward the block ("read the location") transfers
 * unchanged.
 */

export interface RenderableSkill {
  id: string;
  description: string;
  path: string;
}

export const AVAILABLE_SKILLS_OPEN = "<available_skills>";
export const AVAILABLE_SKILLS_CLOSE = "</available_skills>";

export const INJECTED_BLOCK_TRAILER =
  "Skills relevant to the current request are listed above. Read a skill's location path before using it. For anything not listed, call search_skills.";

export const SEARCH_SKILLS_TOOL_DESCRIPTION =
  "Search the claude-plugins skill catalog by task intent. " +
  "Returns ranked skills with the SKILL.md path; read that path to load the skill.";

/** One listing entry — the per-skill unit of the standing-token accounting. */
export function renderSkillEntry(skill: RenderableSkill): string {
  return `  <skill><name>${skill.id}</name><description>${skill.description}</description><location>${skill.path}</location></skill>`;
}

/**
 * The full injected block: pins first, then ranked results, deduped by id,
 * capped at k entries, wrapped in <available_skills> tags with the one-line
 * trailer that routes the long tail to the pull tool.
 */
export function renderInjectedBlock(
  pins: RenderableSkill[],
  ranked: RenderableSkill[],
  k: number,
): string {
  const seen = new Set<string>();
  const selected: RenderableSkill[] = [];
  for (const skill of [...pins, ...ranked]) {
    if (seen.has(skill.id)) continue;
    seen.add(skill.id);
    selected.push(skill);
    if (selected.length >= k) break;
  }
  const lines = [
    AVAILABLE_SKILLS_OPEN,
    ...selected.map((s) => renderSkillEntry(s)),
    AVAILABLE_SKILLS_CLOSE,
    INJECTED_BLOCK_TRAILER,
  ];
  return lines.join("\n");
}

/**
 * Remove every `<available_skills>…</available_skills>` span from a
 * system-prompt element, keeping the surrounding text (DESIGN §3.3
 * indexOf/slice approach, shared with the pi binding).
 *
 * Substring granularity is load-bearing for the OpenCode binding: upstream
 * request.ts pre-joins the ENTIRE system prompt (agent prompt + env + native
 * skills block + instructions) into a single array element before the
 * system.transform hook fires, so dropping whole matching elements would
 * delete the whole prompt. A malformed span (open tag with no close after
 * it) is left untouched rather than truncating the element.
 */
export function stripAvailableSkillsBlocks(element: string): string {
  let out = element;
  for (;;) {
    const open = out.indexOf(AVAILABLE_SKILLS_OPEN);
    if (open === -1) return out;
    const close = out.indexOf(AVAILABLE_SKILLS_CLOSE, open);
    if (close === -1) return out; // unclosed: leave as-is, never truncate
    out = out.slice(0, open) + out.slice(close + AVAILABLE_SKILLS_CLOSE.length);
  }
}

/** Pull-tool result text: ranked entries with the SKILL.md path to read. */
export function renderToolResult(results: Array<RenderableSkill & { score: number }>): string {
  if (results.length === 0) return "No matching skills found.";
  return results
    .map((r, i) => `${i + 1}. ${r.id} — ${r.description}\n   read: ${r.path}`)
    .join("\n");
}

/** chars/4 — the repo's established token proxy (skill-quality.md). */
export function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}
