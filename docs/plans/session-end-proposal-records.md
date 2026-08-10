# Unified proposal records for `session-plugin:session-end`

## 1. Decision summary

Every pass emits one shared **proposal record**, but the record is a *preview and hand-off* format — not an automation gate. session-end's existing Step 3 `AskUserQuestion` becomes an **item-level** multiSelect over the merged record set, and each sub-skill skips its own item confirmation when handed a confirmed set. That single change is where the whole prompt reduction comes from (~10 → 1 on a heavy session); the vocabulary exists so five passes can share one preview line, one ordering, and one apply loop.

Passes run in two phases: **emit** (read-only, prompt-free, no outward calls) then **apply** (only the confirmed subset). A no-op, a suppressed item, and a not-queried pass emit **no record** — they are one line of report text. Confidence collapses from three self-assessed tiers to two mechanically-decidable ones (`entailed` / `judged`), used only for ordering and default selection, never printed and never a write gate.

**CUT from the original proposal:**

| Cut | Why |
|---|---|
| `--auto` | Applies ~1 non-vacuous record on a maximally productive session, while carrying 9 of the 11 auto-safety hazards. Unattended application already has two owners: the blueprint manifest gate and Claude Code's own auto mode. (AS1) |
| `--auto-threshold` | A three-value scale controlling one binary decision. Its only useful setting (`low`) authorises unattended `remove`. (PB3, CI7) |
| `--dry-run` on session-end | The mandatory preview + a Cancel option in the existing question already is it. Zero new flags on session-end. (PB9) |
| `CONFIDENCE` as a three-tier field | `collector signal + exactly one judgment step` is not script-adjudicable; the inventory graded the same record `medium` in one pass and `low` in another. Replaced by a two-value `TIER` whose boundary is *who constructed the record*. (CI1) |
| A dependency/precondition field | Dependent writes fold into their parent record; preconditions (slug confirm, target-repo resolution, manifest gate) are resolved **before** the preview, as pass mechanics. (CI3, AS4) |
| `ACTION=skip` / a null record | Would re-create the per-task enumeration as a table. (PB7, CI9) |
| A 6-column table at low item counts | ≤4 records render as prose lines. `EVIDENCE`/`TIER`/`REVERSIBLE` are never printed. (PB4) |
| Acceptance-rate calibration log | Unmeasurable on the tier that matters, confounded by the preview's own defaults. (CI4) |
| tasksync `add`; wrap `close`/`annotate`; vacuous ghid-already-linked annotate; blueprint's 6 dependent writes; distill `[SKIP]` | Cross-pass duplicates, no-ops, and consequences. (SEAM3, CI3) |
| A new `.claude/rules/*.md` | The schema is owned by `session-plugin:session-end`'s REFERENCE.md; cross-plugin consumers name-reference it (`skill-consolidation.md` §2). No always-loaded cost. |

---

## 2. The record

| Field | Vocabulary | Notes |
|---|---|---|
| `PASS` | `wrap` \| `distill` \| `feedback` \| `tasksync` \| `blueprint` | |
| `ACTION` | `add` \| `update` \| `annotate` \| `close` \| `release` \| `file` \| `remove` \| `promote` \| `drain` | `release` = drop this session's own `+ACTIVE` claim. No `skip`, no `leave`, no `probe`. |
| `TARGET` | **a list**, ≥1 entry, each of: `path:<repo-relative>` \| `justfile:<recipe>` \| `task:<uuid>` \| `<owner>/<repo>#<N>` \| `<owner>/<repo>#new:<slug>` \| `WO-<id>` | A list because one decision can produce two artifacts (`scripts/x.sh` + its recipe). `#new:<slug>` is the pre-application form for `file`/`promote`. |
| `EVIDENCE` | `collector:<KEY>=<literal value>` \| `script:<script>:<KEY>=<literal value>` \| `user:<verbatim text>` \| `judgment` | **Key *and* value, always.** A bare key binds to an unstable ordinal (`TASK_3_UUID`) and can re-bind between emit and apply. (CI5, AS7) |
| `TIER` | `entailed` \| `judged` | Derived, internal. Never rendered. |
| `REVERSIBLE` | `git` \| `task` \| `manual` \| `outward` | `manual` is new: a file we wrote outside our git (the journal in the user's vault). `outward` means published to other people. |

### TIER derivation rule (the whole rule)

> **`entailed`** iff a single `collector:` or `script:` key literally names **both the action and its target(s)**, and the model read that list rather than building it. **`judged`** otherwise, no exceptions.

Three clarifications that the three-tier rule left to per-pass interpretation, resolved here once:

- **Naming is labelling, not construction.** Choosing a recipe name or a rule filename does not demote a record whose action and target came from a key.
- **A deterministic script's output is first-class evidence** (`script:` class). A `jq` set-containment test or a `reconcile.sh` verdict is not self-assessment; grading it `judged` would exclude the only mechanical work in the system. (CI3)
- **A cardinality is never entailment.** `OPEN_TASKS=3`, `DRIFT_COUNT=2`, `READY_COUNT=4` name no target.

### What TIER is used for

Ordering, and the default selection in the one confirmation: **pre-checked iff (`entailed` ∧ `REVERSIBLE ∈ {git, task}`) ∨ `EVIDENCE` is `user:`**. `remove` and `promote` are **never** pre-checked regardless of tier. (CI8)

### Emit-phase contract

A pass's emit phase is **read-only, prompt-free, and makes no outward call**. Anything a pass needs interactively (feedback's target repo, the taskwarrior slug) is resolved by session-end in Step 1 and handed down; anything a pass mutates as a precondition (`gh label create`) moves to apply time. (SEAM1, AS6)

