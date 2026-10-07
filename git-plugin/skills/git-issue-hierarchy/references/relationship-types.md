# Choosing a Relationship Type

Moved verbatim from `SKILL.md`. Read when unsure whether a link should be a sub-issue, a `blocked_by` dependency, or a plain cross-reference.

## When to Use

| Use this skill when... | Use X instead when... |
|------------------------|----------------------|
| Breaking issues into sub-tasks | Creating standalone issues (`github-issue-writing`) |
| Checking sub-issue completion progress | Implementing/processing issues (`git:issue`) |
| Recording `blocked_by` / `blocking` dependencies | Auto-detecting related issues (`github-issue-autodetect`) |
| Viewing a blocker graph before picking work | Searching for OSS solutions (`github-issue-search`) |

### Sub-issues vs. dependencies vs. "related to"

GitHub ships three distinct ways to link issues. Pick the right one — they're
not interchangeable:

| Relationship | When to use | API surface |
|--------------|-------------|-------------|
| **Sub-issue** (parent ↔ child) | Child issue is a *part of* the parent's scope. Completing all children fulfils the parent. | `issues/{N}/sub_issues` |
| **Blocked by** (hard dependency) | Parent *cannot start or ship* until the other issue closes. Makes the blocked issue render a "Blocked" badge on boards. | `issues/{N}/dependencies/blocked_by` |
| **Blocking** (read-only inverse) | You want to see everything *this* issue gates. Managed by creating `blocked_by` links on the other side. | `issues/{N}/dependencies/blocking` |
| **"Related to #N" in body** | Soft cross-reference, no lifecycle coupling, no board indicator. | Plain markdown — no API needed |

Sub-issues express **composition** ("is part of"). Dependencies express
**ordering** ("must happen before"). The same two issues should rarely use
both — a sub-issue is implicitly ordered by its parent's scope.
