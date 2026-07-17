# pi (pi.dev) export & local-model orchestration

Run this marketplace's skills inside **pi** ([pi.dev](https://pi.dev),
`@earendil-works/pi-coding-agent`) against a **local model** (mlx_lm.server /
ollama). The sibling of [`opencode-export.md`](opencode-export.md) — same goal
(local-model testing of our skills), a much thinner pipeline.

## Why pi needs almost no pipeline

pi loads Claude Code `SKILL.md` files **unmodified**. Validated this session
(pi 0.80.6): pi is *strictly more lenient* than OpenCode/rulesync — it accepts
display-name `name:` values (`UnoCSS`), unprefixed names (`ground-response`),
comma-string `allowed-tools`, and extra frontmatter, all of which the OpenCode
export's `rewrite-skill-name-to-dir.py` / `normalize-skill-allowed-tools.py`
layer had to rewrite. **None of that normalization is needed for pi.** pi also
reads `CLAUDE.md` natively and does the same progressive disclosure as Claude
Code (only `name`+`description` surfaced up front; the body loads on demand via
`read` / `/skill:name`), so there is no separate search tool to build.

So the only thing worth building is a **curated installer**, not an export
pipeline.

## The one real gap: pi doesn't budget the skill listing

Claude Code caps the up-front skill-description listing at
`skillListingBudgetFraction × context`. **pi has no such budget** — every
installed skill costs ~111 tokens of standing per-turn context (measured, pi
0.80.6), dead linear and uncapped:

| Installed skills | Standing cost/turn | On a 128K local context |
|------------------|--------------------|-------------------------|
| ~20 | ~2.2K | negligible |
| 94 (Tier-1 general) | ~10.4K | ~8% — fine |
| ~200 | ~22K | tight |
| all ~400 | ~45K | fatal (401 skills hangs the turn >2min; ≤200 fine) |

On the user's 1M-context Claude at `skillListingBudgetFraction 0.1` this is
invisible; on a small local quant it wedges the agent. **Conclusion: don't dump
all skills into pi.** Curate by *tier* using pi's two native scopes.

## Tiers → pi's two native scopes

pi discovers skills from `~/.pi/agent/skills/` (global) **and** `.pi/skills/`
(per-project) and merges them. That maps cleanly onto a tier model:

| Tier | pi scope | Meaning |
|------|----------|---------|
| `general` | `~/.pi/agent/skills/` | Always-on, every project. Keep lean (94 skills ≈ 10.4K tok/turn). |
| `domain` | `.pi/skills/` | Installed only in a matching project type, by `category`. |
| `exclude` | never installed | Claude-Code-authoring meta (hooks, blueprint, agent orchestration): pure budget waste in pi. |

The classification is the single source of truth in
[`../pi/tiers.yaml`](../pi/tiers.yaml) — **read it there**, don't restate the
assignments here. Its header block documents the schema (`tier`, optional
`skills:` cherry-pick, `category`, `reason`). Large general plugins (e.g.
git-plugin) cherry-pick a core subset via the `skills:` list rather than
installing every skill.

The manifest is enforced by `scripts/check-pi-tiers.sh` (wired into
`.pre-commit-config.yaml` and the `Plugin: PR checks` workflow): every
marketplace plugin is classified exactly once, and every cherry-picked skill
name resolves to a real `SKILL.md`.

## Pipeline

```
pi/tiers.yaml ──▶ install-pi.sh ──▶ ~/.pi/agent/skills/   (general → global)
                              └────▶ <project>/.pi/skills/ (a domain → project)
                     mlx_lm.server ──▶ models.json ──▶ pi --model mlx-local/<id>
```

### 1. Install the curated skills

```
just pi-tiers                    # print the install plan (no writes)
just install-pi                  # general tier → ~/.pi/agent/skills/
just install-pi-domain infra     # an infra project's domain tier → .pi/skills/
```

`install-pi.sh` copies additively (existing skills under the target are
preserved) and drops a `.claude-plugins-pi-receipt`. Flags: `--scope
global|project`, `--category <cat>`, `--dry-run`, `--list`. Env overrides
`PI_HOME` (default `~/.pi/agent`) and `PI_PROJECT_DIR` (default `$PWD`) exist for
tests / non-standard layouts.

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

`just setup-pi` runs `install-pi` then prints this block (with your `pi_model` /
`pi_port` interpolated) plus the run command.

### 4. Run pi against the local model

```
cd <project>
pi --model mlx-local/mlx-community/Qwen3.6-35B-A3B-4bit
```

The end-to-end question this answers: does a **small local model actually
invoke** a skill (not merely list it)? That is the real fidelity test — listing
is cheap; a weak quant choosing and reading the right `SKILL.md` on intent is
what makes this useful for local-model testing.

## Out of scope (deferred)

- **A `skill-search` pi extension** (a `search_skills` tool + suppressed default
  injection). ~~Only worth building if the trimmed Tier-1 general set still feels
  tight on the smallest local quant. The tier manifest is the cheaper,
  deterministic answer — defer the extension.~~ **Un-deferred by
  [ADR-0022](adrs/0022-adapter-over-export-for-foreign-harnesses.md)**: the
  extension (now a binding over a harness-agnostic discovery core, #2090) is
  slated to *supersede* the tier system entirely; the tier pipeline documented
  here is removed once the adapter passes its eval gate (#2093).
- **Agent / prompt / hook porting.** Hooks especially are selective: only the
  *safety* hooks would earn a pi `pi.on` port; the style nudges are noise on a
  different harness.

## Related

- [`../pi/tiers.yaml`](../pi/tiers.yaml) — the tier classification (source of truth)
- [`opencode-export.md`](opencode-export.md) — the sibling local-model export (heavier rulesync pipeline)
- [pi custom-provider docs](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/custom-provider.md) — upstream `models.json` schema
