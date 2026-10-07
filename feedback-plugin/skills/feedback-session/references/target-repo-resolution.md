# feedback-session: target-repo resolution

#### Dominant-source detection: parameters and tiering

The thresholds and prompt order above are deliberate. Keep them aligned when editing this step.

| Parameter | Value | Why |
|-----------|-------|-----|
| Dominance threshold | **> 70%** of total references | Lower thresholds risk wrong defaults on mixed sessions; higher would suppress correct suggestions on small ones |
| Minimum sample size | **≥ 3** references | Two references can both come from one stray skill mention; three is the smallest sample that survives one outlier |
| Prompt tiering | suggestion → free-text → abort | The user can correct a wrong guess in one keystroke without redoing the scan, and `Abort` is always one selection away |
| Mismatch prompt | named choices (dominant / cwd / free-text / abort) | Both repos are plausible; naming them saves the user a copy-paste and makes the choice explicit |

Evidence: issue #1207 (positive feedback) reported the first end-to-end exercise of this fallback in a no-remote cwd. The 3/3 100%-dominant case auto-suggested `laurigates/claude-plugins`, the user accepted on the first prompt, and the free-text tier never fired — confirming the "Recommended" affordance lands the suggestion cleanly when the heuristic is well-tuned. Issue #1425 extended the dominant-source scan to the cwd-with-remote branch so the mismatch is surfaced rather than silently dropped.

> **Bonus / future work**: when `$SUGGESTED_REPO` is also cloned at `~/.claude/plugins/cache/<owner>/<repo>/<version>/`, that path could be used by Step 1b's `labels.tf`/`labels.yaml` Glob detection instead of cwd, so IaC-managed labels are detected correctly even when the skill runs outside the plugin checkout. This Step 1b plumbing is intentionally out of scope for this PR — track as a separate issue. For now, Step 1b continues to scan the cwd.

## The four-combination decision table (summary of Steps A–D)

Use this four-combination decision table to resolve `$TARGET_REPO`:

| `--target-repo` set? | cwd has remote? | Dominant source found? | Action |
|----------------------|-----------------|------------------------|--------|
| Yes | any | any | Use `--target-repo` value. Done. |
| No | No | Yes (≥70%, ≥3 refs) | Prompt: accept dominant source or enter free-text. |
| No | No | No | Prompt: free-text entry or abort. |
| No | Yes | Agrees with cwd remote | Use cwd remote silently. |
| No | Yes | Differs from cwd remote | Prompt: offer dominant source AND cwd remote as named choices. |

Execute the steps below to implement this table.

## Step D branches when the cwd has no git remote

- **No `$CWD_REPO` and no dominant source** — Use AskUserQuestion to ask the user to enter an `owner/repo` free-text. Validate against `^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$`, set `$TARGET_REPO`, and continue to Step 1b. If the user declines, exit the skill.

- **No `$CWD_REPO` and dominant source found** — Use AskUserQuestion to ask:

  > **No git remote found.** Suggested target: `$SUGGESTED_REPO` (derived from $N plugin skills referenced this session). Accept, or enter a different `owner/repo`?

  Options:
  1. **Accept `$SUGGESTED_REPO`** — set `$TARGET_REPO` to the suggestion and append `-R $TARGET_REPO` to every remaining `gh` command.
  2. **Enter a different `owner/repo`** — free-text follow-up; validate and set `$TARGET_REPO`.
  3. **Abort** — exit the skill.

  Continue to Step 1b once `$TARGET_REPO` is set.
