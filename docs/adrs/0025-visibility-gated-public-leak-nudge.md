---
id: ADR-0025
date: 2026-10-26
created: 2026-10-26
modified: 2026-10-26
status: Accepted
deciders: claude-plugins team
domain: architecture
relates-to:
  - ADR-0017  # hooks as the cue substrate; this ADR adds a destination-conditional cue
  - ADR-0016  # deterministic scripts own mechanical checks; the gate reuses one
---

# ADR-0025: Gate Public-Repo Leaks at the Write, Keyed on the Destination's Visibility

## Context

Guidance about sanitizing internal content (the
`documentation-plugin:public-export-sanitization` skill and the always-loaded
rule stubs that point at it) applies only when the text is headed somewhere
public. It is loaded on every turn regardless, including in private repos, so
the agent weighs public-repo rules where they do not apply.

A SessionStart hook that reads the session repo's visibility and injects the
matching guidance would scope it, but it decides on the wrong repo. Sessions in
this portfolio typically start in a multi-repo root (`~/repos`,
`~/repos/laurigates`) and write to several repos of mixed visibility. The leak
that matters crosses repos: an internal identifier from one org landing in a
public repo of another, or a PR comment on a public repo citing a private one.
The relevant visibility is that of each write's destination.

## Decision

Add a PreToolUse hook, `documentation-plugin/hooks/public-repo-leak-gate.sh`,
that fires on outbound writes only: `git commit`, `gh pr|issue
create|comment|edit|review`, and the GitHub MCP write tools.

1. It resolves the destination (`git -C` / leading `cd` / cwd for a commit;
   `-R`, a github.com URL, or cwd for `gh`; `owner`/`repo` for MCP) and its
   visibility through `repo-visibility.sh`, which caches `gh api` results for
   24 h and never caches a failed lookup.
2. Private, internal, and local-only (no `origin`) destinations get no output.
   Public destinations, and destinations whose visibility could not be read,
   are scanned; the second case is stated as unknown in the prompt.
3. The text that would be published (staged added lines, plus the unstaged
   diff for `commit -a`; the command text with path operands removed;
   `--body-file` / `-F` contents; MCP string inputs) is scanned by the skill's
   existing `check-public-export.sh` with the portfolio patterns file found by
   walking up from the destination checkout.
4. A clean scan gets no output. Findings produce `permissionDecision: "ask"` listing
   them. It is never a deny: the same identifier is legitimate in its own
   org's public repos, which only the user can judge. Owners listed in
   `.claude/public-export.exempt-owners` skip the org patterns but keep the
   built-in shapes.

The hook lives in `documentation-plugin` beside the scanner, so it calls the
scanner by a path inside its own install unit.

## Consequences

- The sanitization check runs at the moment of publication and only when the
  destination is public, so its guidance no longer has to be resident to fire.
  The always-loaded rule stubs can be demoted once this has run in practice;
  that change lives in the portfolio's own rules repo, not here.
- Each outbound write to a public repo pays one scanner run (`rg` over the
  outbound text) and, on a cache miss, one `gh api` call (~0.5 s measured).
  Every other Bash call exits at the trigger regex.
- Known gaps: commits made outside the agent are not scanned, `git push` is not
  a trigger, and a commit with explicit pathspecs scans the index rather than
  the working-tree versions it commits. A private repo flipped to public
  publishes its whole history at once, which no per-write hook can see; that
  belongs in the gitops visibility change itself.
- `CLAUDE_HOOKS_DISABLE_PUBLIC_LEAK_GATE=1` disables it;
  `CLAUDE_REPO_VISIBILITY_TTL` tunes the cache.
