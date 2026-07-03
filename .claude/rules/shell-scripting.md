---
created: 2026-01-18
modified: 2026-03-02
reviewed: 2026-03-02
requires: bash 5+
paths:
  - "**/*.sh"
  - "scripts/**"
---

# Shell Scripting Patterns

Safe, portable shell scripting patterns for use in skills and commands.

## Reserved Variable Names

These variables are read-only or have special meaning in bash/zsh. Use prefixed alternatives instead.

| Reserved | Shell | Reason | Use Instead |
|----------|-------|--------|-------------|
| `status` | zsh | Read-only exit status | `item_status`, `doc_status` |
| `name` | both | Common collision | `item_name`, `file_name` |
| `type` | both | Common collision | `item_type`, `doc_type` |
| `path` | both | Common collision | `file_path`, `doc_path` |
| `PWD` | both | Read-only current directory | - |
| `OLDPWD` | both | Read-only previous directory | - |
| `UID` | both | Read-only user ID | - |
| `EUID` | both | Read-only effective user ID | - |
| `PPID` | both | Read-only parent process ID | - |
| `RANDOM` | both | Special, generates random numbers | - |
| `SECONDS` | both | Special, time since shell start | - |
| `LINENO` | both | Special, current line number | - |
| `HISTCMD` | both | Read-only history number | - |
| `HOSTNAME` | both | May be read-only | - |
| `HOSTTYPE` | both | May be read-only | - |
| `OSTYPE` | both | May be read-only | - |

**Convention**: Prefix variables with descriptive context (e.g., `prp_`, `adr_`, `doc_`).

## YAML Frontmatter Extraction

### Standard Pattern

Use this consistent pattern for extracting YAML frontmatter fields:

```bash
# Safe frontmatter field extraction
# Pattern: grep for field at start of line, extract value, trim whitespace
extract_field() {
  local file="$1"
  local field="$2"
  head -50 "$file" | grep -m1 "^${field}:" | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r'
}

# Usage
doc_status=$(extract_field "$file" "status")
confidence=$(extract_field "$file" "confidence")
```

### Inline Extraction (for loops)

```bash
# Safe inline extraction - prefix all variables
for prp in docs/prps/*.md; do
  prp_name=$(basename "$prp")
  prp_status=$(head -50 "$prp" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//')
  prp_confidence=$(head -50 "$prp" | grep -m1 "^confidence:" | sed 's/^[^:]*:[[:space:]]*//')
  echo "$prp_name | $prp_status | $prp_confidence"
done
```

### Key Patterns

| Purpose | Pattern |
|---------|---------|
| First match only | `grep -m1` |
| Case-insensitive | `grep -im1` |
| Anchor to line start | `^fieldname:` |
| Extract value after colon | `sed 's/^[^:]*:[[:space:]]*//'` |
| Limit to frontmatter | `head -50` (generous) or `head -20` (strict) |
| Remove carriage returns | `tr -d '\r'` |

### Multi-Value Fields (Arrays)

For YAML arrays like `related:`, extract and parse separately:

```bash
# Extract array items (assumes - prefix format)
get_array_field() {
  local file="$1"
  local field="$2"
  awk -v field="$field" '
    /^---$/ { in_front = !in_front; next }
    in_front && $0 ~ "^"field":" { capture = 1; next }
    capture && /^[[:space:]]*-/ { gsub(/^[[:space:]]*-[[:space:]]*/, ""); print }
    capture && /^[a-z]/ { exit }
  ' "$file"
}

# Usage
related_items=$(get_array_field "$file" "related")
```

## Hook Script Conventions

### Error Handling Flags

All hook scripts must include `set -euo pipefail` after the shebang and comment block. Exception: logging/observability hooks may use `set -uo pipefail` (omit `-e`) with a comment explaining why.

#### `pipefail` + `producer | head` aborts on SIGPIPE (exit 141)

