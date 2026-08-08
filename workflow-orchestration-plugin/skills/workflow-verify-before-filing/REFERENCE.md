# workflow-verify-before-filing — Worked Example

Complete operational scaffolding from the run that motivated the skill
(FVH → SIMPL-Open on a GitLab instance, 2026-06-11: 17 candidates → 5 filed,
12 dispositioned). Adapt names/hosts; the shapes are the deliverable.

## Data flow

```
wave2-candidates.json ──► workflows/verify-before-filing.workflow.js
                            per wave of ≤5 candidates:
                              parallel[ verify-agent, search-agent ]
                              └─ gate ─► draft-agent ─► coldread(haiku) ─► revise
                            then ONE batch-dedup agent over all survivors
                          ◄── {results:[{id, disposition, draftPath, title,
                                         targetProject}], merged, dispositions}
result JSON ──► scripts/file-wave.sh (paced) ──► filed-urls.txt
filed-urls.txt + dispositions ──► source-doc annotations, tracking-issue
                                  comment, follow-up tasks
```

## Phase 1+2 — the harness: why the shape is what it is

The script itself is **not** here. It ships as
[`workflows/verify-before-filing.workflow.js`](workflows/verify-before-filing.workflow.js) and
is framed by SKILL.md § "Workflow harness (template)", which names what an adapter may rewrite.
Same split as Phase 3 below: the structure lives in the file, the *rationale* stays here
(`.claude/rules/workflow-vs-skill.md`, `.claude/rules/offload-to-deterministic-substrate.md`).
A skeleton kept in both places drifts — this one already had, predating the wave cap, the
body-carrying draft schema, and the batch-dedup barrier.

Read the file for the prompts, the schemas, and the control flow. What a future run has to
re-decide is below.

| Decision | Value | Why |
|---|---|---|
| read wave | ≤5 candidates in flight | The forge's issue endpoints are aggressively rate-limited (Phase 3 paces *writes* at 70 s for that reason), and the reads hit the same instance. Unbounded, a 24-candidate manifest fires 48 concurrent read agents. Raise only with evidence. |
| harness floor | <3 candidates → abort | Two candidates is a linear pass; the harness would spend agent preambles to save nothing. |
| gate precedence | duplicate **before** verdict | A duplicate kills the filing however present the bug is. `could-not-verify` never files — it becomes a human follow-up task. |
| revise rounds | exactly 1 | A fixed gate, not a loop-until-clear: a second cold reader is not a better judge of the same text, and an unbounded critique loop has no independent stop condition (`.claude/rules/loop-integrity.md`). |
| cold reader | `model:'haiku'`, never the drafter | The reader is the *measurement instrument* — "can a low-context reader act on this text alone?". A stronger model answers an easier question, and the drafter judging its own draft optimises for done. |
| `DRAFT_SCHEMA` carries `body` | required, alongside `path` | Batch dedup and the cold read run inside the workflow, which has **no filesystem** and cannot open a path. `path` stays required because Phase 3 reads the draft off disk. |
| batch dedup | one agent, after all waves | The per-candidate search compared each draft to the *tracker*. Nothing had compared the drafts to *each other* — and two audit docs routinely describe one upstream defect. |
| return shape | `{results:[…], merged, dispositions}` | `results` is exactly what `scripts/file-wave.sh` normalises and files; `dispositions` is the Phase 4 deliverable. |

The forge-tooling and prior-reports prompt blocks (the GitLab worked example) are constants at
the top of the `.js` — `FORGE_TOOLING` and `PRIOR_REPORTS`. Swap them wholesale for `gh`.

## Phase 3 — Paced filing: why the numbers are what they are

The loop itself is **not** here. It lives in
[`scripts/file-wave.sh`](scripts/file-wave.sh) and the skill invokes it — Phase 3
is purely mechanical, so retyping it out of this file each run would re-derive it
slightly differently every time
(`.claude/rules/offload-to-deterministic-substrate.md`). What stays here is the
*rationale*, which is the part a future run actually has to re-decide.

| Default | Value | Why |
|---|---|---|
| `--pace-seconds` | 70 | Observed: a GitLab instance returned **429 after a single create**. 70 s cleared it with margin. Treat as a starting point, not a spec — raise it if a wave still 429s. |
| `--backoff-seconds` | 130 | Roughly 2× the pace: a 429 means the window is already exhausted, so a retry needs more than the steady-state gap. |
| `--max-attempts` | 4 | Attempts *including* the first (so 3 retries). Beyond this a create is failing for a reason pacing won't fix — bad project path, revoked token — and burning 130 s per attempt buys nothing. |

Three behaviours are load-bearing and non-obvious, so they are pinned by
[`scripts/tests/test-file-wave.sh`](scripts/tests/test-file-wave.sh):

- **A failure never aborts the batch.** The run continues to the next draft and
  reports every failure at the end. A half-filed wave with no record is the worst
  outcome — you cannot tell which issues exist.
- **Every outcome is appended to `filed-urls.txt`**, success (`draft -> URL`) and
  failure (`draft -> FAILED`) alike. That manifest is what Phase 4 dispositions
  and the cross-link pass read.
- **Pacing sits *between* writes**, not after each one, so a wave never pays a
  trailing wait it cannot use.

Invocation and the forge dispatch (`gh` vs `glab`) are documented in the script's
own header — run `bash scripts/file-wave.sh --help`. Use `--dry-run` to see the
resolved title/target for every draft without creating anything.

Created GitLab issues may surface as `/-/work_items/<n>` URLs; the issues API
addresses them by the same iid (`projects/<id>/issues/<iid>`). Cross-link
related issues afterwards via
`glab api -X POST "projects/<id>/issues/<iid>/notes" -f body="..."` (paced).

## Phase 4 — Bookkeeping targets

Generic shapes; adapt to the project's systems:

- **Source docs**: append the disposition to each originating claim
  (filed URL / "fixed upstream in vX" / "claim invalid: <what was true>"),
  in the same repo, via a normal docs PR.
- **Tracking issue**: post the disposition table as a comment on whatever
  issue tracks "file these upstream"; close it when nothing known remains.
- **Follow-up tasks**: fixed-upstream discoveries become tasks in the
  project's task system (taskwarrior, GitHub issues, …): retire the fork,
  advance the pin, delete the workaround.

## Observed gotchas

- `Workflow` args may arrive as a JSON **string** — parse defensively.
- Verify agents must check both HEAD **and** the latest tag: HEAD-only
  misses "fixed on main, broken in every release" and vice versa.
- The search agent must fetch your prior reports' **full bodies** — by-catch
  findings buried inside them are the duplicates you'll miss otherwise.
- Expect framing corrections from verification (the bug is real but your
  mechanism was wrong) — let the draft cite the *corrected* mechanism.
