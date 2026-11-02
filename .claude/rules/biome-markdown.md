---
created: 2026-11-02
modified: 2026-11-02
reviewed: 2026-11-02
paths:
  - "**/biome.json"
  - "**/biome.jsonc"
  - "foundryvtt-plugin/skills/foundryvtt-module-scaffold/scaffold.py"
---

# Biome ≥ 2.6 Formats Markdown — Keep It Off Here

Biome 2.6 added a Markdown formatter and linter that are **on by default**. Any
biome config whose `files.includes` reaches `.md` files starts failing
`biome ci` / `biome check` on the next minor bump, with no config change in
the PR. This shows up in Renovate PRs as "File content differs from
formatting output" on files the PR never touched.

The formatter does not parse YAML frontmatter. On the adapter test fixtures
(#3352) it:

- rewrote a frontmatter block into a `## description:` heading;
- flattened a `>-` folded scalar, changing the parsed value;
- column-padded every table. In a generated file the padding depends on the
  module id, so no template can satisfy it (#3374).

`biome check --write` on those files therefore changes what the tests read.
Never accept the auto-fix on a fixture or a SKILL.md.

## The rule

Every biome config in this repo, and every one a scaffold emits, carries:

```json
"markdown": { "formatter": { "enabled": false }, "linter": { "enabled": false } }
```

Markdown here is linted by the repo's own tooling, not biome. When a biome bump
fails on `.md` files, add this block. Reformatting the files is not a fix, and
running `biome migrate` alone doesn't fix it either: it only updates the
`$schema` URL.

| Config | Status |
|---|---|
| `adapters/biome.json` | off since #3352 |
| `foundryvtt-plugin/templates/foundryvtt-module/biome.json` + `scaffold.py` `BIOME_JSON` | open: #3374 |