A multi-section diagnostic/collector script (each section runs a check, emits a
result, and the script must reach the *next* section regardless) should use
`set -u` alone — **not** `set -euo pipefail`. Under `pipefail`, any
`producer | head -N` pipeline where `head` closes the pipe early sends the
producer `SIGPIPE`; `pipefail` then reports the pipeline as exit **141**
(128 + 13), and `set -e` aborts the whole script mid-run. `ps -Aeo … | head -21`
is the canonical trigger — `ps` keeps writing after `head` has its 21 lines.

```bash
# Wrong for a run-every-section collector: first `| head` SIGPIPE kills the run
set -euo pipefail
top="$(ps -Aeo pid,pcpu,comm -r | head -21)"   # ps → SIGPIPE → pipefail 141 → abort

# Right: -u only; a single failing section can't abort the rest
set -u
top="$(ps -Aeo pid,pcpu,comm -r | head -21)"   # pipeline returns head's 0
```

This is distinct from hook scripts, which *should* fail fast — the rule is
**match the flags to the script's job**: fail-fast tools want `-e`; a diagnostic
that emits its own PASS/WARN/FAIL per section wants to run every section, so drop
`-e`/`pipefail` and guard only unset vars.

### Block Function

Hook scripts that block tool use (exit code 2) must use a standard `block()` function:

```bash
block() {
    echo "$1" >&2
    exit 2
}
```

Do not use variants like `block_error()`, `block_with_reminder()`, or inline `echo >&2; exit 2`.

### Variable Naming

Use `TOOL_NAME` (not `TOOL`) when extracting the tool name from hook input:

```bash
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
```

### Lint Script

Run `bash scripts/lint-shell-scripts.sh` to validate all scripts comply with these conventions. Use `--fix` to auto-fix shebang issues.

### Suppressing shellcheck findings

A **file-level** `# shellcheck disable=SCxxxx` directive must appear immediately after the shebang and **before the first command** — including before `set -uo pipefail`. Placed after any command, it degrades to a *next-statement* directive and silently scopes only the following line:

```bash
#!/usr/bin/env bash
# shellcheck disable=SC2015,SC2002   # file-level: must precede the first command
set -uo pipefail
# ... rest of the script ...
```

```bash
#!/usr/bin/env bash
set -uo pipefail
# shellcheck disable=SC2015          # WRONG: now only scopes the next line
```

Two findings worth suppressing rather than rewriting in **test scripts** (where the idiom is deliberate): `SC2015` (`cmd && pass++ || fail` — the `++` is arithmetic that exits 0 here, so the `|| fail` branch only runs on real failure) and `SC2002` (piping a fixture through `cat` for readability). Prefer a justified file-level disable with a comment over churning every assertion.

**Meta-gotcha — pre-commit only shellchecks *staged* files.** Editing a script that "passed" before can surface pre-existing findings that were never actually checked (the hook never re-ran on that file since they were introduced). Don't assume an untouched-looking lint failure is something your edit caused; the whole file is being linted, possibly for the first time in a while. Run `shellcheck <file>` directly to see the full picture before committing.

## Error Handling

### Standard Fallback Pattern

```bash
# Always provide a fallback for missing fields
prp_status=$(head -50 "$prp" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//' || true)

# With default value
prp_status=${prp_status:-"unknown"}
```

### Silent Errors for Optional Fields

```bash
# Suppress errors for missing files or fields
confidence=$(head -50 "$prp" 2>/dev/null | grep -m1 "^confidence:" | sed 's/^[^:]*:[[:space:]]*//' || echo "")
```

### Check Before Use

```bash
# Validate required fields
if [ -z "$prp_status" ]; then
  echo "Warning: $prp_name missing status field"
  continue
fi
```

## File Iteration Patterns

### Safe Glob Iteration

```bash
# Use nullglob behavior - handle empty directories
shopt -s nullglob 2>/dev/null  # bash
setopt null_glob 2>/dev/null   # zsh

# Or check for files first
if ls docs/prps/*.md >/dev/null 2>&1; then
  for prp in docs/prps/*.md; do
    # ...
  done
else
  echo "No PRPs found"
fi
```

### With find (more portable)

