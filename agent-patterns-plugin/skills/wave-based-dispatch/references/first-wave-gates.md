# Wave-Based Dispatch — First-Wave Gates

Moved verbatim from [SKILL.md](../SKILL.md). Open when deciding what wave 1 must
be: a research probe (downstream scope is unknown) or a pilot (the same change
will be applied to N items).

## The Research-Before-WO Gate

When the scope of a downstream WO depends on information that only a tool
run can produce — Ghidra decomp, a live API trace, the actual structure
of a binary format, a benchmark — run that probe as **its own first wave**
before the implementation WO is written.

The reason is concrete: the implementation WO's *size* collapses once
the probe lands. A WO scoped as "unknown — possibly days, depends on the
binary's actual layout" turns into "plumb a known pointer from offset
0x40 to the existing decoder, hours" once the research wave produces a
spec artefact. Writing the brief before the research lands locks in the
worst-case framing and the agent burns its window re-deriving the
information.

Process:

1. Wave 1 brief asks the probe agent to write findings to gitignored
   scratch (`tmp/research/format-spec.md`, `tmp/decomp/strings.txt`,
   `tmp/api/probe-results.json`).
2. Probe agent returns a Return Contract that lists the artefact paths.
3. Implementation WO is written **after** wave 1 closes, citing those
   paths verbatim and forbidding re-running the probe.
4. If the artefacts are insufficient, the implementation agent returns
   `partial` with the missing question in `Orchestrator action needed`,
   and the orchestrator dispatches a follow-up probe wave rather than
   letting the implementation agent improvise.

See `agent-patterns-plugin:exclusive-lock-dispatch` when the probe tool
holds an exclusive lock — the pre-dump mechanics there are the right
shape for the research wave's brief.

## The Pilot-Before-Fan-Out Gate

When the **same transformation** will be applied to N items (repos, files,
packages, services), validate the whole recipe on **one representative
pilot end-to-end — including the riskiest unknown — before fanning out**.
Wave 1 is the pilot; wave 2 is the fan-out, and it *mirrors* the landed
pilot rather than re-deriving the recipe N times in parallel.

The reason is concrete: a parallel fan-out over an unvalidated recipe
multiplies a single wrong assumption into N broken outputs, and you pay
for all N before discovering the flaw. Proving it once converts the
fan-out agents' job from "figure out how" to "replicate this exact,
working example" — which is both cheaper and far more reliable.

Process:

1. **Wave 1 = the pilot.** Pick the *simplest representative* item. Do
   the full transformation, and explicitly confirm the **load-bearing
   unknown** — the one thing that, if it didn't work, would invalidate
   the entire approach (a build externalization, an API contract, a
   migration codemod's output).
2. **Gate.** The pilot's own gates (build/test/lint) must pass **and**
   the risky unknown must be confirmed before any fan-out brief is
   written.
3. **Wave 2 = the fan-out.** Each agent is told to mirror the landed
   pilot — cite its path verbatim as the reference implementation — with
   per-item detection only for the parts that genuinely vary.
4. **If the pilot reveals the approach is wrong, re-plan.** Cheap,
   because only one item was touched.

Distinct from [the Research-Before-WO Gate](#the-research-before-wo-gate): research produces a
*spec / artefact* to scope an unknown ("what should we build?"); a pilot
produces a *working reference implementation* of a repeatable change
("we know what to build — is the recipe sound, and does the risky step
actually work?"). Reach for research when the scope is unknown; reach for
a pilot when the scope is known but the recipe is unproven.
