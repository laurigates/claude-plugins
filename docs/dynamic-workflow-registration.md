# Registering a dynamic workflow by name

Bundled workflow templates live beside their `SKILL.md`
(`.claude/rules/workflow-vs-skill.md` § "Layout convention"). Exactly **one**
template in this marketplace is *also* registered under a resolvable name, and
this document is the whole of that exception.

| | |
|---|---|
| The one registered template | `evaluate-plugin/skills/evaluate-skill/workflows/evaluate-skill.workflow.js` |
| How it is registered | `"workflows": ["./skills/evaluate-skill/workflows/evaluate-skill.workflow.js"]` in `evaluate-plugin/.claude-plugin/plugin.json` |
| The name it resolves under | `evaluate-plugin:evaluate-skill` (`<plugin>:<meta.name>`) |
| Who resolves it | `evaluate-plugin:evaluate-plugin-batch`'s harness, via `workflow('evaluate-plugin:evaluate-skill', {...})` |
| Everything else | **Not registered.** Bundled only. |

**Register that one and nothing else.** A registered workflow reads as
*runnable* and appears in the skill listing, and these templates are
deliberately incomplete: invoking one against empty `args` spends real agents
to discover it was a template. There is no `meta` field that hides a registered
workflow from the listing. The only thing that earns a registered name is
another harness that has to call it by name, and today there is exactly one
such call site.

## Why a name at all — and the alternatives

The platform supports several ways for one harness to reach another's work.
Weigh them before adding a second registered name.