```bash
# Use find with -print0 for safe filename handling
find docs/prps -name "*.md" -type f -print0 2>/dev/null | while IFS= read -r -d '' prp; do
  prp_name=$(basename "$prp")
  # ...
done
```

## Output Formatting

### Table Output

```bash
# Consistent table format with pipes
printf "%-30s | %-12s | %s\n" "Name" "Status" "Confidence"
printf "%-30s | %-12s | %s\n" "----" "------" "----------"
for prp in docs/prps/*.md; do
  prp_name=$(basename "$prp" .md)
  prp_status=$(head -50 "$prp" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//' || true)
  prp_confidence=$(head -50 "$prp" | grep -m1 "^confidence:" | sed 's/^[^:]*:[[:space:]]*//' || true)
  printf "%-30s | %-12s | %s\n" "$prp_name" "${prp_status:-N/A}" "${prp_confidence:-N/A}"
done
```

### JSON Output (for parsing)

```bash
# Generate JSON array for machine consumption
echo "["
first=true
for prp in docs/prps/*.md; do
  prp_name=$(basename "$prp" .md)
  prp_status=$(head -50 "$prp" | grep -m1 "^status:" | sed 's/^[^:]*:[[:space:]]*//' || true)

  $first || echo ","
  first=false
  printf '  {"name": "%s", "status": "%s"}' "$prp_name" "${prp_status:-unknown}"
done
echo ""
echo "]"
```

## Quick Reference

### Frontmatter Extraction One-Liner

```bash
# Template - replace FIELD and use safe variable name
item_FIELD=$(head -50 "$file" | grep -m1 "^FIELD:" | sed 's/^[^:]*:[[:space:]]*//' || true)
```

### Common Extractions

| Field | Safe Variable | Pattern |
|-------|---------------|---------|
| status | `doc_status` | `head -50 "$f" \| grep -m1 "^status:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| confidence | `confidence` | `head -50 "$f" \| grep -m1 "^confidence:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| domain | `doc_domain` | `head -50 "$f" \| grep -m1 "^domain:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| created | `created_date` | `head -50 "$f" \| grep -m1 "^created:" \| sed 's/^[^:]*:[[:space:]]*//'` |
| modified | `modified_date` | `head -50 "$f" \| grep -m1 "^modified:" \| sed 's/^[^:]*:[[:space:]]*//'` |

## BashTool Login Shell Behavior (2.1.51+)

As of Claude Code 2.1.51, the BashTool skips the login shell `-l` flag by default when a shell snapshot is available. This means `.bash_profile` and `.profile` are not sourced on every command. Environment setup that depends on login shell initialization should use `SessionStart` hooks or `CLAUDE_ENV_FILE` instead.

## Bash Version Requirement

Scripts require **bash 5+**. macOS ships bash 3.2 (GPLv2); install a modern version via Homebrew:

```bash
brew install bash
```

Homebrew bash installs to `/opt/homebrew/bin/bash` and takes priority in `$PATH`. All scripts use `#!/usr/bin/env bash` shebangs, so no system replacement is needed.

### Bash 5+ Features Available

These features are safe to use in all project scripts:

| Feature | Example |
|---------|---------|
| Associative arrays | `declare -A map=([key]=value)` |
| `mapfile` / `readarray` | `mapfile -t lines < file.txt` |
| `${var,,}` / `${var^^}` | Lowercase/uppercase without `tr` |
| `${var@Q}` | Shell-quoted expansion |
| Nameref variables | `declare -n ref=varname` |

### Plugin Directory Discovery

Exclude `.claude-plugin` (hidden metadata directory) from `*-plugin` globs:

```bash
find . -maxdepth 1 -type d -name '*-plugin' -not -name '.claude-plugin' -print0
```

### GNU vs BSD Tool Differences

Even with bash 5+, some CLI tools differ between macOS (BSD) and Linux (GNU). Use portable patterns for:

