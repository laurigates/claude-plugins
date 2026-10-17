# Sync Notes for git-merge-hazards

Maintainer notes on [SKILL.md](../SKILL.md). Its numbered sections (§1 to §6) are
the verbatim text of the promoted `~/.claude/rules/pr-merge-hazards.md` rule, with
the exceptions listed in this file. Read it when syncing that rule.

- The `## Agentic Optimizations` table is this skill's own command index; leave it
  out when syncing with `pr-merge-hazards.md`.
- §5's follow-on subsections moved verbatim into `references/`; they are still
  rule text when syncing. §3's pointer moved too, but its registration-race text
  diverged (see **Diverged, not yet mirrored: §3's registration race**).
- Skill-only, not in `pr-merge-hazards.md`: §6, §4's merge-endpoint pointer, and
  the two §2 bullets **Check the base first** and **No-force alternative**. The
  chezmoi rule does not carry those two §2 bullets yet. Mirror them there, or the
  next sync removes them from this skill.
- Skill-only, not in the body of `pr-merge-hazards.md`: §1's REVIEW-bucket sentence,
  the last sentence of the **Fix** bullet (#2268). The chezmoi rule keeps that
  sentence in its notes outside the body. Move it into the body there, or the next
  sync deletes it from this skill, and `scripts/check-branch-containment-guidance.sh`
  then fails on `branch_audit_uncaveated`.
- **Diverged, not yet mirrored: §3's registration race.** The rollup gate in
  [stacked-chain-push.md](stacked-chain-push.md) replaces the chezmoi copy's
  expected-count gate with the `headRefOid`, completion, two-read, deadline and
  terminal-state rules (#2826), and its background run carries an explicit
  `timeout` above the deadline. Mirror that gate into `pr-merge-hazards.md`, or the
  next sync reinstates the count gate that broke on path-filtered workflows.
- Two gates, §1's merged-ness authority order and §4 (minus its skill-only
  merge-endpoint pointer), are also reproduced verbatim in the
  `pr-merge-hazards.md` stub, because they are read *while* the decision is being
  made. Edit both copies together.
- §1 overlaps `git-plugin:deadbranch` Step 1.5, which carries the same three
  signals scoped to branch cleanup.
- §2 and §3 describe **ad-hoc** chains, meaning PRs whose base is another PR's
  branch. A stack **registered with GitHub** (`gh stack`) retargets its upper PRs
  itself on merge, so the auto-close hazard and the manual retarget/rebase
  ordering do not apply there. See `git-plugin:git-stacked-prs`.
- The two encoded recipes cited in §1 and §2 are the author's own (a `just -g`
  recipe in `laurigates/dotfiles`, and a sweep script in
  `laurigates/claude-plugins`), not commands a plugin consumer already has. Read
  the authority ladder in §1 as the instruction. The recipe is a convenience, and
  its REVIEW bucket measured ~90% false positives (#2268).
