# Registering a dynamic workflow by name

Bundled workflow templates live beside their `SKILL.md`
(`.claude/rules/workflow-vs-skill.md` § "Layout convention"). Exactly **one**
template in this marketplace is *also* registered under a resolvable name, and
this document is the whole of that exception.

| | |
|---|---|
| The one registered template | `evaluate-plugin/skills/evaluate-skill/workflows/evaluate-skill.workflow.js` |
| The name it must resolve under | `evaluate-skill` |
| Who resolves it | `evaluate-plugin:evaluate-plugin-batch`'s harness, via `workflow('evaluate-skill', {...})` |
| Everything else | **Not registered.** Bundled only. |

**Register that one and nothing else.** A file in `~/.claude/workflows/` reads
as *runnable*, and these templates are deliberately incomplete — invoking one
against empty `args` spends real agents to discover it was a template. The only
thing that earns a registered name is another harness that has to call it by
name, and today there is exactly one such call site.

## Why a name at all — and the two alternatives that do not need one

The platform supports three ways for one harness to reach another's work. Weigh
them before adding a second registered name; two of them need no registry.

| Route | Call shape | Cost |
|---|---|---|
| **Registered name** *(chosen)* | `workflow('evaluate-skill', args)` | Needs a saved copy outside the repo. Throws on an unknown name. |
| Script path | `workflow({scriptPath: '<repo>/evaluate-plugin/skills/evaluate-skill/workflows/evaluate-skill.workflow.js'}, args)` | No registry, but hardcodes a cross-plugin path into `evaluate-plugin-batch`, which then breaks if either skill moves or if only one plugin is installed. |
| Slash command per unit | each fan-out agent invokes `/evaluate:skill <plugin>/<skill>` with the `SlashCommand` tool — the pattern `configure-all-check.workflow.js` uses | No registry and no path, but the child runs as prose inside one agent, so the cell-level fan-out and the schema-forced verdicts are lost. |

The name was chosen because `evaluate-plugin-batch` wants the *harness*, not the
prose skill, and a cross-plugin filesystem path is exactly the kind of reference
`.claude/rules/skill-consolidation.md` § 2 rules out (a relative path is dead for
anyone who installed one plugin without the other). If registration ever proves
unreliable in practice, the script-path route is the documented fallback — it is
a supported platform input, not a workaround.

## Where a registered workflow lives

Two scopes, same mechanism:

| Scope | Directory | Applies to |
|---|---|---|
| User | `~/.claude/workflows/` | every session for that user |
| Project | `<repo>/.claude/workflows/` | sessions whose working directory is in that project |

With nested `.claude/` directories the workflow **closest to the working
directory wins** on a name collision, and project-scope saves target the closest
existing `.claude/workflows/` (Claude Code 2.1.178 — see
`.claude/rules/agent-development.md`). So a project-scoped
`evaluate-skill` would shadow a user-scoped one of the same name rather than
merging with it.

**This repo does not commit a `.claude/workflows/` copy**, and deliberately so:
the bundled `workflows/*.workflow.js` file is the single source of truth, and a
second committed copy would be a fleet-drift surface with nothing keeping the two
in step (`.claude/rules/generated-fleet-drift.md`). Registration is an
**install-time** act performed against a checkout, not a second tracked file.

## Installing the registration

Neither directory exists by default (verified 2026-09-20: `~/.claude/workflows`
and `<repo>/.claude/workflows` were both absent on a clean machine). Create it
and copy the bundled template in, keeping the **basename in step with
`meta.name`**:

```bash
mkdir -p ~/.claude/workflows
cp evaluate-plugin/skills/evaluate-skill/workflows/evaluate-skill.workflow.js \
   ~/.claude/workflows/evaluate-skill.workflow.js
```

The identity that `workflow('evaluate-skill', …)` resolves is the workflow's
**`meta.name`**, which is why that field is load-bearing rather than cosmetic and
why the bundled file is named `evaluate-skill.workflow.js` rather than after some
other purpose slug. Keep the three in agreement — `meta.name`, the bundled
basename, and the installed basename — and the question of which one the registry
keys on never has to be answered.

### Verifying it resolved

There is no lint for this in the repo, and there cannot usefully be one: the
registry lives outside the checkout, so a CI job would be asserting something
about the runner's home directory. Verify it by hand, in this order:

1. `ls ~/.claude/workflows/evaluate-skill.workflow.js` — the file is installed.
2. `grep -n "name: 'evaluate-skill'" ~/.claude/workflows/evaluate-skill.workflow.js`
   — the installed copy declares the name the caller uses.
3. `diff evaluate-plugin/skills/evaluate-skill/workflows/evaluate-skill.workflow.js ~/.claude/workflows/evaluate-skill.workflow.js`
   — the installed copy has not drifted from the bundled source of truth. Re-run
   this after any edit to the bundled file; a stale registered copy is a silent
   fork.
4. In a session, check that `evaluate-skill` appears in `/workflows`.

Do **not** verify it by invoking the workflow. It is a template: running it
against empty or placeholder `args` spends real opus agents to discover that.

## Two platform constraints the caller must design around

**Nesting is one level only.** `workflow()` inside a child **throws**. Since
`evaluate-plugin-batch` is the parent and `evaluate-skill` is the child,
`evaluate-skill.workflow.js` must contain no `workflow()` call at all — it does
not, and its header comment says why so an adapter does not add one.

**`workflow()` throws on an unknown name.** If the registration is missing, the
throw propagates and kills the *entire* batch — not just the one skill it was
evaluating. A caller that fans out over many skills must therefore either wrap
each call:

```js
let result
try {
  result = await workflow('evaluate-skill', cellArgs)
} catch (e) {
  // One unresolvable name must not take the sweep down with it. Record the
  // skill as unevaluated so it stays in the denominator, and carry on.
  log(`evaluate-skill did not resolve for ${s.path}: ${e.message}`)
  result = { abort: true, reason: 'workflow-unresolved', skill: s.path }
}
```

…or fall back to the script-path route above. Either is acceptable; silently
letting the throw escape is not, because a batch that dies on its first skill
reports nothing and looks like an infrastructure failure rather than a missing
install step.

The child also **shares the parent's concurrency cap, agent counter, abort
signal and token budget**. That is why `evaluate-skill.workflow.js` imposes no
wave width of its own: a second ceiling inside the child would silently supersede
whatever `--parallel N` the batch caller was given.

## Adding a second registered name

Don't, unless a *second* harness genuinely has to call a template by name. When
that happens:

1. Confirm neither alternative in the table above fits — a slash command or a
   script path is cheaper and carries no install step.
2. Add the template to the table at the top of this file, with its call site.
3. Update `.claude/rules/workflow-vs-skill.md` § "Layout convention", which
   currently states the rule as "register a name **only** when another harness
   must call it by name".
4. Extend the install snippet and the verification steps above.

## Related

- `.claude/rules/workflow-vs-skill.md` — when a bundled template earns its agents; the layout convention and the global-registration rule
- `.claude/rules/plugin-structure.md` § "Bundled Workflow Templates" — the same four rows in table form
- `.claude/rules/agent-development.md` § Dynamic Workflows — the nested-`.claude/` closest-wins resolution note
- `.claude/rules/docs-currency.md` — this doc lands in the same commit as the `.js` that depends on it
- `docs/plans/dynamic-workflow-migration.md` — the evaluation that made `evaluate-skill` the one exception
