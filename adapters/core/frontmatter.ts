/**
 * DIY minimal frontmatter parser (DESIGN §2.2) — no YAML dependency.
 *
 * The core consumes exactly three top-level scalar string fields (`name`,
 * `description`, `compatibility`) out of frontmatter whose observed shape is
 * flat `key: value` scalars across all 406 SKILL.md files. Both target
 * harnesses treat unknown fields as ignorable and read only scalars, so this
 * parser matches the actual consumer semantics. Verified by a diff test
 * against Bun.YAML.parse over every real SKILL.md (tests/frontmatter.test.ts).
 */

const FIELD_RE = /^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$/;
const FOLD_MARKERS = new Set([">", ">-", "|", "|-"]);

/**
 * Return the raw frontmatter text between the leading `---` fence and the
 * closing `---` fence, or null when the document has no frontmatter.
 */
export function extractFrontmatterBlock(text: string): string | null {
  const lines = text.split("\n");
  if (lines.length === 0 || (lines[0] ?? "").trim() !== "---") return null;
  const body: string[] = [];
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i] ?? "";
    if (line.trim() === "---") return body.join("\n");
    body.push(line);
  }
  // Unclosed fence: no frontmatter.
  return null;
}

/**
 * Parse the scalar top-level fields out of a document's frontmatter.
 * Returns null when the document has no frontmatter fence. Per-field
 * fail-safe: unparseable values are treated as absent (never thrown).
 *
 * Value handling:
 * - one level of matching single/double quotes is stripped;
 * - a bare `>`/`>-`/`|`/`|-` value consumes the following more-indented
 *   lines joined with spaces (folded) — defensive, since a future skill may
 *   fold its description;
 * - lists and nested maps are skipped (no consumed field uses them).
 */
export function parseFrontmatter(text: string): Record<string, string> | null {
  const block = extractFrontmatterBlock(text);
  if (block === null) return null;

  const fields: Record<string, string> = {};
  let foldKey: string | null = null;
  let foldLines: string[] = [];

  const flushFold = () => {
    if (foldKey !== null) {
      fields[foldKey] = foldLines.join(" ").trim();
      foldKey = null;
      foldLines = [];
    }
  };

  for (const line of block.split("\n")) {
    const m = FIELD_RE.exec(line);
    if (m) {
      flushFold();
      const key = m[1] as string;
      let value = (m[2] as string).trim();
      if (FOLD_MARKERS.has(value)) {
        foldKey = key;
        foldLines = [];
        continue;
      }
      if (value.length >= 2 && value[0] === '"' && value[value.length - 1] === '"') {
        // Double-quoted style: strip the quotes and resolve the two escape
        // sequences observed in the corpus (\" and \\). Verified against
        // Bun.YAML by the whole-corpus diff test.
        value = value.slice(1, -1).replace(/\\(["\\])/g, "$1");
      } else if (value.length >= 2 && value[0] === "'" && value[value.length - 1] === "'") {
        // Single-quoted style: strip the quotes; '' is the escaped quote.
        value = value.slice(1, -1).replace(/''/g, "'");
      }
      fields[key] = value;
      continue;
    }
    if (foldKey !== null && (line.startsWith(" ") || line.startsWith("\t"))) {
      foldLines.push(line.trim());
      continue;
    }
    // Continuation of a list / nested map / blank line — not a consumed shape.
    flushFold();
  }
  flushFold();
  return fields;
}
