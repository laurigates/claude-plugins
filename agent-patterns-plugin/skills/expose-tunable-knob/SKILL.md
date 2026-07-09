---
name: expose-tunable-knob
description: Expose a live-adjustable control instead of guessing a magic constant for a parameter the agent cannot itself perceive. Use when tuning visual, audio, or UX output (color, size, position, timing, volume) that only the user can judge.
allowed-tools: Read, Edit, Write, Grep, Glob, Bash(cargo test *), Bash(npm test *), Bash(pytest *)
model: opus
created: 2026-07-08
modified: 2026-07-08
reviewed: 2026-07-08
---

# Expose Tunable Knob

An agent iterating on a **perceptual** parameter — a mask's size, a color
threshold, an animation's timing, an audio gain — hits a hard wall the moment
it can't render, watch, or listen to its own output. A human running a live
webcam feed, a rendered UI, or a mixed audio track can judge instantly whether
a value looks or sounds right; the agent, reasoning purely from code and
possibly one static screenshot, cannot. The naive move — pick a value from
domain reasoning, ship it, wait for feedback, repeat — burns a full
rebuild/re-run/re-report round-trip **per guess**, and the agent's guess still
carries no more information than the human's own eyes would supply directly.

## When to Use This Skill

| Use this skill when... | Skip when... |
|---|---|
| Tuning a value whose correctness is judged by a sense the agent lacks (sight, sound, feel) | The value has an objective, computable correctness criterion (a test asserts the exact number) |
| The user has already pushed back once on a guessed default ("that's better, but...") | This is the first attempt — try a principled default before adding a knob |
| The parameter is genuinely continuous/subjective (position, size, gain, ratio, threshold) | The parameter is binary/structural (a feature flag, an algorithm choice) — that's a decision, not a tuning value |
| The runtime already has (or can cheaply gain) a live control surface — a GUI slider, a config‑reload flag, a CLI `--watch` | Changing the value requires a full redeploy/recompile cycle with no faster path — a knob doesn't help if it's still one guess per round-trip |

## The pattern

1. **Implement the mechanism**, not the magic number. Parameterize whatever
   currently hardcodes the value — a mask's expansion ratio, a debounce delay,
   a color-mix weight — so it reads from config/state rather than a literal.
2. **Pick a reasoned starting default**, not an arbitrary one. Use the best
   available signal: the reference implementation's value, a "just a little
   more than currently" nudge in the diagnosed direction, or a rough
   calculation — record *why* in a doc comment, since the next reader (agent
   or human) needs the reasoning, not just the number.
3. **Expose a live control at the layer the human already interacts with** —
   a UI slider (`egui::Slider`, a web form range input), a hot-reloadable
   config key, a CLI flag re-read per invocation. The requirement is that the
   human can change it and see the result **without asking the agent to
   redo anything**.
4. **Stop guessing values past this point.** Once the knob exists, further
   "should I bump this to 0.3 or 0.4?" turns are wasted — hand the decision to
   the human and move on to the next piece of work.

## Worked example

A Rust live face-swap app's mouth-mask feature pastes the real webcam mouth
back over a swapped face, using a landmark-derived polygon expanded by a
`mouth_mask_size` factor and shifted by a `mouth_mask_offset_y` bias. Neither
value has an objectively correct answer — "does the opening sit between the
lips, and does the boundary look smooth" is answerable only by someone
watching their own live video. Rather than iterating blind (ship a guess →
wait for a screen-recording or description → guess again), the fix:

- parameterized both values in `ProcessingConfig` (mechanism, not constant),
- set defaults reasoned from the *known-wrong* prior value (Python's `1.0`/10%
  padding was empirically too tight; `4.0`/40% was a deliberate, reasoned
  bump, not arbitrary),
- added `egui::Slider` controls ("Mouth Mask Size", "Mouth Mask Position") so
  the user could dial both in during a single `just live` session,

turning what would have been an open-ended sequence of "try 0.3 now" /
"still not quite right, try 0.35" exchanges into one code change plus the
user's own real-time tuning.

## Anti-patterns

- **Silent precision theater**: shipping a value to three decimal places
  (`0.347`) with no note that it's a guess. A guessed value should read as
  a starting point, not settled science — the user needs to know it's
  provisional so they know to check it.
- **Adding a knob nobody can reach.** A config field with no UI/CLI surface
  and a "rebuild to test" cycle is not a knob — it's the same guess-and-wait
  loop with extra steps. The control has to land where the human already is
  (the running app), not one layer removed from it.
- **Knob sprawl.** Not every parameter earns a slider — reserve this for
  values the user has already signaled need iteration (see the "skip when"
  row above). A UI cluttered with tuning knobs for values nobody disputes is
  its own cost.

## Relationship to sibling skills

- `verify-before-plan` — verifies **facts** an orchestrator assumes before
  dispatching work; this skill hands off **judgment** the agent structurally
  cannot make itself. Different gaps, same "don't guess — get the answer from
  the party who actually has it" instinct.
- `mcp-management` / `configure-*` skills often *build* the UI surface
  (sliders, config files) this pattern exposes a value through — this skill
  is about *when* to reach for that surface, not how to wire it.
