# Plugin Flow Diagrams

Codifies when a plugin earns a Mermaid flow diagram, where it lives, and what conventions to follow.

Canonical example: [`health-plugin/docs/flow.md`](../../health-plugin/docs/flow.md).

## When to add a diagram

Add `docs/flow.md` if **any** of the following apply:

- **Router / delegation pattern** — one skill orchestrates others (e.g. `/health:check` → scope-specific sub-skills)
- **Ordered pipeline** — skills have real sequencing (A → B → C), not just coexistence
- **>15 skills** where visual grouping meaningfully clarifies scope
- **Cross-skill integration** worth showing — shared artefacts, data handoffs, conditional branches

## When NOT to add a diagram

Skip if the plugin is a flat collection of independent tools. The README's Skills table **is** the diagram.

Examples of flat bags (no diagram): `tools-plugin`, `python-plugin`, `rust-plugin`, `typescript-plugin`, `networking-plugin`, `obsidian-plugin`, `home-assistant-plugin`, `finops-plugin`, `testing-plugin`, `container-plugin`, `kubernetes-plugin`, `css-plugin`, `api-plugin`, `documentation-plugin`, `accessibility-plugin`, `migration-patterns-plugin`, `communication-plugin`, `prose-plugin`, `bevy-plugin`, `code-quality-plugin`, `langchain-plugin`, `github-actions-plugin`, `agent-patterns-plugin`, `component-patterns-plugin`, `blog-plugin`.

A bad diagram (boxes without flow) is worse than no diagram.

## Location and format

- Path: `<plugin>/docs/flow.md`
- Diagram type: Mermaid `flowchart TD`
- Include a **Legend** table and a **scope → skill mapping** table beneath the diagram

## Node colour conventions

Use Mermaid `classDef` with these semantics:

| Class | Fill | Meaning |
|-------|------|---------|
| `router` | Blue (`#4a9eff`) | Top-level orchestrating skill |
| `check` | Green (`#8fbc8f`) | Read-only diagnostic / analysis |
| `fix` | Orange (`#ffa500`) | Writes files / mutates state |
| `prompt` | Purple (`#dda0dd`) | Interactive `AskUserQuestion` prompt |

Copy the `classDef` block from `health-plugin/docs/flow.md` verbatim and assign only the classes that apply.

## Linking from the README

Add an **Overview** (or **Flow**) section near the top of the plugin README:

```markdown
## Flow

See [`docs/flow.md`](docs/flow.md) for a diagram of how the skills fit together.
```

## Drift warning

These diagrams are **not** CI-tested. Keep them coarse enough that adding or removing a single skill rarely invalidates the diagram — group fine-grained skills under a single node rather than drawing every skill individually. Prefer capturing *the pattern* over *every skill*.