---

## 3. Confidence derivation table

`(new)` = depends on a new collector key or a new script invocation (§9 C1/C2).

### wrap — owns `add`, journal, and outward filings

| pass | action | evidence key | tier | reversible |
|---|---|---|---|---|
| wrap | add | `judgment` (loose thread; slug from `collector:PROJECT=<slug>`) | judged | task |
| wrap | add | `judgment` (journal log entry) | judged | manual |
| wrap | add | `judgment` (journal todo) | judged | manual |
| wrap | add | `judgment` (`+upstream` track-for-later task) | judged | task |
| wrap | file | `judgment` (post-merge follow-up, `<cwd-origin>#new:<slug>`) | judged | outward |
| wrap | file | `judgment` (upstream `<owner>/<repo>#new:<slug>`) | judged | outward |

*Folded into the `file` record, not separate:* the PR-body edit that links the issues just filed. *Not emitted:* the ghid-already-equals-PR annotate (no-op); anything suppressed by "an open PR is its own tracker" (report scalar).

### distill

| pass | action | evidence key | tier | reversible |
|---|---|---|---|---|
| distill | add | `collector:CANDIDATE_n_SESSIONS=2` + `collector:CANDIDATE_n_FIRST=<cmd>` | **entailed** | git |
| distill | add | `collector:CANDIDATE_n_BRACKETED=yes` + `CANDIDATE_n_SESSIONS=1` | judged | git |
| distill | update | `judgment` (existing recipe) | judged | git |
| distill | add | `judgment` (`path:scripts/<n>.sh` **+** `justfile:<n>` — one record, two targets) | judged | git |
| distill | add | `judgment` (`path:.claude/skills/<n>/SKILL.md`) | judged | git |
| distill | update | `collector:RULES_SIGNAL=denials` + `DENIAL_<kind>=<n>` (target file is model-chosen) | judged | git |
| distill | add | `judgment` (`path:.claude/rules/<n>.md`) | judged | git |
| distill | update | `judgment` (hot-file-adjacent rule) | judged | git |
| distill | update | `judgment` (`path:<plugin>/skills/<s>/SKILL.md`, this repo) | judged | git |
| distill | remove | `judgment` | judged | git *(never pre-checked)* |
| distill | promote | `judgment` (new skill in another repo → `<owner>/<repo>#new:<slug>`) | judged | outward |
| distill | promote | `judgment` (edit existing skill → `<owner>/<repo>#new:<slug>`, target names the existing path) | judged | outward |

### feedback — every record is `outward`; TIER never changes its handling

| pass | action | evidence key | tier | reversible |
|---|---|---|---|---|
| feedback | file | `user:<the seed finding verbatim>` | judged *(pre-checked)* | outward |
| feedback | file | `judgment` (bug / enhancement / positive from transcript) | judged | outward |
| feedback | annotate | `judgment` (dedup hit → comment on the open issue instead of dropping it) | judged | outward |
| feedback | file | `collector:DENIAL_<kind>=<n>` | — | — *(not emitted; seam S5)* |

`TARGET` repo comes from `collector:REPO=<owner>/<repo>` **(new)**, resolved once in Step 1 from the origin URL — no `gh` call, works when `gh` is absent.

### tasksync — owns `close` / `annotate` / `release` on existing tasks

| pass | action | evidence key | tier | reversible |
|---|---|---|---|---|
| tasksync | close | `script:reconcile.sh:VERDICT=pr-merged` \| `issue-closed` **(new)** | **entailed** | task |
| tasksync | annotate | `collector:TASK_n_GHID=<N>` == `collector:PR_m_NUMBER=<N>` ∧ `PR_m_URL` ∉ `TASK_n_ANNOT` | **entailed** | task |
| tasksync | close | `judgment` (session finished it; no linked ref) | judged | task |
| tasksync | annotate | `judgment` (description↔PR-title match) | judged | task |
| tasksync | annotate | `judgment` (end-of-session state note) | judged | task |
| tasksync | release | `collector:TASK_n_ACTIVE=true` (claim ownership not entailed — no identity UDA in the digest) | judged | task |
| tasksync | update | `collector:PROJECT_PREFIX_SIBLINGS=<slugs>` (re-slug a misfiled task) | judged | task |

