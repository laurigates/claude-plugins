# session-distill — Distill Collector Digest

Consume the digest:

- `RECIPE_CANDIDATES` — normalized commands that recurred across **separate**
  sessions or are commit-bracketed this session, are NOT already a `just`
  recipe or churn (`status`/`diff`/`log`/`test`/`build`/`ls`/…), are NOT a
  compound/loop line (`;`, `&&`, `||`, `until`/`while`/`for` — those are
  `--process` material), and carry a **stable argument**: either no
  placeholder at all, or one standalone placeholder that resolved to the same
  concrete value in ≥2 sessions (a placeholder embedded in a flag —
  `--title=<str>` — can never prove stability, so those shapes are always
  dropped). Each carries a concrete `_FIRST` example, `_SESSIONS`
  count, `_NOVEL_TOKENS`, and `_STABLE_ARGS` (up to three repeated values,
  sorted, or `literal`). A low count is the honest answer, not a broken collector.
- `HOT_FILES` — the files this session edited/wrote most (exact paths) — where
  rule/doc updates likely land.
- `COMMIT_INTERVALS` + `COMMAND_DIGEST` — the mechanical grouping you use to
  *name* a process or sequence. The script never infers a sequence itself
  (sequence-naming is judgment); it hands you completed-work intervals.
- `RULE_HINTS_FROM_TOOLING` — repeated permission/auth denials, the **only**
  mechanical rule signal.

Under pi, the collector falls back to the transcript named by `PI_SESSION_FILE`
and reports `TRANSCRIPT_FORMAT=pi`. pi records no permission denials, so its
`RULE_HINTS_FROM_TOOLING` carries `RULE_HINTS_RECORDED=false`: a zero there
means "not recorded", not "none".
