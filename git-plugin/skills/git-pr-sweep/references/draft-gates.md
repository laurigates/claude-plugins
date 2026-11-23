# Draft classes, markers and gates

`list-sweep-prs.sh` classifies every PR and `merge-gate.sh` gates it; both are pure jq over the
roster, so this page describes their rules rather than restating their code. Their headers and
tests are authoritative.

## Policy per PR kind (Lauri's decisions D3–D6)

| PR kind | Reviewed | Fixed | Merged by the sweep | Reported as |
|---|---|---|---|---|
| release-please (`release-please--*` head or login) | no | no | no | handled by `git-plugin:release-please-pr-workflow` |
| Renovate (`renovate/*` head or login) | yes | no | no | findings reported; merge stays with Renovate's own flow |
| head in a fork (`cross_repo_head`) | no | no | no | skipped |
| external author | yes, read-only verifiers (nothing from the PR is built or run) | no | no | `git-plugin:external-pr-trust`: authorship is a precondition of merging, and of running the code |
| WIP marker, drafts and non-drafts alike | yes | no | no | "WIP/do-not-merge marker: <which>" |
| any other PR | yes | yes | when every gate passes | — |

## WIP markers (D4)

A PR carries a WIP marker when, compared case-insensitively:

- its title starts with `WIP`, `[WIP]`, `DNM` or `[DNM]`; or
- it has the label `wip`, `do-not-merge` or `blocked`.

Labels spelled `do not merge` or `work in progress` do not count; a test pins that.

## Draft classes

`draft_class` is decided in this order, first match wins:

| Class | When | Fixed | Readied |
|---|---|---|---|
| `not_draft` | the PR is not a draft | yes | — |
| `wip` | a WIP marker | no | no |
| `no_section` | no `## Draft status` heading in the body | no | no |
| `no_blocker_urls` | the section names no PR URL; readiness is Lauri's call | no | no |
| `blockers_unresolved` | listed without `--resolve-blockers` | yes | no ("re-list with --resolve-blockers") |
| `blocked` | some blocker PR is not MERGED | yes | no; each one not MERGED is reported |
| `ready_candidate` | every blocker PR has MERGED | yes | when every gate passes and pr-merge holds nothing |

The section runs from a line matching `## Draft status` to the next `## ` heading or the end. Its
blockers are the `https://github.com/<o>/<r>/pull/<n>` URLs in it, deduplicated, cross-repo URLs
included; a URL outside the section is ignored. The blocker state is read as `state`, never `merged`.

Drafts move to ready only in the main session (`gh pr ready <n>`), before merge-chain.sh, which skips
drafts. merge-chain.sh is not changed to accept them.

## Merge gates (`merge-gate.sh`)

Evaluated in order; `gate` names the first failure and `failed` lists every one.

| # | Gate | Passes when |
|---|---|---|
| G1 | `skip` | `sweep_skip` is null |
| G2 | `author` | `author_kind` is `self` or `bot`; filtered before merge-chain.sh, because one disallowed author in `--prs` makes the merge guard deny the whole command |
| G3 | `wip` | no WIP marker |
| G4 | `review` | review status `reviewed`, no `unverified`, no `verifierFailed`, and `open` empty or the fix row `PASS`/`REPAIRED_PASS` with push status `pushed` |
| G5 | `head` | the roster `head_sha` equals the expected head: the pushed fix head, else the reviewed head |
| G6 | `ci` | `ci` is `green`, or `pending` for a non-draft (merge-chain.sh waits); `red`, `none` (no check ran) and any other value fail |
| G7 | `base` | the base is the default branch; a stacked PR is reported and retargeted by a human |
| G8 | `draft` | drafts only: `draft_class` is `ready_candidate` and `ci` is `green`, never pending |

Every report row carries `fix_block` (the roster's reason the sweep did not fix the PR) and its open
`findings`, so the findings of Renovate, external and unreadyable-draft PRs reach the final report
(D3, D6). For such a PR G4's reason names the `fix_block` rather than "no fix ran".

pr-merge adds one gate after G8 for ready drafts: `draft_prose`, held when a reader finds a
`## Draft status` condition other than a PR URL unmet or unknown, when the head moved, or when the
reader returned nothing usable. A reader can hold a draft; it cannot pass a PR the script reported.

More than 100 checks on one commit read as `pending` with `ci_truncated`, so such a draft never
passes G8.
