---
created: 2026-06-15
modified: 2026-06-24
reviewed: 2026-07-04
paths:
  - ".github/workflows/**"
---
# GitHub Actions Security

The secure-use baseline for every workflow this repo authors and for the example
snippets in any skill that scaffolds or describes a GitHub Actions workflow.
Distilled from GitHub's [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use);
this rule is the citable repo standard, the doc is the upstream source.

Companion to `version-pinning.md` (third-party action SHA pinning, the one
secure-use item this repo already manages via Renovate) and `workflow-naming.md`
(the `<Domain>: <Action>` naming convention).

## The baseline checklist

| # | Practice | What it looks like |
|---|----------|--------------------|
| 1 | **Least-privilege `GITHUB_TOKEN`** | Every workflow carries an explicit `permissions:` block. Without one the token gets the repo-default scope; with one, anything unlisted is `none`. Grant the narrowest set per job, escalate only where needed. |
| 2 | **Script-injection indirection** | Untrusted run-context values (`github.event.*.title`, `.body`, `.head.ref`, comment bodies) go through an intermediate `env:` variable referenced as `"$VAR"` — never interpolated `${{ … }}` directly into a `run:` script. |
| 3 | **Pin third-party actions** | SHA pin + version comment, managed by Renovate. See `version-pinning.md`. |
| 4 | **OIDC over long-lived secrets** | For cloud auth, use `id-token: write` + the provider's OIDC login action instead of storing static cloud credentials as secrets. |
| 5 | **Guard `pull_request_target`** | It runs in the **base** repo context with secrets and a write-capable token. Never check out *and build/execute* untrusted PR head code in the same job, and never expose secrets to steps that touch PR content. |
| 6 | **Mask & scope secrets** | `${{ secrets.* }}` only — never plaintext. `::add-mask::` any derived sensitive value. Don't wrap secrets in JSON/XML/YAML (breaks redaction). Register transformed secrets. |
| 7 | **CODEOWNERS on workflows** | Add `/.github/workflows/` to `.github/CODEOWNERS` so workflow edits require a designated reviewer. |
| 8 | **Constrain Actions' write power** | Prefer the repo setting that blocks Actions from creating/approving PRs unless a workflow genuinely needs it. |
| 9 | **Avoid self-hosted runners on public repos** | GitHub-hosted (ephemeral) runners by default; if self-hosted is unavoidable, use just-in-time ephemeral runners and runner groups. |

## Script injection: the load-bearing pattern

The single most-missed item. A workflow author who writes:

```yaml
# WRONG — title is attacker-controlled; `a"; rm -rf / #` runs as shell
- run: echo "Reviewing PR: ${{ github.event.pull_request.title }}"
```

has handed shell execution to anyone who can open a PR. The fix is **always**
the same — bind the untrusted value to an environment variable, then reference
the shell variable (quoted):

```yaml
# CORRECT — the value reaches the shell as data, not code
- env:
    PR_TITLE: ${{ github.event.pull_request.title }}
  run: echo "Reviewing PR: $PR_TITLE"
```

This applies to any value an external user controls: issue/PR titles and bodies,
comment bodies, branch and base ref names, author names, and label names. For
non-trivial logic, prefer a JavaScript action that receives the context value as
an argument over an inline shell script.

> **Claude Code workflows are not exempt.** The `anthropics/claude-code-action`
> `prompt:` block consumes the same untrusted context. Treat issue/PR/comment
> content as untrusted input in the prompt (strip hidden instructions, validate
> format) — this is *prompt* injection, the sibling of *shell* injection above.
> See `github-actions-plugin:github-actions-auth-security`.

## Skills that must follow this rule

Any skill that emits or describes a workflow YAML snippet applies the checklist
in its examples:

| Skill | Surface |
|-------|---------|
| `github-actions-plugin:github-actions-auth-security` | Canonical permissions / secrets / injection guidance |
| `github-actions-plugin:claude-code-github-workflows` | Claude Code workflow templates |
| `github-actions-plugin:github-workflow-auto-fix` | `Auto-fix:` and reusable-workflow templates |
| `configure-plugin:ci-workflows` | Canonical workflow shapes (build, test, release) |
| `configure-plugin:configure-workflows` | Interactive scaffolder |
| `configure-plugin:configure-reusable-workflows` | Reusable-workflow callers |
| `agents-plugin/agents/ci.md` | CI agent's example workflows |

When you add a new workflow-scaffolding skill, register it here.

## Related

- `.claude/rules/version-pinning.md` — SHA pinning of `uses:` refs (checklist item 3), Renovate-managed
- `.claude/rules/workflow-naming.md` — `<Domain>: <Action>` naming for the same workflow surface
- `github-actions-plugin:github-actions-auth-security` — the skill that carries the worked examples
- GitHub [Secure use reference](https://docs.github.com/en/actions/reference/security/secure-use) — upstream source