*Not emitted:* `leave` (modal outcome — no record); `add` (wrap owns it, seam S1); a `close` derived from a PR's **absence** from `PRS` (a closed-unmerged PR is indistinguishable from a merged one — AS5).

### blueprint

| pass | action | evidence key | tier | reversible |
|---|---|---|---|---|
| blueprint | drain | `collector:UNDRAINED_WOS=<WO-id>`, gated on `BLUEPRINT:TASK_AVAILABLE=true` ∧ `JQ_AVAILABLE=true` ∧ `BPID_QUERY_OK=true` **(new)** | **entailed** | git |

One record per WO. Its evidence string, the FR status flips, the `.statistics` recalculation, `.last_updated`/`.current_phase`, the `task_registry` bookkeeping and the post-write integrity repair are **consequences of applying it**, folded into this record and never separately previewed or selectable. The Full-Sync-only discrepancy question is out of scope (session-end invokes `--drain-wave` only).

**Four `entailed` record kinds exist across five passes.** That is the honest measurement, and it is why the prompt reduction is designed to come from folding confirmations, not from automating them.

---

## 4. Degradation matrix

**One rule governs every row: a degraded collector SUPPRESSES records (emits none, costs one report line). It never demotes them.** Demoting routes a record to the confirmation, which raises prompt count precisely in the weakest environments (Claude Code on the web). A record may only be minted from a section whose **header is present** and whose own availability key says the query ran.

| Degraded state | Signal | Effect on records |
|---|---|---|
| gh absent / unauthenticated | `GH_READY=false` | Suppress every record citing a `PRS` or `GITHUB_DRIFT` key. Disqualify the **feedback** pass entirely (SEAM9). |
| gh query killed by watchdog | `GH_TIMEOUT=true` (may coexist with `GH_READY=true`) | Same as above — suppress all GitHub-derived records. |
| `mktemp -d` failed, gh present | `GH_READY=false`, no `GH_TIMEOUT` | Same as `GH_READY=false`. |
| Digest truncated by hook kill | Section **header absent** | Treat as not queried. Key on `=== SECTION ===` presence, never on the absence of `KEY_n_` rows. |
| No `task` binary | `TASK_AVAILABLE=false` / `TASK_SCOPE=none` | Suppress **tasksync** and **blueprint drain** (via the new BLUEPRINT echo). |
| `jq` absent | `JQ_AVAILABLE=false` per section **(new)** | Suppress every record from that section. No record is `entailed` anywhere when jq is absent. |
| `bpid` UDA undeclared / query errored | `BPID_QUERY_OK=false` **(new)** | Suppress the drain record. Without this key a false `UNDRAINED_COUNT=0` reads green on every precondition (CI2). |
| Tracker missing in a blueprint repo | `MANIFEST=true` ∧ `TRACKER=false` | Suppress drain; the zero was never computed. |
| Not a blueprint repo | `MANIFEST=false` | No blueprint records. Report line **names the path checked** (`--project-dir`, not repo root). |
| No slug matched | `TASK_SCOPE=all-projects-fallback` | Suppress all `TASK_n_`-derived records (those rows do not exist). `RECENT_TASK_n_` records are `judged` only. |
| Counted under another slug | `TASK_SCOPE=remote-name` \| `ancestor-name` | `judged` only, **and** rewrite the record's target scope to `PROJECT_RESOLVED`. |
| Slug untrustworthy | `PROJECT_CONFIDENCE=low` | Every record in every pass forced to `judged`; `add` records **suppressed**. |
| Prefix siblings present | `PROJECT_PREFIX_SIBLINGS=<slugs>` | Blocking precondition: confirm the slug **before** the preview renders (this is the one legitimate second prompt). All records `judged` until answered. `add` suppressed if declined. (AS2, SEAM7) |
| Hidden backlog under an ancestor | `PROJECT_AMBIGUOUS=<slug>` (fires even at `high`) | Suppress any "nothing to sync" conclusion; offer `--project <slug>`. |
| Not in git, no declaration | `DETECTION=ambiguous` ∧ `PROJECT=` empty | Treat as `TASK_SCOPE=unknown` — suppress tasksync. |
| Bad `--recent-days` | `RECENT_DAYS_INVALID=` | `RECENT_TASK_*` records `judged` only (window is not the stated one). |
| Bad gh budget | `GH_BUDGET_INVALID=` | Treat as a GitHub degradation: suppress GitHub-derived records. |
| Row lists truncated | `RECENT_TASK_TRUNCATED=true`, distill `TRUNCATED` | Per-row records fine; no record may assert completeness. `PROCESS_SIGNAL`-derived records `judged` when the interval list truncated. |
| Not a git repo | `IN_GIT=false` | Suppress every `REVERSIBLE=git` record — there is nothing to revert in. |
| No upstream branch | `UNPUSHED=0` indistinguishable from in-sync | No record may claim "work is pushed". |
| Target path dirty or untracked | `git status --porcelain -- <path>` non-empty at apply time | Record is never applied without appearing in the confirmation. `REVERSIBLE=git` is a claim about the path *now*, not its directory. (AS3) |
| distill has no input | `TRANSCRIPT_AVAILABLE=false` ∧ `STATUS=SKIP` + `SKIP_REASON=` | Suppress distill. One report line naming `SKIP_REASON`. |
| No justfile | `JUST_AVAILABLE=false` | Suppress recipe records — the novelty filter never ran, so candidates are inflated (a false-**positive** degradation). |
| Single transcript | `SESSIONS_SCANNED<2` | Recipe records `judged` only; the recurrence signal did not exist. |
| Dynamic denial keys | `DENIAL_<kind>=` (unsanitised key name) | Never trust a dynamic key name; read `DENIAL_TOTAL` and treat kinds as opaque values. |
| Coarse mode | `--summary` output | **Never mints a record.** It may only qualify or disqualify a pass. |
| Section absent because its flag was not passed | — | session-end passes `--with-commits --with-blueprint --with-dedup --with-journal` unconditionally; the record builder still verifies the header. |
| `STATUS=` / `ISSUE_COUNT=` | Hardcoded literals in every `session-survey.sh` section | **Never gate on `STATUS=`.** Every row above keys on a domain key. |

