# pi (pi.dev) skill discovery & local-model orchestration

Run this marketplace's skills inside **pi** ([pi.dev](https://pi.dev),
`@earendil-works/pi-coding-agent`) against a **local model** (mlx_lm.server /
ollama). The sibling of [`opencode-export.md`](opencode-export.md) — same goal
(local-model testing of our skills), a much thinner pipeline.

> **The tier installer is gone (#2093).** Skill discovery is now the
> **ADR-0022 adapter**'s job: `pi/tiers.yaml`, `scripts/install-pi.sh`,
> `scripts/check-pi-tiers.sh` and the `install-pi` / `install-pi-domain` /
> `pi-tiers` / `check-pi-tiers` recipes were removed after the adapter's
> retrieval eval gate was measured and frozen on 2026-07-22
> ([`../adapters/CUTOVER.md`](../adapters/CUTOVER.md)). Nothing needs to be
> copied into `~/.pi/agent/skills/` any more.

## Why pi needs almost no pipeline

pi loads Claude Code `SKILL.md` files **unmodified**. Validated on pi 0.80.6:
pi is *strictly more lenient* than the retired rulesync converter was — it
accepts display-name `name:` values (`UnoCSS`), unprefixed names
(`ground-response`), comma-string `allowed-tools`, and extra frontmatter, all of
which that converter's normalization layer had to rewrite. **None of it was ever
needed for pi**, and since #2094 none of it runs for OpenCode either — both
harnesses now read `SKILL.md` in place through the adapter. pi also reads
`CLAUDE.md` natively and does the same progressive disclosure as Claude Code
(only `name`+`description` surfaced up front; the body loads on demand via
`read` / `/skill:name`).

So the only thing worth building was a way to keep the *listing* affordable.

## The one real gap: pi doesn't budget the skill listing

Claude Code caps the up-front skill-description listing at
`skillListingBudgetFraction × context`. **pi has no such budget** — every
skill it discovers costs ~111 tokens of standing per-turn context (measured, pi
0.80.6), dead linear and uncapped:

| Skills in the listing | Standing cost/turn | On a 128K local context |
|------------------|--------------------|-------------------------|
| ~20 | ~2.2K | negligible |
| 94 | ~10.4K | ~8% — fine |
| ~200 | ~22K | tight |
| all ~400 | ~45K | fatal (401 skills hangs the turn >2min; ≤200 fine) |

On a 1M-context Claude at `skillListingBudgetFraction 0.1` this is invisible; on
a small local quant it wedges the agent.

Two answers were built for this. The **tier installer** (retired) curated a
~95-skill subset into pi's native scopes and paid ~9,900 standing tokens for it,
at the cost of a hand-maintained manifest that restated facts already in the
marketplace. The **adapter** (current) replaces the native listing outright.

## The adapter (ADR-0022)

`adapters/pi/` is a pi extension that strips the native `<available_skills>`
block and injects, in its place, a small set of pins plus a per-turn **ranked
top-k** slice — while exposing a `search_skills` **pull tool** for everything
else. All ~400 skills stay reachable at **~600 standing tokens/turn** instead of
the tier's ~9,900, and there is no curation manifest to drift.

Full documentation — configuration keys, the Trust caveat, the ranker, and the
eval harness — is [`../adapters/README.md`](../adapters/README.md) § pi. Read it
there rather than restating it here.

```
just pi-adapter-check        # prereqs: pi, bun deps, ollama embed model
just pi-adapter              # trial it, ZERO config changes (pi -e <path>)
just pi-adapter-register     # persist into ~/.pi/agent/settings.json extensions[]
just pi-adapter-unregister   # reverse the above
```

`just pi-adapter-register` is idempotent and non-clobbering. Note pi loads local
extensions from `extensions`, **not** the `packages` array `pi install` / `pi
list` manage — so `pi list` will not show it; that is expected, not a failure.

## Pipeline

```
adapters/pi/index.ts ──▶ ~/.pi/agent/settings.json extensions[]  (just pi-adapter-register)
                         (search_skills pull + ranked top-k push, ~600 tok/turn)

mlx_lm.server ──▶ models.json ──▶ pi --model mlx-local/<id>
```

### 1. Wire up skill discovery

```
just pi-adapter-check            # verify prereqs first
just pi-adapter-register         # persistent; or `just pi-adapter` to trial it
```

### 2. Serve the model

```
uv tool install mlx-lm
just serve-pi-model              # mlx_lm.server --model <pi_model> --port 8080
curl -s localhost:8080/v1/models # verify it is up
```

`pi_model` / `pi_port` are overridable (`just pi_model=… serve-pi-model`, or
`PI_MODEL` / `PI_PORT`).

### 3. Point pi at the local endpoint — `~/.pi/agent/models.json`

pi reads custom OpenAI-compatible providers from `~/.pi/agent/models.json`
(re-read on every in-session `/model` switch — no restart needed). For an
mlx_lm.server / ollama endpoint:

```json
{
  "providers": {
    "mlx-local": {
      "baseUrl": "http://localhost:8080/v1",
      "api": "openai-completions",
      "apiKey": "mlx",
      "compat": {
        "supportsDeveloperRole": false,
        "supportsReasoningEffort": false
      },
      "models": [
        {
          "id": "mlx-community/Qwen3.6-35B-A3B-4bit",
          "name": "Qwen3.6 35B A3B 4bit (local)",
          "contextWindow": 128000,
          "maxTokens": 32000,
          "cost": { "input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0 }
        }
      ]
    }
  }
}
```

The `compat` flags matter for local servers: many OpenAI-compatible servers
don't understand the `developer` role reasoning-capable models use
(`supportsDeveloperRole: false` sends the system prompt as a plain system
message), nor `reasoning_effort` (`supportsReasoningEffort: false`).

`just setup-pi` runs the adapter prereq check, registers the adapter, then
prints this block (with your `pi_model` / `pi_port` interpolated) plus the run
command.

### 4. Run pi against the local model

```
cd <project>
pi --model mlx-local/mlx-community/Qwen3.6-35B-A3B-4bit
```

The end-to-end question this answers: does a **small local model actually
invoke** a skill (not merely list it)? That is the real fidelity test — listing
is cheap; a weak quant choosing and reading the right `SKILL.md` on intent is
what makes this useful for local-model testing. The adapter's retrieval quality
on exactly that question is what the eval harness measures
([`../adapters/README.md`](../adapters/README.md) § eval).

## Out of scope (deferred)

- **Agent / prompt / hook porting.** Hooks especially are selective: only the
  *safety* hooks would earn a pi `pi.on` port; the style nudges are noise on a
  different harness.

## Related

- [`../adapters/README.md`](../adapters/README.md) § pi — the adapter (source of truth for skill discovery)
- [`../adapters/CUTOVER.md`](../adapters/CUTOVER.md) — the eval gate that authorized retiring the tier installer
- [`adrs/0022-adapter-over-export-for-foreign-harnesses.md`](adrs/0022-adapter-over-export-for-foreign-harnesses.md) — adapter-over-export decision
- [`opencode-export.md`](opencode-export.md) — the sibling harness: same adapter for skills, plus an agent/hook export pi does not need
- [pi custom-provider docs](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/custom-provider.md) — upstream `models.json` schema
