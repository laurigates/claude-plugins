# Channel J sample — selection rule and what it leaves out

Ten units, two independent judges each (20 judgments). Selection was fixed
before judging and is recorded here so the sample cannot be rationalised
after the fact.

`.claude/rules/skill-evaluation.md` Principle 3 is the precedent: judge a small
stratified canary set, not all 407 skills. The canaries are the weathervane —
when they move, sweep the long tail.

## Selection

| # | Unit | Why it is in the sample |
|---|---|---|
| 1 | `testing-plugin/skills/test-tier-selection` | Channel M's most constraint-dense skill — the sharpest C1 test |
| 2 | `agent-patterns-plugin/skills/meta-context-diet` | Second-densest **and** a large single-file body; also the repo's own context-trimming skill, so it is the fairest place to ask whether we take our own advice |
| 3 | `agent-patterns-plugin/skills/parallel-agent-dispatch` | Largest skill body in the marketplace — the sharpest C3 test |
| 4 | `configure-plugin/skills/configure-claude-plugins` | Second-largest, and flat (no supporting files at all) |
| 5 | `comfyui-plugin/skills/comfy-node` | Half its content is shared with a skill in a different plugin — the sharpest C4 test |
| 6 | `git-plugin/skills/git-commit` | Archetype: convention-enforcer, high-traffic, small body |
| 7 | `configure-plugin/skills/configure-security` | **Control.** Three disclosure levels, zero constraint markers. If the rubric cannot score this well, the rubric is broken |
| 8 | `CLAUDE.md` | The always-loaded root — the unit the post's headline claim is actually about |
| 9 | `.claude/rules/agent-coworker-detection.md` | Largest unscoped rule (~16K chars on every turn) |
| 10 | `.claude/rules/terminology.md` | A glossary on the always-loaded surface — the most direct test of the "don't state the obvious" anchor |

Units 1–5 come from Channel M's ranked output; 6 and 7 are archetype and
control; 8–10 are the always-loaded surface. Judges never saw why a unit was
selected, nor any Channel M number.

## What this sample does not cover

Stated explicitly rather than left as an implied "we looked at everything":

- **Archetypes dropped for budget:** file-generator (`comfyui-node-scaffold`)
  and `AskUserQuestion`-driven skills (`configure-gitattributes`). Both were on
  the shortlist and were cut to hold the run at 20 judgments.
- **397 of 407 skills were never judged.** Channel M covers all of them; Channel
  J covers ten. Any claim about the long tail in the report is a Channel M claim.
- **`comfy-node`'s overlap partner** (`foundryvtt-plugin/skills/foundryvtt-module`)
  was not judged. The C4 finding is therefore one-sided by construction: it
  establishes that the duplication exists, not which copy should survive.
- **Only 2 judges per unit.** A median of two cannot separate "judges agree" from
  "judges are correlated"; disagreement is reported per unit rather than smoothed
  away.

## Blinding

The prior benchmark blinded artifacts into `side-A`/`side-B` because it was a
head-to-head between two repos. This run is a single-repo audit — there is no
opposing side to conceal, so **A/B blinding does not apply**. What replaces it:

| Concealed from judges | Why |
|---|---|
| All Channel M output (`metrics.json`) | Prevents anchoring judgments to the mechanical proxies the report keeps separate |
| Other judges' files | Independence of the two scores per unit |
| `skill-quality.md`, `skill-development.md`, `skill-evaluation.md` | These are the house standards under test; they must not become the yardstick |
| The selection rule above | Prevents "this was picked as an offender, so score it low" |

**Known leak, not concealable:** this repo injects `CLAUDE.md` and the twelve
unscoped rules into *every* agent's context automatically, and `skill-quality.md`
is path-scoped to `**/SKILL.md`, so it may attach when a judge opens a skill.
Each judgment therefore carries a `leakage` self-report, and the report
publishes what leaked rather than claiming clean isolation.