---

## 5. UX walkthroughs

### A. Modal boring session — 2 commits, 1 tracked task with a merged PR, one repeated command

**Before: 1–3 prompts. After: 1.**

```
Session end — 2 items

  tasksync   annotate task 8f2c1a4e  ← PR #2148 url
  distill    add     justfile:check-hooks
```

```
[AskUserQuestion]  Apply these?
  ☑ tasksync — annotate 1 task with its PR URL
  ☑ distill  — add 1 justfile recipe (seen in 3 sessions)
  ☐ Adjust first
```

Two records, so prose lines and no table header. No `EVIDENCE`, `TIER` or `REVERSIBLE` column. One question; both sub-skills are then invoked with the confirmed set and raise nothing of their own.

### B. Nothing qualifies

**Before: 0 prompts. After: 0.** Step 2's qualify gate is unchanged and runs **first** — only qualifying passes emit records, so the conversation re-read, the upstream scan and the feedback transcript scan never run. (PB5)

```
Nothing to capture — no loose threads, no durable learnings, no plugin friction.
taskwarrior: not queried (task binary absent).
```

The second line appears **only** because a collector degraded; a pass that merely failed to qualify says nothing. (AS11)

### C. Heavy session — merged PR, 8 open tasks (1 touched), 2 learnings, 1 upstream candidate, 1 feedback finding, 2 undrained WOs

**Before: 10–12 prompts** (1 pass-set + 8 per-task done/update/leave + 1 wrap apply gate + 1 upstream candidate + up to 4 distill categories + 1 feedback multiSelect). **After: 1.**

```
Session end — 7 items

  ACTION    TARGET
  ─────────────────────────────────────────────────────────────────
  close     task 8f2c1a4e  "narrow the cat/head/tail read block"
  annotate  task 41b0d7c2  ← PR #2148 url
  add       justfile:check-hooks
  add       .claude/rules/hook-block-scope.md
  add       task +upstream  "ast-grep nthChild ofRule docs gap"
  file      laurigates/claude-plugins#new  feedback(hooks-plugin): teach-hook stdout shape
  drain     WO-031, WO-034  → tracker tasks.completed (2 FR flips)

  7 open tasks unchanged · 3 items skipped as noise
```

```
[AskUserQuestion]  Apply these?  (multiSelect)
  ☑ tasksync — close 1 task, annotate 1 with its PR URL
  ☑ distill  — 1 justfile recipe, 1 new rule
  ☑ blueprint — drain 2 WOs from the feature tracker
  ☑ wrap     — track the upstream ast-grep gap as a task
  ☐ wrap     — file the ast-grep gap upstream now (verify + cold-read gate first)
  ☐ feedback — file 1 issue on laurigates/claude-plugins
  ☐ Adjust first
```

