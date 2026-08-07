#!/usr/bin/env bash
# shellcheck disable=SC2034  # file-level: lineno/lang are positional read fields required to reach the trailing `line` field
# Version-pin coverage guard (.claude/rules/version-pinning.md).
#
# Every executable version pin in skill markdown — GitHub Action refs (uses:),
# Docker base images (FROM), service/container images (image:), and pre-commit
# revisions (rev:) — should be a shape Renovate's customManagers can see and
# keep fresh. This guard fails when an executable pin is version-shaped but does
# NOT match a managed form (so Renovate would silently skip it and the pin would
# rot). It deliberately does NOT demand SHA pins: tag form is "covered" too, so
# the guard never deadlocks against Renovate's own digest-pinning first run.
#
# It also catches the *transitive* gap (#2175): an action that installs a binary
# of its own is only half-pinned by `uses:` — if the step leaves the action's
# `version:` input at its floating default, the workflow looks pinned but pulls
# a fresh binary on every run. See INSTALLER_ACTIONS below.
#
# It also catches the *path* gap (#2222): a plugin scaffold template
# (*-plugin/templates/**) ships REAL workflow/manifest files that a generated
# repo inherits verbatim. Such a pin can be perfectly well shaped and still be
# invisible, because no manager's file pattern matches its path. See the
# "Plugin scaffold templates" section below.
#
# Only fenced code blocks are scanned, so illustrative version numbers in prose
# tables are ignored by design (see the "illustrative vs. managed" table in the
# rule). Fence detection comes from a real markdown parse (tree-sitter) via the
# shared scripts/lib/extract-md-elements.py helper — NOT a hand-rolled ``` toggle
# (that state machine shipped bug #1492).
#
# Emits the structured KEY=value / STATUS= convention
# (.claude/rules/structured-script-output.md).
#
# Usage:
#   check-version-pin-coverage.sh [--project-dir <path>] [--strict]
#
#   --project-dir   Repo root to scan (default: git toplevel, else cwd)
#   --strict        Exit 1 when an ERROR-severity pin is found (default: exit 0)
set -uo pipefail

proj_dir=""
strict=false

while [ $# -gt 0 ]; do
  case "$1" in
    --project-dir) proj_dir="$2"; shift 2 ;;
    --strict) strict=true; shift ;;
    *) shift ;;
  esac
done

if [ -z "$proj_dir" ]; then
  proj_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

issue_count=0
declare -a issues=()
files_scanned=0
uses_covered=0
from_covered=0
image_covered=0
rev_covered=0
version_input_covered=0
template_files_scanned=0
template_pins_covered=0

add_issue() {
  # add_issue <severity> <type> <message>
  issues+=("  - SEVERITY=$1 TYPE=$2 MSG=$3")
  issue_count=$((issue_count + 1))
}

