# foundryvtt-module-scaffold: cargo-generate template (pilot)

### Alternative: the cargo-generate template (pilot)

`templates/foundryvtt-module/` is a cargo-generate port of `scaffold.py` whose
emitted files are real files (so `tsc`/`biome`/`actionlint` can check them)
rather than Python strings. Output is byte-identical, enforced by
`scripts/tests/test-template-parity.sh`.

**`scaffold.py` remains the default.** Reach for the template to edit the
scaffold itself, or to try the flow before it is promoted:

```sh
cargo generate --path ${CLAUDE_SKILL_DIR}/../../templates/foundryvtt-module --name foundryvtt-initiative-tweaks --vcs none --define 'display_name=Initiative Tweaks' --define 'description=…' --define variant=basic
```

Needs `cargo-generate` locally — not in the base image, and the main cost of the
port. CI installs it from the release tarball so the parity gate actually runs
(#2221). See [`templates/README.md`](../../../templates/README.md)
for the comparison, the one deliberate divergence (a non-kebab-case name), the
Liquid brace-collision fixes, and what promoting the template would take.