Seven records, so a 2-column table. The two `wrap` upstream rows are the same candidate: the reversible branch is pre-checked, the outward branch is not, and selecting the outward one drops the other (S6). Outward rows start unchecked; ticking one is the confirmation `feedback-session` Step 4 would otherwise ask for separately. `7 open tasks unchanged` is the modal `leave` outcome as a scalar, not seven rows.

If `PROJECT_PREFIX_SIBLINGS` were present, exactly one more question precedes this one, and `add` records are withheld until it is answered.

### D. The same heavy session with `--auto`

`--auto` is not a flag. Passing it is ignored (session-end's only argument remains `--project <slug>`). What the user gets instead, in a repo whose `docs/blueprint/manifest.json` has `enabled: true`, `auto_run: true`, `autonomy_level ≥ 1`, with Claude Code auto mode active:

```
Blueprint tracker-sync: drained 2 WO(s) automatically (auto_run) — WO-031, WO-034

Session end — 5 items

  ACTION    TARGET
  ─────────────────────────────────────────────────────────────────
  close     task 8f2c1a4e  "narrow the cat/head/tail read block"
  annotate  task 41b0d7c2  ← PR #2148 url
  add       justfile:check-hooks
  add       .claude/rules/hook-block-scope.md
  add       task +upstream  "ast-grep nthChild ofRule docs gap"
  file      laurigates/claude-plugins#new  feedback(hooks-plugin): teach-hook stdout shape
```

…followed by the identical question minus the blueprint row. **Prompt count: 1, same as C.** Auto mode does not suppress `AskUserQuestion` (2.1.147) and this design does not want it to: the one gate exists because outward and `manual` writes are in the set. The blueprint pass costs 0 prompts and 1 receipt line, exactly as today.

---

## 6. Auto-application contract (replaces the `--auto` contract)

**There is no `--auto` and no `--auto-threshold`.** Unattended application is owned by two pre-existing authorities, and session-end defers to both rather than stacking a third gate (`auto-mode.md`: do not double-gate).

| Authority | Scope | session-end's behaviour |
|---|---|---|
| **Blueprint manifest** — `automation.autonomy_level ≥ 1` ∧ `task_registry["feature-tracker-sync"].enabled == true` ∧ `.auto_run == true` | The `drain` record only | Resolved in Step 2, **before** the preview. `auto` → apply, leave out of the question, one receipt line. `ask` → an ordinary record in the preview. Never re-derived, never re-confirmed, never overridden. The current gate omits `.enabled`, so a repo owner's opt-out is ignored today — fixed in C2. (AS4, PB6) |
| **Claude Code auto mode** | The harness's own permission decision on each tool call | Inherited. session-end adds nothing. A sub-skill invoked **standalone** keeps its current auto behaviour unchanged — notably `session-distill`, which applies git-reversible proposals with zero prompts and confirms `remove`. Under orchestration those proposals are already covered by the one confirmation, so nothing regresses. (PB2) |

**Never applied without appearing in the confirmation**, in any mode:

- Any record with `REVERSIBLE ∈ {outward, manual}`.
- Any `remove` or `promote`, regardless of tier.
- Any record whose target path is untracked or modified at apply time.
- Any record from a pass with a live precondition (`PROJECT_PREFIX_SIBLINGS`, `PROJECT_CONFIDENCE=low`, `PROJECT_AMBIGUOUS`).
- Any record from a degraded section (§4 — those are suppressed before they exist).

**Reporting.** session-end's existing Step 5 report lists every record that was applied with its `ACTION`, `TARGET` and `EVIDENCE` value, plus the receipt for anything the manifest gate applied. No apply log, no JSON artifact — the git diff and the taskwarrior annotations are the audit trail. Nothing applied by an outer authority stages or commits, so `git restore` stays live. (AS10)

**Applying a `drain` passes its own `EVIDENCE` value through as `--evidence <text>`**, so the sync skill's priority-2 branch wins and its priority-4 `AskUserQuestion` is structurally unreachable. (AS8)

**Chained automation is an accepted residual risk** (AS9): a `scheduled-reconcile.sh --apply` close feeding a later `entailed` drain is still an unreviewed completion claim. With `--auto` cut, the drain's application requires either a human ticking the box or the repo owner's manifest opt-in, which is the smallest honest containment.

---

## 7. Seam rules

| # | Collision | Executable rule |
|---|---|---|
| **S1** | tasksync `add` vs wrap `add` for the same thread (today deduped only by Step 4 ordering, which two-phase emit destroys) | `add` is **cut from tasksync's vocabulary**. wrap owns `add`; tasksync owns `close`/`annotate`/`release`/`update` on existing tasks. (SEAM3) |
| **S2** | Two outward `file` records, one gated and one not | Any `file` or `promote` whose TARGET repo ≠ the cwd `origin` routes through `workflow-orchestration-plugin:workflow-verify-before-filing` → `agent-patterns-plugin:cold-read-gate` before the write, whichever pass emitted it. Deliberate consequence: feedback's cross-repo issues now go through cold-read-gate too. Both are workflows, not confirmations — latency, not clicks. (SEAM2) |
| **S3** | distill `promote` vs feedback `file` for the same plugin | If a `promote` names `<plugin>/skills/<skill>` and a `file` record's title scope is `feedback(<plugin>)` for the same plugin **and** the same TARGET repo, the `promote` wins; the feedback record is dropped and its evidence goes into the PR body. A PR is strictly more than an issue reporting the same thing. (SEAM6) |
| **S4** | Blueprint drain preview computed before tasksync's closes apply | The preview's wave = `CLOSED_BPID_COUNT` set ∪ `TASK_n_BPID` **(new)** of every task carrying an accepted `close` record. Step 4.3's inline re-derivation stays authoritative; this makes the preview agree with it and makes declining a close visibly shrink the drain row. (SEAM4) |
| **S5** | `RULES_SIGNAL=denials` feeding both distill and feedback | When distill emits a denials-derived record, feedback emits none for the same `DENIAL_<kind>`. Consequence: feedback never runs `distill-survey.sh`. (SEAM10) |
| **S6** | Two records for one upstream candidate | `add +upstream` (task) and `file` (outward) are emitted as a pair over one target. If both are selected, `file` wins and the `add` is dropped. |
| **S7** | A pass that cannot run | **No record and no row.** One report line, and only when the underlying signal is non-zero: `blueprint: 3 undrained WO(s) — blueprint-plugin not installed`. Reuses `session-spinup`'s `<source>: not queried (<reason>)` vocabulary. (SEAM5) |
| **S8** | Records leaking into the next session | Records are **ephemeral**: they live for one session-end invocation, are never persisted, and are never read by `session-spinup`. The only cross-session carrier is the artifact itself. (SEAM11) |

---

## 8. Edge cases — every finding

| # | Scenario | Sev | Resolution |
|---|---|---|---|
| PB1 | Record schema reduces zero prompts on its own | blocker | **designed-for** — §1: propose/apply split + item-level Step 3 + sub-skills skip their own gates. |
| PB2 | `--auto` is a strict regression for distill | blocker | **designed-for** — `--auto` cut; standalone distill's auto path untouched (§6). |
| PB3 | `--auto-threshold` cuts a safety gate | major | **designed-for** — cut. |
| PB4 | 6-column table heavier than prose | major | **designed-for** — ≤4 records = prose; ≥5 = 2 columns; internals never printed (§5). |
| PB5 | Emission replaces the qualify gate | major | **designed-for** — Step 2 unchanged and runs first (§5B). |
| PB6 | Blueprint auto-drain regresses to a preview row | major | **designed-for** — manifest gate resolved before the preview (§6). |
| PB7 | `leave` must emit no record | major | **designed-for** — §2: records are proposed writes only. |
| PB8 | feedback resolves its repo lazily and can prompt first | major | **designed-for** — `REPO=` (new) in Step 1; emit phase prompt-free (§2). |
| PB9 | Three new flags; `--dry-run` duplicates the preview | minor | **designed-for** — zero new flags on session-end. |
| CI1 | medium/low boundary not script-adjudicable; same record graded twice | blocker | **designed-for** — two tiers, boundary = who constructed the record (§2). |
| CI2 | Tier from key *presence* mints confidence on degraded reads | blocker | **designed-for** — §4 suppress-never-demote + `BPID_QUERY_OK`/`JQ_AVAILABLE`/`TASK_AVAILABLE` echoes. |
| CI3 | Blueprint grades six records high with no collector key | major | **designed-for** — `script:` evidence class; the six are dependent writes folded into the drain. |
| CI4 | Acceptance-rate calibration unmeasurable | major | **designed-for** — cut. |
| CI5 | EVIDENCE citing a bare key binds to an unstable ordinal | major | **designed-for** — `KEY=<literal value>`, mandatory. |
| CI6 | Deriving CONFIDENCE on outward-only passes costs a collector run | major | **designed-for** — outward ⇒ ask, decided by REVERSIBLE alone; S5 removes feedback's need for `distill-survey.sh`. |
| CI7 | `--auto-threshold medium` is a rename of `high` | minor | **designed-for** — cut. |
| CI8 | Tier controls destructiveness without measuring it | minor | **designed-for** — `remove`/`promote` gated on ACTION, never pre-checked. |
| CI9 | "Not queried" has no representation; invites `ACTION=skip` | minor | **designed-for** — S7: one report line, never a record. |
| AS1 | `--auto` buys one recipe and carries every hazard | blocker | **designed-for** — cut (§1, §6). |
| AS2 | An exact UUID is not evidence of scope | blocker | **designed-for** — §4 prefix-sibling/low-confidence rows force `judged` and suppress `add`; slug confirm is a blocking precondition. |
| AS3 | `REVERSIBLE=git` is a property of the path, not the tree | blocker | **designed-for** — §4 last row + §6: tracked-and-unmodified required for unattended application. |
| AS4 | `--auto` overrides the manifest; the gate omits `.enabled` | blocker | **designed-for** — §6 defers to the manifest in both directions; `.enabled` fixed in C2. |
| AS5 | `close` from the absence of an open PR | major | **designed-for** — tasksync's self-derived `close`-by-absence cut; delegated to `reconcile.sh --dry-run --only-verdicts=pr-merged,issue-closed`. |
| AS6 | `--dry-run` already writes (labels) | major | **designed-for** — emit phase is read-only; `gh label create` moves to apply time (C5). |
| AS7 | `--dry-run` output not predictive | major | **designed-for** — `--dry-run` cut; EVIDENCE key+value must still resolve at apply time or the record is dropped. |
| AS8 | An applied record hits a prompt inside the delegated skill | major | **designed-for** — `--evidence` pass-through on drain (C7). |
| AS9 | Chained automation launders an unverified close | major | **accepted-risk** — argued in §6; containment is that no flag can apply the drain, only a human or the repo owner's manifest. |
| AS10 | Audit trail expires when the change is committed | major | **designed-for** — no staging/committing by any auto path; Step 5 reports ACTION/TARGET/EVIDENCE; no new artifact. |
| AS11 | Silence when nothing auto-applies vs a suppressed pass | minor | **designed-for** — §5B asymmetry: degraded ⇒ one line; merely-unqualified ⇒ nothing. |
| SEAM1 | Building the preview is neither read-only nor prompt-free | blocker | **designed-for** — §2 emit-phase contract; C5 reorders feedback. |
| SEAM2 | Outward gates flattened into one table row | blocker | **designed-for** — S2. |
| SEAM3 | Batching destroys the ordering that deduped tasksync vs wrap `add` | major | **designed-for** — S1. |
| SEAM4 | Drain row computed from a pre-close snapshot | major | **designed-for** — S4 + `TASK_n_BPID` (new). |
| SEAM5 | An absent cross-plugin pass has no detection and would get phantom rows | major | **designed-for** — S7. |
| SEAM6 | `promote` and feedback `file` duplicate | major | **designed-for** — S3. |
| SEAM7 | Unattended write under an unverified slug is invisible from both sides | major | **designed-for** — `--auto` cut removes the write path; §4 keeps the slug confirm blocking. |
| SEAM8 | The Stop nudge must never offer `--auto`; its own probe is a raw prefix match | minor | **designed-for** — C8: no flag in the nudge, `task_cue` deleted, probe reuses `session-survey.sh --summary`. |
| SEAM9 | feedback should disqualify on `GH_READY=false` | minor | **designed-for** — §4 + C5 qualify condition. |
| SEAM10 | Resist a spinup-facing record field | minor | **designed-for** — S8. |

---

## 9. Implementation order

Packages: `session-plugin`, `feedback-plugin` are separate release-please packages; **`blueprint-plugin` is not touched** (the sync skill already accepts `--evidence`), so it does not bump. No `.claude/rules/*.md` is added. The schema is **owned** by `session-plugin/skills/session-end/REFERENCE.md`; `feedback-plugin` and any other consumer reference it by the name `session-plugin:session-end` — never by file path (`skill-consolidation.md` §2).

| # | Commit | Files | Regression guard |
|---|---|---|---|
| **C1** | `feat(session-plugin): emit availability and linkage keys in session-survey.sh` | `session-plugin/scripts/session-survey.sh`, `session-plugin/scripts/tests/test-session-survey.sh` | New TESTs, semantic (execute the collector): `BLUEPRINT` emits `TASK_AVAILABLE=`/`JQ_AVAILABLE=`/`BPID_QUERY_OK=`; a **failing** `task bpid.any:` query yields `BPID_QUERY_OK=false` beside `UNDRAINED_COUNT=0` (the false-zero case, which currently reads green on every precondition); `REPO=<owner>/<repo>` derived from the origin URL with **no** `gh` invocation in the argv log; `TASK_n_BPID=` present and row/column-sanitised; `UNDRAINED_WOS_NO_EVIDENCE=` lists WOs whose linked task has no annotation. Guard integrity: a repo with no origin emits `REPO=` empty, not a garbage slug. |
| **C2** | `fix(session-plugin): pass --with-dedup and read .enabled in the blueprint auto-drain gate` | `session-plugin/skills/session-end/SKILL.md` | `plugin-compliance-check.sh check_skill_body()` for `session-end`: pins `--with-dedup` **and** all three manifest fields (`enabled`, `auto_run`, `autonomy_level`) in the gate jq. Negative guard: the two-field jq form must not reappear. |
| **C3** | `feat(session-plugin): proposal records and one item-level confirmation` | `session-plugin/skills/session-end/SKILL.md`, **new** `session-plugin/skills/session-end/REFERENCE.md` (owns the schema) | **New** `scripts/check-session-records.sh --strict` (+ `scripts/tests/test-check-session-records.sh`): asserts the `ACTION` and `REVERSIBLE` vocabularies appear exactly once in the repo (in the owner REFERENCE.md) and that no consumer skill restates the table; asserts session-end's body carries the emit-phase contract (read-only ∧ prompt-free), the no-op-emits-no-record rule, the `KEY=<value>` evidence form, and the ≤4-records-render-as-prose rule. Mutation-verified against a body with each clause removed. |
| **C4** | `refactor(session-plugin): wrap and distill emit records; drop their own item gates` | `session-plugin/skills/session-wrap/{SKILL,REFERENCE}.md`, `session-plugin/skills/session-distill/{SKILL,REFERENCE}.md` | Extend `check-session-records.sh`: each consumer carries the `session-plugin:session-end` **name**-reference and no duplicated vocabulary. Negative guard: wrap no longer instructs a per-candidate `AskUserQuestion`. Positive guards preserved: `+upstream`, `workflow-verify-before-filing` (wrap); `distill-survey.sh`, `--process`, `.claude/skills/`, `git clone --depth 1 --single-branch` (distill); distill's standalone auto path still confirms `remove`. |
| **C5** | `fix(feedback-plugin): resolve the target repo from the digest and defer label creation to apply time` | `feedback-plugin/skills/feedback-session/SKILL.md` | `check_skill_body()` for `feedback-session`: pins consumption of `REPO=` and `GH_READY=`; **negative** guard that `gh label create` does not appear before the issue-creation step; pins the existing `SEED_FINDINGS` contract and `disable-model-invocation` absence. |
| **C6** | `feat(feedback-plugin): accept a confirmed record set and annotate dedup hits` | `feedback-plugin/skills/feedback-session/SKILL.md` | `check_skill_body()`: pins the `session-plugin:session-end` name-reference, the "skip Step 4 when handed a confirmed set" clause, and `annotate` on the dedup path. Negative guard: the dedup branch must not silently drop the finding. |
| **C7** | `fix(session-plugin): pass drain evidence through to the tracker sync` | `session-plugin/skills/session-end/SKILL.md` | `check_skill_body()`: pins `--evidence` adjacent to `--drain-wave`, so the sync skill's priority-4 `AskUserQuestion` stays unreachable from an orchestrated run. |
| **C8** | `fix(session-plugin): stop the end nudge advertising the per-task loop` | `session-plugin/hooks/session-end-nudge.sh`, `session-plugin/hooks/test-session-end-nudge.sh` | Existing suite extended: the injected reason names no flag; the `task_cue` paragraph is gone; the raw `task project:"$(basename …)"` prefix probe is replaced by `session-survey.sh --summary` (paired positive control: a genuine wind-down still fires the offer). |

C1 → C2 → C3 must land in order (C3's rules cite C1's keys and C2's flags). C4–C8 are independent of each other.

---

## 10. Open questions

1. **`manual` as a fourth `REVERSIBLE` value** — it correctly stops the journal auto-applying while distinguishing "not revertible by us" from "published to other people". Accept, or keep the journal in `outward` and lose that distinction?
2. **tasksync `close` via `reconcile.sh --dry-run`** — this is the only way any `close` reaches `entailed`, but it adds a `gh` poll to session-end's critical path (bounded, parallel-safe). Accept the latency, or drop the `script:` evidence path and leave every `close` `judged`?
3. **Pre-selection** — the confirmation pre-checks `entailed ∧ {git,task}` plus user-stated findings. Is a pre-checked box an acceptable confirmation for those records, or should the multiSelect start entirely unchecked (costing a few extra keystrokes on every session but removing the "confirmed by default" objection)?
4. **The `.enabled` gate fix (C2) changes live behaviour** for any repo that disabled `feature-tracker-sync` while leaving `auto_run: true` — session-end will stop auto-draining there. Ship it inside this series, or as a standalone fix first so the behaviour change is attributable?
5. **Feedback's standalone `--dry-run`** stays on the skill for direct invocation, but session-end has no equivalent. Is "Adjust first" in the single question a sufficient preview-only path, or is a read-only session-end invocation still wanted?
