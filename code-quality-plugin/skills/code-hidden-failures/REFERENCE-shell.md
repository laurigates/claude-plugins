# Reference — Shell / Bash Error Swallowing

Detection and classification rules for shell scripts (`*.sh`, `*.bash`,
`Makefile` recipes). Paired scanner: `scripts/scan-shell.sh`.

## Patterns

| ID | Pattern | Raw risk |
|----|---------|----------|
| `sh-or-true` | `<cmd> \|\| true` / `<cmd> \|\| :` | Suppresses non-zero exit silently |
| `sh-stderr-null` | `<cmd> 2>/dev/null` | Hides diagnostic output; may hide real failure |
| `sh-both-null` | `<cmd> &>/dev/null` / `<cmd> >/dev/null 2>&1` | Hides stdout AND stderr |
| `sh-set-plus-e` | `set +e` without a matching `set -e` | Disables fail-fast for the rest of the script |
| `sh-trap-empty` | `trap '' ERR` / `trap - ERR` | Removes the error trap |
| `sh-no-pipefail` | Script without `set -o pipefail` that uses pipes | Silently ignores mid-pipeline failures |
| `sh-missing-check` | `command` at top level without `|| exit` on a High-severity op | No reaction to failure |
| `sh-xtrace-suppression` | `{ cmd; } 2>/dev/null` wrapping xtrace output | Hides debugging stream |

## Allowlist (classify as Low)

These patterns are documented and intentional. See
`.claude/rules/shell-scripting.md` §"Error Handling" (lines 135–162).

| Pattern | Why allowed |
|---------|-------------|
| `grep -m1 '^field:' \| sed '...' \|\| true` | Frontmatter extraction; missing field is expected |
| `grep -m1 '^field:' \| sed '...' \|\| echo ""` | Same; explicit empty default |
| `rm -f <tmp>` without check | `-f` already suppresses missing-file error by design |
| `mkdir -p <dir>` | `-p` already idempotent |
| `command -v <tool> >/dev/null 2>&1` | Testing presence, output irrelevant |
| `test -f <path> \|\| <default>` | Conditional guard, not suppression |
| `2>/dev/null` inside a `find` predicate | Silences permission-denied on probes |

Additionally, the scanner treats a line as Low when it is inside a function
whose name starts with `extract_`, `probe_`, `has_`, `is_`, or `check_` —
these are probe helpers where suppression is the idiom.

## Severity assignment

Start from the default severity per pattern below, then promote to **High**
if the suppressed command matches the High operation regex; demote to
**Low** if the allowlist matches.

| Pattern | Default |
|---------|---------|
| `sh-or-true` | Medium |
| `sh-stderr-null` | Medium |
| `sh-both-null` | Medium |
| `sh-set-plus-e` | Medium |
| `sh-trap-empty` | Medium |
| `sh-no-pipefail` | Low |
| `sh-missing-check` | Medium |
| `sh-xtrace-suppression` | High |

### High-operation regex (any match promotes to High)

```
(npm publish|yarn publish|pnpm publish|cargo publish|gh release|
 git push|git tag|docker push|helm upgrade|kubectl apply|
 terraform apply|aws s3 cp|aws s3 sync|rclone copy|
 psql.*INSERT|psql.*UPDATE|psql.*DELETE|psql.*DROP|
 curl.*POST|curl.*PUT|curl.*DELETE|
 rm -rf)
```

## Remediation templates

### Replace `cmd || true` (CLI context)

```bash
# Before
dangerous_cmd || true

# After
if ! dangerous_cmd; then
  echo "warn: dangerous_cmd failed (continuing)" >&2
fi
```

### Replace `cmd 2>/dev/null` (CLI context, High)

```bash
# Before
dangerous_cmd 2>/dev/null

# After — capture and surface
err=$(dangerous_cmd 2>&1 >/dev/null) || {
  echo "error: dangerous_cmd: ${err:0:200}" >&2
  exit 1
}
```

### Replace `set +e`

Prefer a targeted `|| handler` on the single command that needs to tolerate
failure, and keep `set -e` active elsewhere.

## Scanner notes

`scripts/scan-shell.sh` implements these rules. Its output format is
pipe-delimited for machine parsing:

```
<severity>|<rule>|<file>:<line>|<content>|<recommended-surface>
```

Exit codes:

- `0`: no Medium/High findings (Low tolerated)
- `1`: Medium findings present
- `2`: High findings present