| Tool | macOS (BSD) | Linux (GNU) | Portable |
|------|-------------|-------------|----------|
| `date` | `date -j -f "%Y-%m-%d %H:%M:%S" "$d 00:00:00"` | `date -d "$d 00:00:00"` | Pin the time component (see below) |
| `sed -i` | `sed -i ''` | `sed -i` | Use `sed -i.bak` + `rm` |
| `grep -P` | Not available | PCRE support | Use `grep -E` (extended regex) |

#### BSD `date` fills unspecified time fields with the *current* time

`date -j -f "%Y-%m-%d" "$d" "+%s"` does **not** parse a bare date as
midnight on BSD/macOS — it fills the unspecified hour/minute/second with
the **current wall-clock time**. So the same date string parsed a second
apart returns epochs that differ by one second:

```bash
date -j -f "%Y-%m-%d" "2026-06-21" "+%s"   # 1782064565
date -j -f "%Y-%m-%d" "2026-06-21" "+%s"   # 1782064566  ← same date, +1s
```

Any code that parses two dates separately and compares them (`-gt`, `-lt`)
is then **non-deterministic**: an `equal` comparison flips to `newer`
whenever the two `date` calls straddle a second boundary. This was the
root cause of the `check-driver-freshness.sh` flake (#1704 / PR #1764),
where a dependency date equal to the driver's review date intermittently
compared as newer.

Fix: parse an explicit `00:00:00` so the epoch is a pure function of the
date on both platforms. (GNU `date -d "$d"` already parses a bare date as
midnight, but pinning the time keeps both branches identical.)

```bash
# Cross-platform date → epoch — deterministic (time-of-day independent)
if date -j -f "%Y-%m-%d %H:%M:%S" "$past_date 00:00:00" "+%s" >/dev/null 2>&1; then
  past_ts=$(date -j -f "%Y-%m-%d %H:%M:%S" "$past_date 00:00:00" "+%s")  # BSD/macOS
elif date -d "$past_date 00:00:00" "+%s" >/dev/null 2>&1; then
  past_ts=$(date -d "$past_date 00:00:00" "+%s")                        # GNU/Linux
fi
```

#### BSD `date` has no `%N` — millisecond timing needs python/perl

GNU `date +%s%3N` (Unix seconds + zero-padded milliseconds) is a common way to
time a command to sub-second precision. **BSD/macOS `date` does not support
`%N`** — it emits the literal character `N`, so `date +%s%3N` returns garbage
like `17830708663N` (a valid-looking integer with a trailing `N`), not
milliseconds. The failure is silent: the string is truncated/parsed into a
number and the elapsed math is nonsense (or a whole-second `date +%s` reads `0`
for anything sub-second — an M4 finishes a 10M-iteration loop in <1s).

```bash
# Wrong on macOS: %N is literal, and whole-second %s reads 0 for fast ops
start=$(date +%s%3N)   # → 17830708663N  (BSD emits a literal 'N')
```

Portable millisecond timestamp — python3 or perl (both present on macOS),
falling back to whole-second `date`:

```bash
now_ms() {
  if command -v python3 &>/dev/null; then python3 -c 'import time; print(int(time.time()*1000))'
  elif command -v perl &>/dev/null; then perl -MTime::HiRes=time -e 'print int(time()*1000)'
  else echo $(( $(date +%s) * 1000 )); fi
}
start=$(now_ms); some_command; echo "$(( $(now_ms) - start )) ms"
```

For timing a script *you* invoke (a benchmark), prefer measuring inside the
interpreter it already runs — e.g. have the Python step print
`int((time.perf_counter()-t)*1000)` itself — over wrapping it in shell `date`.

## Checklist for New Commands

- [ ] Variable names use prefixed form (e.g., `doc_status` instead of `status`)
- [ ] Frontmatter extraction uses `head -50 | grep -m1 "^field:" | sed ...` pattern
- [ ] Error handling with `|| true` or `|| echo ""`
- [ ] Default values with `${var:-default}`
- [ ] File iteration handles empty directories
- [ ] Output format is consistent (table or JSON)
- [ ] Plugin discovery excludes `.claude-plugin` directory