# Managed-form predicates (mirror the renovate.json customManager regexes).
is_managed_uses_ref() {
  # $1 = the text after "uses: " up to end of line
  local rest="$1"
  # SHA pin + version comment:  owner/repo@<40hex> # vX.Y.Z
  [[ "$rest" =~ @[0-9a-f]{40}[\"\'\ ].*#[[:space:]]*v?[0-9] ]] && return 0
  [[ "$rest" =~ @[0-9a-f]{40}([[:space:]]+#[[:space:]]*v?[0-9]) ]] && return 0
  # Tag form: @vX...  or  @<digits>.<...>  (needs a dot to avoid matching a SHA)
  [[ "$rest" =~ @v[0-9] ]] && return 0
  [[ "$rest" =~ @[0-9][0-9A-Za-z._+-]*\.[0-9A-Za-z._+-]+ ]] && return 0
  return 1
}

is_floating_or_local_ref() {
  # Floating tags and local/non-pinned refs are intentionally out of scope.
  local rest="$1"
  [[ "$rest" =~ @(main|master|stable|nightly|latest|HEAD)([[:space:]]|$|\") ]] && return 0
  [[ "$rest" =~ uses:[[:space:]]+\.?/ ]] && return 0       # local action ./path
  [[ "$rest" =~ uses:[[:space:]]+docker:// ]] && return 0  # docker:// ref
  return 1
}

is_version_shaped_ref() {
  # Looks like a deliberate version pin (so an unmanaged one is a real gap).
  local rest="$1"
  [[ "$rest" =~ @v[0-9] ]] && return 0
  [[ "$rest" =~ @[0-9] ]] && return 0
  [[ "$rest" =~ @[0-9a-f]{40} ]] && return 0
  return 1
}

# --- Transitive pins: the action installs a binary of its own (#2175) ---------
# A SHA-pinned `uses:` pins the composite action and its bundled installer — NOT
# the artifact that installer downloads. When the action exposes a `version:`
# input whose default floats (Connorrmcd6/surface's action.yml: `version:
# default: latest`, then install.sh resolves releases/latest over the API at run
# time), an example that omits `version:` produces a workflow that LOOKS fully
# pinned while installing a floating binary on every run. Checksum verification
# does not close it: the checksum proves the download matches its own published
# hash, not that it is the version the consumer pinned.
#
# Both new checks (absent `version:`, and present-but-floating `version:`) are
# gated on membership. Scoping to a curated list rather than every pinned action
# is deliberate: a `version: latest` on a toolchain setup-* action is frequently
# an intentional "track the latest toolchain" choice, so blanket-flagging it
# would turn a correctness guard into a style opinion on files the reporting PR
# never touched. Add an action here when its floating default is a real gate-
# stability hazard — a candidate observed while writing this check is
# `astral-sh/setup-uv` (python-plugin/skills/python-development/REFERENCE.md
# pins the ref but leaves `version: "latest"`), left out pending a decision.
declare -a INSTALLER_ACTIONS=(
  "Connorrmcd6/surface"
)

is_installer_action() {
  local ref="$1" known
  for known in "${INSTALLER_ACTIONS[@]}"; do
    [ "$ref" = "$known" ] && return 0
  done
  return 1
}

uses_action_id() {
  # "  - uses: owner/repo@<ref> # vX.Y.Z"  ->  "owner/repo"
  local rest="$1"
  rest="${rest#*uses:}"
  rest="${rest#"${rest%%[![:space:]]*}"}"   # ltrim
  rest="${rest%%[[:space:]]*}"              # first token only
  rest="${rest%%@*}"                        # drop the @ref
  rest="${rest#\"}"; rest="${rest#\'}"
  rest="${rest%\"}"; rest="${rest%\'}"
  printf '%s' "$rest"
}

is_floating_version_value() {
  # The values that mean "resolve it fresh at run time".
  local val="$1"
  val="${val#\"}"; val="${val%\"}"
  val="${val#\'}"; val="${val%\'}"
  [ -z "$val" ] && return 0
  case "$val" in
    latest|main|master|stable|nightly|edge|HEAD) return 0 ;;
  esac
  return 1
}

# Pending-step state for the transitive-pin check. The scan loop below runs in
# the current shell (process substitution), so this state survives iterations —
# same mechanism the pre-commit `last_repo` lookahead already relies on.
pending_uses_ref=""
pending_uses_rel=""
pending_uses_installer=false
pending_version_seen=false

flush_pending_uses() {
  if [ -n "$pending_uses_ref" ] \
     && [ "$pending_uses_installer" = true ] \
     && [ "$pending_version_seen" = false ]; then
    add_issue ERROR version_input_missing \
      "$pending_uses_rel: '$pending_uses_ref' installs its own binary but the step sets no 'version:' input — the pinned uses: covers the action, not the binary (its version input defaults to a floating 'latest')"
  fi
  pending_uses_ref=""
  pending_uses_rel=""
  pending_uses_installer=false
  pending_version_seen=false
}

# Discover files to scan. Prune agent worktree copies (.claude/worktrees/*) —
# they are full repo checkouts created by concurrently-running isolated agents,
# so descending into them re-scans every skill file N× and litters WARN output
# with their paths (#1492). The guard only ever audits the real tree.
#
# Prune dist/ for the same reason in generated form (#2214): it is the
# gitignored rulesync build output, so a finding there is unactionable by
# construction — the fix site is always the source skill, and the next
# `just export-opencode` overwrites it. A stale local dist/ otherwise hard-ERRORs
# every local commit while CI (which never sees dist/) stays green. The sibling
# scripts/lint-context-commands.sh already excludes it via --exclude-dir='dist'.
#
# Discovery runs from INSIDE proj_dir against RELATIVE paths (#2219). With an
# absolute base, the bare `*/.claude/worktrees/*` prune fires on the whole tree
# whenever proj_dir is ITSELF an agent worktree — its own path contains
# `/.claude/worktrees/`, so every descendant matches, the scan root is pruned
# entirely, and this guard reports FILES_SCANNED=0 / STATUS=OK having scanned
# nothing: a false green for exactly the worktree-isolated subagents that do most
# plugin work here. Relative paths make the root `.`, so its absolute prefix cannot
# match while copies nested anywhere below it still prune correctly. Same fix, and
# same reasoning, as scripts/check-subagent-types.sh.
cd "$proj_dir" || { echo "check-version-pin-coverage.sh: cannot cd to $proj_dir" >&2; exit 2; }

declare -a scan_files=()
while IFS= read -r -d '' file; do
  scan_files+=("$file")
done < <(find . -path '*/.claude/worktrees/*' -prune -o \
           -path '*/dist/*' -prune -o \
           -path '*/skills/*' -name '*.md' -type f -print0 2>/dev/null)
files_scanned=${#scan_files[@]}

# Zero files scanned is two different states and they must be distinguishable.
# Plugin directories present but no skill markdown discovered means the scan
# misfired (a prune that swallowed the root); no plugin directories at all means
# there is genuinely nothing to audit.
# The population signal is a plugin dir that actually HAS a skills/ tree, not a
# plugin dir per se. A plugin carrying only templates/ (or only agents/) is a
# legitimate zero-markdown corpus, and counting it made a template-only tree
# report a misfire it had not suffered. A prune that swallows the scan root
# still fires: every real plugin dir has skills/, so the count stays > 0.
plugin_dir_count=$(find . -maxdepth 2 -type d -name 'skills' -not -path '*/.claude/worktrees/*' -not -path '*/dist/*' 2>/dev/null | wc -l | tr -d ' ')
# Recorded as a normal ERROR issue rather than an early exit. The misfire is a
# verdict about the MARKDOWN corpus only, and the scaffold-template scan below
# (#2222) is independent of it — reading its own file set and emitting its own
# TEMPLATE_* counters. Exiting here suppressed that scan entirely, so a
# template-only tree (plugin dirs + templates, no skill markdown) reported
# neither counter and any consumer reading TEMPLATE_FILES_SCANNED got an empty
# string. Falling through keeps the check loud: the ERROR still forces
# STATUS=ERROR and `--strict` still exits 1, via the normal report path.
# The markdown parse block below is already gated on `files_scanned > 0`, so it
# no-ops on an empty corpus without needing a second guard.
if [ "$files_scanned" -eq 0 ] && [ "$plugin_dir_count" -gt 0 ]; then
  add_issue ERROR nothing_scanned \
    "$plugin_dir_count plugin dirs but zero skill markdown discovered; scan misfired (see #2219)"
fi

# Fence-awareness comes from a real markdown parse (tree-sitter via the shared
# scripts/lib/extract-md-elements.py helper), replacing the hand-rolled ``` /
# ~~~ toggle state machine that shipped bug #1492. The helper emits one
# `fence_line` record per raw source line INSIDE a fenced code block:
#   fence_line<TAB>file<TAB>lineno<TAB>language<TAB>text
# so this loop only ever sees lines a correct CommonMark/GFM parse considers
# fenced. Illustrative version numbers in prose tables are never fenced, so they
# are excluded by construction (the "illustrative vs. managed" rule).
if [ "$files_scanned" -gt 0 ]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  helper="$script_dir/lib/extract-md-elements.py"
  if ! command -v uv >/dev/null 2>&1; then
    echo "check-version-pin-coverage: 'uv' not found on PATH; cannot parse markdown structure" >&2
    echo "  (the fence-aware scan uses scripts/lib/extract-md-elements.py via 'uv run')" >&2
    exit 2
  fi
  prev_file=""
  last_repo=""
  rel=""
  while IFS=$'\t' read -r rectype file lineno lang line; do
    [ "$rectype" = "fence_line" ] || continue
    if [ "$file" != "$prev_file" ]; then
      flush_pending_uses
      prev_file="$file"
      last_repo=""
      rel="${file#"$proj_dir"/}"
    fi

    # --- GitHub Action refs ---------------------------------------------------
    if [[ "$line" =~ uses:[[:space:]]+[^[:space:]]+@ ]]; then
      # A new step ends the previous one's `with:` block — settle it first.
      flush_pending_uses
      if is_floating_or_local_ref "$line"; then
        :  # intentionally unpinned
      elif is_managed_uses_ref "$line"; then
        uses_covered=$((uses_covered + 1))
      elif is_version_shaped_ref "$line"; then
        add_issue ERROR uses_uncovered \
          "$rel: version-shaped 'uses:' ref not in a Renovate-managed form (use @vX.Y.Z tag or @<sha> # vX.Y.Z): ${line#"${line%%uses:*}"}"
      fi
      # Track pinned steps so a following `version:` input can be judged (#2175).
      if ! is_floating_or_local_ref "$line"; then
        pending_uses_ref="$(uses_action_id "$line")"
        pending_uses_rel="$rel"
        if is_installer_action "$pending_uses_ref"; then
          pending_uses_installer=true
        fi
      fi
    fi

    # --- Transitive binary pin: the step's own `version:` input (#2175) -------
    if [ "$pending_uses_installer" = true ] && [[ "$line" =~ ^[[:space:]]*version:[[:space:]]*(.*)$ ]]; then
      version_value="${BASH_REMATCH[1]}"
      version_value="${version_value%%#*}"                                  # strip trailing comment
      version_value="${version_value%"${version_value##*[![:space:]]}"}"    # rtrim
      pending_version_seen=true
      if is_floating_version_value "$version_value"; then
        add_issue ERROR version_input_floating \
          "$rel: 'version: ${version_value:-<empty>}' under pinned 'uses: $pending_uses_ref' — the pinned ref covers the action, not the binary it installs; set an explicit release tag"
      else
        version_input_covered=$((version_input_covered + 1))
      fi
    fi

    # --- Docker base images ---------------------------------------------------
    if [[ "$line" =~ ^[[:space:]]*FROM[[:space:]]+[^[:space:]]+:[^[:space:]@]+ ]]; then
      from_covered=$((from_covered + 1))
    fi

    # --- Service/container images --------------------------------------------
    if [[ "$line" =~ image:[[:space:]]+[\"\']?[^[:space:]\"\']+:[^[:space:]@\"\']+ ]]; then
      image_covered=$((image_covered + 1))
    fi

    # --- pre-commit repo + rev -----------------------------------------------
    if [[ "$line" =~ repo:[[:space:]]+(https://)?github\.com/ ]]; then
      last_repo="github"
    elif [[ "$line" =~ repo:[[:space:]]+ ]]; then
      last_repo="other"
    fi
    if [[ "$line" =~ ^[[:space:]]*rev:[[:space:]]+[^[:space:]]+ ]]; then
      if [ "$last_repo" = "github" ]; then
        rev_covered=$((rev_covered + 1))
      elif [ "$last_repo" = "other" ]; then
        add_issue WARN rev_non_github \
          "$rel: pre-commit 'rev:' under a non-github.com repo — Renovate github-tags cannot manage it"
      fi
      last_repo=""
    fi

    # --- Known-unmanaged version surfaces (informational) --------------------
    if [[ "$line" =~ (node-version|python-version|go-version|ruby-version):[[:space:]]+[\"\']?[0-9] ]]; then
      add_issue WARN runtime_version_unmanaged \
        "$rel: runtime-version selector is not a Renovate-managed surface (illustrative only): ${line#"${line%%[!  ]*}"}"
    fi
    if [[ "$line" =~ additional_dependencies:.*@[0-9] ]]; then
      add_issue WARN npm_in_precommit_unmanaged \
        "$rel: pinned npm dep in additional_dependencies is out of scope for v1 (see version-pinning.md)"
    fi
  done < <(printf '%s\n' "${scan_files[@]}" \
             | uv run --quiet "$helper" --types fence_line --files-from - 2>/dev/null)
  # Settle the last step of the last file.
  flush_pending_uses
fi

# --- Plugin scaffold templates (#2222) ----------------------------------------
# The scan above covers pins written as EXAMPLES in skill markdown. A plugin
# scaffold template (*-plugin/templates/**) is the other shape: real workflow /
# manifest files that a generated repo inherits verbatim, so whatever pin the
# template carries at generation time is what every new repo starts on.
#
# The failure mode here is not the pin's SHAPE (a template's `uses: x@v6` is a
# perfectly good tag-form pin) — it is the pin's PATH. Renovate's built-in
# managers are '(^|/)'-prefixed rather than root-anchored, so they already reach
# a template's own .github/workflows/ subtree and its package.json; a FLAT
# scaffold layout (blueprint-plugin/templates/*.workflow.yml) matches nothing.
# Such a pin looks managed, is shaped correctly, and silently never updates.
#
# So this check asks the coverage question directly: is the FILE matched by any
# manager pattern? The configured patterns are read out of renovate.json rather
# than restated here, so the guard tracks the config instead of drifting from it
# (the built-in defaults below are Renovate's own, which do not change often).
if command -v python3 >/dev/null 2>&1; then
  template_report="$(
    python3 - "$proj_dir" <<'PY'
import json, os, re, sys

proj = sys.argv[1]

# Renovate's own defaults for the managers that carry version pins. Additive
# user patterns from renovate.json are appended below.
patterns = [
    r"(^|/)(workflow-templates|\.(?:github|gitea|forgejo)/(?:workflows|actions))/.+\.ya?ml$",
    r"(^|/)action\.ya?ml$",
    r"(^|/)package\.json$",
    r"(^|/)\.pre-commit-config\.ya?ml$",
    r"(^|/)([Dd]ocker|[Cc]ontainer)file[^/]*$",
    r"(^|/)(docker-)?compose[^/]*\.ya?ml$",
]


def add(raw):
    # Renovate treats a /…/-delimited value as a regex; anything else is a glob.
    # Only the regex form is understood here — a glob pattern is reported as
    # unparsed rather than silently treated as covering nothing.
    if isinstance(raw, str) and len(raw) > 1 and raw.startswith("/") and raw.endswith("/"):
        try:
            re.compile(raw[1:-1])
        except re.error:
            return
        patterns.append(raw[1:-1])


cfg_path = os.path.join(proj, "renovate.json")
try:
    with open(cfg_path, encoding="utf-8") as fh:
        cfg = json.load(fh)
except (OSError, ValueError):
    cfg = {}

for key, value in cfg.items():
    if isinstance(value, dict):
        for raw in value.get("managerFilePatterns", []) or []:
            add(raw)
for cm in cfg.get("customManagers", []) or []:
    for raw in cm.get("managerFilePatterns", []) or []:
        add(raw)

compiled = [re.compile(p) for p in patterns]

USES = re.compile(r"uses:\s*[\"']?([\w.-]+/[\w./-]+)@([^\s\"']+)")
FROM = re.compile(r"^\s*FROM\s+\S+:\S+", re.M)
IMAGE = re.compile(r"^\s*image:\s*[\"']?[\w./-]+:[\w][\w.-]*", re.M)
REV = re.compile(r"^\s*rev:\s*\S+", re.M)
FLOATING = {"main", "master", "stable", "nightly", "latest", "HEAD"}

files = 0
covered = 0
issues = []

for dirpath, dirnames, filenames in os.walk(proj):
    dirnames[:] = [
        d for d in dirnames
        if d not in (".git", "node_modules", "dist") and d != "worktrees"
    ]
    parts = os.path.relpath(dirpath, proj).split(os.sep)
    # Only a `templates/` tree that lives directly inside a *-plugin directory.
    if not any(
        parts[i].endswith("-plugin") and parts[i + 1] == "templates"
        for i in range(len(parts) - 1)
    ):
        continue
    for name in sorted(filenames):
        # Markdown under a plugin is either a skill example (scanned above) or
        # prose; either way it is not a file a manager would ever match.
        if name.endswith(".md"):
            continue
        abspath = os.path.join(dirpath, name)
        rel = os.path.relpath(abspath, proj)
        try:
            with open(abspath, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
        except OSError:
            continue

        pins = []
        for owner_repo, ref in USES.findall(text):
            if ref in FLOATING:
                continue
            pins.append("uses: %s@%s" % (owner_repo, ref))
        if FROM.search(text):
            pins.append("FROM <image>:<tag>")
        if IMAGE.search(text):
            pins.append("image: <image>:<tag>")
        if REV.search(text):
            pins.append("rev: <ref>")
        if name == "package.json":
            try:
                pkg = json.loads(text)
            except ValueError:
                pkg = {}
            for dep_type in ("dependencies", "devDependencies", "peerDependencies"):
                if pkg.get(dep_type):
                    pins.append("package.json %s" % dep_type)

        if not pins:
            continue
        files += 1
        if any(rx.search(rel) for rx in compiled):
            covered += len(pins)
            continue
        issues.append(
            "ERROR\ttemplate_pin_unmanaged\t"
            "%s: scaffold template carries a version pin (%s) at a path no "
            "Renovate manager matches — add the path to a manager's "
            "managerFilePatterns in renovate.json (see .claude/rules/version-pinning.md)"
            % (rel, pins[0])
        )

print("COUNT_FILES=%d" % files)
print("COUNT_COVERED=%d" % covered)
for line in issues:
    print("ISSUE\t%s" % line)
PY
  )"
  while IFS= read -r report_line; do
    case "$report_line" in
      COUNT_FILES=*) template_files_scanned="${report_line#COUNT_FILES=}" ;;
      COUNT_COVERED=*) template_pins_covered="${report_line#COUNT_COVERED=}" ;;
      ISSUE*)
        report_line="${report_line#ISSUE	}"
        add_issue "${report_line%%	*}" \
          "$(printf '%s' "${report_line#*	}" | cut -f1)" \
          "$(printf '%s' "$report_line" | cut -f3-)"
        ;;
    esac
  done <<< "$template_report"
fi

# --- Status -------------------------------------------------------------------
overall_status="OK"
exit_severity=0
for line in "${issues[@]:-}"; do
  case "$line" in
    *SEVERITY=ERROR*) overall_status="ERROR"; exit_severity=1 ;;
  esac
done
if [ "$overall_status" = "OK" ] && [ "$issue_count" -gt 0 ]; then
  overall_status="WARN"
fi

# --- Output -------------------------------------------------------------------
echo "=== VERSION PIN COVERAGE ==="
echo "FILES_SCANNED=$files_scanned"
echo "PLUGIN_DIRS=$plugin_dir_count"
echo "USES_COVERED=$uses_covered"
echo "FROM_COVERED=$from_covered"
echo "IMAGE_COVERED=$image_covered"
echo "REV_COVERED=$rev_covered"
echo "VERSION_INPUT_COVERED=$version_input_covered"
echo "TEMPLATE_FILES_SCANNED=$template_files_scanned"
echo "TEMPLATE_PINS_COVERED=$template_pins_covered"
echo "STATUS=$overall_status"
echo "ISSUE_COUNT=$issue_count"
if [ "$issue_count" -gt 0 ]; then
  echo "ISSUES:"
  printf '%s\n' "${issues[@]}"
fi
echo "=== END VERSION PIN COVERAGE ==="

if [ "$strict" = true ]; then
  exit "$exit_severity"
fi
exit 0
