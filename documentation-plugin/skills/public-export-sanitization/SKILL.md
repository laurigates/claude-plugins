---
name: public-export-sanitization
description: "Sanitize internal content before it goes public (repo, blog, talk). Use when publishing, to catch leaked project ids, service-account emails, hostnames, names, and repo-escaping links."
allowed-tools: Bash(bash *), Read, Grep, Glob, Edit, TodoWrite
created: 2026-09-24
modified: 2026-09-24
reviewed: 2026-09-24
---

# Sanitizing Internal Content Before It Goes Public

When moving content from a private or internal source into a **public**
destination (a public repo, a blog post, a conference talk, a shareable draft),
the expensive failure is a **silent context leak**: an internal cloud project
id, a service-account email, an internal hostname, a personal name, or a
Markdown link that points back into a private repo. A human reviewer reliably
misses *one* class of these every time, and the miss becomes visible only after
it is public.

The judgment (what to keep, how to reword) is yours. The detection is a script:
run it, don't re-derive it.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Moving internal docs, code, or notes into a public repo, post, or talk | Scanning for tokens and keys: `git-plugin:git-security-checks` (gitleaks) |
| Checking that an exported doc set has no links back into private sources | Checking a doc is readable by a zero-context reader: `agent-patterns-plugin:cold-read-gate` |
| Genericizing infrastructure identifiers for a public write-up | Verifying a machine-read value is *correct*: `documentation-plugin:docs-verify-machine-facts` |

## The tripwire: run it on every export

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/check-public-export.sh" --patterns <org.patterns> <export-tree>
```

It scans for internal **identifiers** and for **Markdown links that escape the
export or are broken**. Exit 1 means findings to review; exit 2 is a usage
error. Patterns ignore `<placeholder>` tokens, so a genericized tree comes back
clean.

**Built-in patterns are org-neutral only**: GCP service-account emails
(`*.iam.gserviceaccount.com`), 12-digit GCP project numbers, and absolute home
paths. Your organisation's identifier shapes go in a `--patterns` file, one
`label::regex` per line (extended regex, `#` comments allowed), kept wherever
your private config lives rather than in the public tree:

```text
# org.patterns
GCP project id (acme-*)::\bacme-[a-z][a-z0-9-]{2,}\b
Internal hostname (corp.example)::\b[a-z0-9-]+\.corp\.example\b
Staff email::\b[a-z0-9._%+-]+@example\.com\b
```

Without a `--patterns` file the scan checks only the built-in shapes, so a
clean result then says nothing about org-specific identifiers.

Two modes:

- **Pre-export gate (default, strict):** scan the export set on its own; *any*
  link leaving it is flagged. This is the self-containment gate below.
- **Post-placement verify:** once the content sits inside a larger **public**
  repo, pass `--repo-root <repo>` so links to public siblings (`../LICENSE`,
  `../other-doc`) are allowed and only repo-escaping or broken links flag.

Other options: `--names <file>` (personal names, which can't be regex'd; seed
the list from the source's git authors and access grants), `--allow <regex>`
(dismiss a known-benign hit, such as a CSS class that shares a project-id
prefix; check the regex does not also hide real ids), `--no-links`, `-q`.

It is **not** a secret scanner. Run `gitleaks` for tokens and keys; this catches
*context* leakage, a different axis.

## Curation rubric (per candidate doc or file)

Keep a candidate only if it clears all five:

| Gate | Pass condition |
|---|---|
| **Audience** | The source already marks it shareable (an inventory tag, an explicit "OK to share"); internal-only means drop it. |
| **Self-containment** | No dependency on private docs or infra; links rewritten to public targets or removed. |
| **Relevance** | Teaches the public audience something genuinely useful. |
| **Sensitivity** | No secrets; internal identifiers genericized; safe in the open. |
| **Durability** | Durable knowledge, not a point-in-time snapshot that rots. |

## Genericization checklist (identifier to placeholder)

Replace the real value and keep the architecture. Common classes:

- Cloud project id / number: `<gcp-project-id>` / `<project-number>`
- Service-account email: `<sa-name>` (or
  `<sa-name>@<gcp-project-id>.iam.gserviceaccount.com`; the bare form keeps the
  scan clean and consistent)
- Database, KMS, and secret-manager resource names: `<cloud-sql-instance>`,
  `<…-keyring>`, `<…-secret>`
- Internal hostnames: `<…-host>`
- Internal issue/PR refs (`#NNNN`): drop, or "(tracked internally)"
- **Personal names** and usernames: a role ("a team member", "an applicant")
- Internal cost or accounting codes: the project name, not the numeric code

**Keep** the non-sensitive facts that carry the value: region, machine types,
CIDRs, component/chart/image versions, public DNS hostnames, public upstream
URLs.

## Link rewriting

No link may leave the export set except to **public** upstream. Links into the
private source (`../adr/…`, `../../infra/…`, `.claude/rules/…`) become
self-contained prose or are repointed within the export. The script's link
check is the backstop for the class humans miss most.

## Delivery discipline

- Branch off a fresh `origin/main`, stage only the new paths
  (`git add <paths>`, never `-A`), and check that `git log origin/main..HEAD`
  shows only your commit before pushing.
- If the export PR is squash-merged and you pushed more commits to its branch
  afterward, those commits are in neither `main` nor the squash. Replay them onto
  a fresh `origin/main` in a new PR.
- Run the tripwire once more against the content **in its destination**
  (`--repo-root <repo>`) before opening the PR.

## Agentic Optimizations

| Context | Command |
|---|---|
| Summary line only | `bash "${CLAUDE_SKILL_DIR}/scripts/check-public-export.sh" -q --patterns <org.patterns> <tree>` |
| Inside a public repo | `bash "${CLAUDE_SKILL_DIR}/scripts/check-public-export.sh" --repo-root <repo> --patterns <org.patterns> <tree>` |
| Identifiers only | `bash "${CLAUDE_SKILL_DIR}/scripts/check-public-export.sh" --no-links --patterns <org.patterns> <tree>` |
