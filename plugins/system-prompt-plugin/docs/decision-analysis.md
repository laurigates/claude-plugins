# Bespoke Claude Code System Prompt — Decision Analysis

## Verdict: GO, phased rollout

10 concrete frictions identified between the default system prompt and our
existing configuration (dotfiles rules + claude-plugins hooks/skills/agents).

## Top conflicts

| # | Default says | We say | Impact |
|---|---|---|---|
| 1 | NEVER create files / docs | `document-management.md` mandates ADR/PRD/PRP | File creation actively discouraged |
| 2 | Verbose tone preamble rules | `communication.md`: lead-with-answer, academic, no preambles | Conflicting style directives |
| 3 | Re-confirm destructive ops each time | Hooks already gate (UserPromptSubmit, PreToolUse branch-protection) | Redundant friction |
| 4 | Generic tool descriptions | Our agentic-optimization requires compact reporters | Token waste, conflicting conventions |
| 5 | Generic commit examples | Conventional commits strictly enforced for release-please | Drift risk |
| 6 | Subagent selection guidance | 14 custom agents with explicit model/isolation/context rules | Generic vs opinionated |
| 7 | Auto-memory assumed on | `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` | Behavioral mismatch |
| 8 | Generic tool install guidance | `dependency-management.md`: mise → uv → bun → cargo → brew | Wrong tool suggested |
| 9 | No code comments default | Same principle but default duplicates without adding value | Token waste |
| 10 | Generic safety gates | LLM-powered hooks do stricter validation | Double-gating |

## Key findings

- Default is ~110 conditional fragments, not monolithic (per Piebald-AI)
- Updates weekly; full replacement drifts fast — needs upstream tracking
- `--system-prompt` replaces; `--append-system-prompt` appends. Append can't remove.
- Tool descriptions and skills survive replacement (injected by infrastructure)
- Claude Code Web cannot use `--system-prompt` (hosted UI; CLAUDE.md only)

## Phases

- **Phase 0** (this PR): Minimal replacement probe — ~24 lines, test what breaks
- **Phase 1**: Pinned full replacement for interactive terminal
- **Phase 2**: GitHub Actions variant (strip confirmation gates)
- **Phase 3**: Headless/SDK variant
- **Phase 4** (deferred): Web sessions (CLAUDE.md only)

## Upstream tracking plan

- Pin Piebald-AI version in `upstream/PINNED_VERSION`
- `scripts/fetch-upstream.sh` + `scripts/diff-upstream.sh`
- Weekly CI job opens issue on drift
- `just bump-upstream` merge workflow