| Route | Call shape | Cost |
|---|---|---|
| **Plugin-native registration** *(chosen, #3684)* | `workflow('evaluate-plugin:evaluate-skill', args)` | No copy and no install step: the plugin cache is the source, at the installed version. The name carries the `evaluate-plugin:` prefix. |
| User-scope copy *(retired)* | `workflow('evaluate-skill', args)` against `~/.claude/workflows/evaluate-skill.workflow.js` | Needed a SessionStart hook to keep the copy in step (#2829), and put a bare `evaluate-skill` entry in every session's listing in every repo. |
| Script path | `workflow({scriptPath: '<repo>/evaluate-plugin/skills/evaluate-skill/workflows/evaluate-skill.workflow.js'}, args)` | The path must be one the session can already read. The installed plugin cache is not (see below). |
| Slash command per unit | each fan-out agent invokes `/evaluate:skill <plugin>/<skill>` with the `SlashCommand` tool — the pattern `configure-all-check.workflow.js` uses | The child runs as prose inside one agent, so the cell-level fan-out and the schema-forced verdicts are lost. |

`evaluate-plugin-batch` wants the *harness*, not the prose skill, which rules
out the slash-command route. A nested `workflow({scriptPath})` only accepts *a
script path the Workflow tool returned, or a file the session can already read
(the working directory or a directory you have added)*. Probed 2026-09-25 with
zero-agent workflows:

| `scriptPath` target | Result |
|---|---|
| The repo checkout, from a session whose working directory is the checkout | Resolved |
| `~/.claude/plugins/cache/<marketplace>/evaluate-plugin/<version>/…` | Threw the restriction above |
| `~/.claude/workflows/evaluate-skill.workflow.js` | Threw the restriction above |

So the script path works only inside this checkout.

## How plugin-native registration resolves

Claude Code loads plugin workflows from a plugin-root `workflows/` directory,
or from a `plugin.json` `workflows` field (a path, or a list of directories and
`.js` files) that replaces that directory. Each registers as
`<plugin>:<meta.name>`, and a nested `workflow('<name>')` resolves against the
same merged list of saved and plugin workflows
(`.claude/rules/workflow-vs-skill.md` § "Layout convention" tables every
location).

Probed 2026-11-25 on the current release
([#3684](https://github.com/laurigates/claude-plugins/issues/3684)): a minimal
plugin with a two-entry `workflows` list, loaded with `claude --plugin-dir`,
ran a caller workflow that called `workflow('wf-probe:hello', {via: 'caller'})`
and got the nested result back with its args. The probe used a probe plugin
loaded by `--plugin-dir`, not `evaluate-plugin` from a marketplace install;
verify once after the marketplace update with the steps below.

`evaluate-plugin` lists the one file rather than relying on a plugin-root
`workflows/` directory, because its templates live under
`skills/<skill>/workflows/` and only one of them is registered.

The identity is the workflow's **`meta.name`**. Keep `meta.name`
(`evaluate-skill`), the bundled basename, and the `evaluate-skill` part of the
caller's literal in agreement.

### The one project-scope workflow

This repo tracks one file under `.claude/workflows/`,
`model-suitability-audit.workflow.js`. It is not a copy: it is a repo-internal
audit harness with no bundled twin, so it has no drift surface. Sessions in this
checkout can start it by name, and it returns `{abort: true}` before its first
`agent()` call when `args` are empty
(`scripts/tests/test-model-suitability-audit-workflow.sh`).

### Upgrading from the copy hook

Earlier versions copied the template to
`~/.claude/workflows/evaluate-skill.workflow.js` at each session start. Nothing
removes that copy now, and it keeps registering a bare `evaluate-skill` that no
caller uses. Delete it:

```bash
rm -f ~/.claude/workflows/evaluate-skill.workflow.js
```

### Verifying it resolved

There is no CI check for resolution: the registry lives in the session, not the
checkout. Verify by hand from a session with `evaluate-plugin` installed:

1. Check that `evaluate-plugin:evaluate-skill` appears in `/workflows`.
2. Resolve it the way the batch caller does, with **empty** `args`. Run a
   Workflow script whose body is
   `return await workflow('evaluate-plugin:evaluate-skill', {})`; it should
   return `{abort: true, reason: 'missing-skill-dir'}`. That comes from the
   `skillDir` guard in `evaluate-skill.workflow.js`, which returns before the
   first `agent()` call, so the check spawns no agents. An unregistered name
   throws `no workflow with that name` instead.

Pass exactly `{}`. Any non-empty `skillDir`, including a placeholder, gets past
the guard and starts the preflight agent.

## Two platform constraints the caller must design around

**Nesting is one level only.** `workflow()` inside a child **throws**. Since
`evaluate-plugin-batch` is the parent and `evaluate-skill` is the child,
`evaluate-skill.workflow.js` must contain no `workflow()` call at all — it does
not, and its header comment says why so an adapter does not add one.

**`workflow()` throws on an unknown name.** If the registration is missing, the
throw propagates and kills the *entire* batch — not just the one skill it was
evaluating. A caller that fans out over many skills must therefore wrap each
call:

```js
let result
try {
  result = await workflow('evaluate-plugin:evaluate-skill', cellArgs)
} catch (e) {
  // One unresolvable name must not take the sweep down with it. Record the
  // skill as unevaluated so it stays in the denominator, and carry on.
  log(`evaluate-skill did not resolve for ${s.path}: ${e.message}`)
  result = { abort: true, reason: 'workflow-unresolved', skill: s.path }
}
```

A batch that dies on its first skill reports nothing and looks like an
infrastructure failure rather than a missing registration.

The child also **shares the parent's concurrency cap, agent counter, abort
signal and token budget**. That is why `evaluate-skill.workflow.js` imposes no
wave width of its own: a second ceiling inside the child would silently supersede
whatever `--parallel N` the batch caller was given.

## Adding a second registered name

Don't, unless a *second* harness genuinely has to call a template by name. When
that happens:

1. Confirm neither the slash-command nor the script-path route fits.
2. Add the template to the owning plugin's `plugin.json` `workflows` list, and
   to the table at the top of this file with its call site.
3. Update `.claude/rules/workflow-vs-skill.md` § "Layout convention", which
   states the rule as "register a name **only** when another harness must call
   it by name".
4. Extend `scripts/tests/test-evaluate-workflow-registration.sh` or add a
   sibling that pins the new name against its `meta.name`.

## Related

- `.claude/rules/workflow-vs-skill.md` — when a bundled template earns its agents; the layout convention and the registration rule
- `.claude/rules/plugin-structure.md` § "Bundled Workflow Templates" — the same rows in table form
- `.claude/rules/docs-currency.md` — this doc lands in the same commit as the `.js` that depends on it
- `docs/plans/dynamic-workflow-migration.md` — the evaluation that made `evaluate-skill` the one exception
