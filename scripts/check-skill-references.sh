#!/usr/bin/env bash
# Resolve every `<name>-plugin:<artifact>` citation, and every `/<ns>:<name>`
# slash command, against the skills and agents that actually exist on disk.
#
# Skills, rules and REFERENCE files cite sibling artifacts by their
# plugin-qualified ID ("invoke `git-plugin:git-commit`"). Nothing validates
# those strings: rename a skill directory, or delete one, and every citation
# keeps reading as authoritative while pointing at an ID the Skill tool cannot
# resolve. The agent burns a round trip on `Skill(...)` -> "not found" and then
# reinvents whatever the cited skill encoded — the exact failure the citation
# existed to prevent.
#
# The same holds for the `/<ns>:<name>` short form ("run `/git:pr-feedback`").
# `testing-plugin:test-analyze` pointed at `/git:smartcommit` and
# `/docs:update`, and `configure-coverage` at `/test:coverage` — none of which
# has existed for months. Those were invisible to the ID check because the short
# form carries no `-plugin` suffix.
#
# This is a RESOLUTION check, not a denylist: ground truth is rebuilt from the
# tree on every run, so a rename is caught the moment it lands without anyone
# adding an entry here. Contrast `lint-mcp-tool-references.sh`, which must
# enumerate bad names because the MCP servers' tool lists are not on disk.
#
# GROUND TRUTH — an ID resolves if it matches either:
#   * `<plugin>/skills/<name>/SKILL.md`  -> `<plugin>:<name>`
#   * `<plugin>/agents/<name>.md`        -> `<plugin>:<name>`
# There are no `commands/` directories in this repo; add a third arm here if
# that changes.
#
# SLASH COMMANDS — `/<ns>:<name>` resolves if either:
#   * FULL FORM: `<ns>:<name>` is itself an ID above (`/git-plugin:git-commit`,
#     the form Claude Code registers a plugin skill under).
#   * SHORT FORM: some plugin P is a candidate for `<ns>` — P is `<ns>-plugin`,
#     or P owns a skill directory whose first hyphen-segment is `<ns>` — and P
#     has a skill directory named `<ns>-<name>` or `<name>`.
# The short form is the repo's documented shorthand (`.claude/rules/
# skill-naming.md`: `/blueprint:prp-create` -> `skills/blueprint-prp-create/`),
# and the mapping is the one `check-docs-index.sh` Check 7 already applies to
# README rows, so a README row and a skill body cannot disagree about whether a
# command exists. Verified 2026-10-07 against all 130 skills whose H1 names
# their own slash command: every one resolves to its own directory. Frontmatter
# `name:` is NOT consulted: the four skills that override it (`refocus`,
# `ground-response`, `UnoCSS`, `Lightning CSS`) are all cited by directory.
# Claude Code built-ins (`/help`, `/clear`, `/goal`, `/loop`) carry no colon
# and so never match.
#
# COVERAGE — what this script reads. It is NOT repo-wide:
#   * every `*.md` under a `skills/` directory — `SKILL.md`, `REFERENCE.md`,
#     and the sidecars the 2026-10 split moved content into
#     (`references/*.md`, `REFERENCE-<topic>.md`, `migrations/`, `templates/`).
#     A sidecar is read out of context, which is when a dead pointer costs most.
#   * `SKILL.md` / `skill.md` / `REFERENCE.md` anywhere else in the repo
#   * `*.workflow.js` — workflow scripts bundled beside a skill, which carry
#     skill IDs in their agent prompts
#   * `.claude/rules/*.md` — always-loaded rules that route the agent to a
#     skill by ID. A dead ID here misroutes every session, so unlike the MCP
#     linter (which excludes rules because they cite broken tool names on
#     purpose) this scan includes them. The two intentional-broken-citation
#     shapes that live in rules are handled by the allowlist below.
# Deliberately OUT of scope:
#   * `docs/**` — ADRs and benchmark judgments are immutable records. ADR-0007
#     cites `git-plugin:commit`, a pre-rename name that was correct when the
#     decision was written; "fixing" it would falsify the record.
#   * `CHANGELOG.md` — release-please generated, and a changelog entry about a
#     rename necessarily names the old ID.
#   * `README.md` / `docs/PLUGIN-MAP.md` counts — already covered by
#     `check-docs-index.sh`; this script must not double-gate them.
#   * hook scripts — `check-hook-cue-skill-refs.sh` owns emitted cues, where
#     only the FULL form is acceptable (the agent pastes them into `Skill`).
#
# Lines starting with `>` (markdown blockquote) are skipped, matching
# `lint-mcp-tool-references.sh`, so a callout can cite a dead ID as an example.
#
# Exit codes:
#   0 - every citation resolves
#   1 - one or more dead citations found
set -euo pipefail

errors=0

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# Citation shape. Two guards earn their keep, both found by running this
# against the tree:
#   * LEFT BOUNDARY `[^A-Za-z0-9_-]` — without it the prose word
#     "Cross-plugin:" yields a phantom `ross-plugin:`. The class must exclude
#     UPPER case too; `[^a-z0-9_-]` still matches the `C` and re-admits it.
#   * NON-EMPTY NAME `[a-z0-9-]+` — a bare `<plugin>:` prefix is not a
#     citation. Without the `+`, the changelog heading `**testing-plugin:**`
#     and the shell line `echo "macos-plugin: not Darwin"` both register as
#     dead IDs (7 of the 9 false positives on the first run).
# Start of line counts as a boundary: the scanner prefixes each line with a
# space, so the boundary character is always present and always stripped.
id_re='[^A-Za-z0-9_-][a-z][a-z0-9-]*-plugin:[a-z0-9-]+'

# Slash-command shape. Its left boundary excludes the characters that put a
# `/x:y` inside something that is not a command, each class observed when the
# check was first run over the tree (2026-10-07, ~100 such matches, all
# correctly excluded):
#   * `/` — a URL with a port (`http://localhost:3000`) and a git refspec
#     (`refs/heads/x:refs/heads/x`)
#   * a letter or digit — an image reference (`ghcr.io/astral-sh/uv:0.12.7`,
#     `oven/bun:1-debian`) or a ref path (`origin/main:openapi.yaml`)
#   * `.` / `~` / `$` — relative and variable paths (`./myapp:main`)
#   * `:` — a container volume mount (`-v ./x:/data:ro`)
# The NAME must start with a letter, which also rejects `/x:8080`-style ports.
slash_re='[^A-Za-z0-9_/.~:$-]/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*'

# Enter the scan root before discovery so the relative paths `find .` emits
# resolve for the reads below too. A discovery subshell that cd'd while the
# consumer ran in the caller's cwd is the silent no-scan class of #2219/#2290.
cd "$repo_root" || exit 1

# Allowlist of citations that are correct despite not resolving. Each entry is a
# `case` glob. A plain entry is matched against the extracted ID; an entry
# containing `|` is matched against `<file>|<id>`, so an exemption can be scoped
# to the one file that legitimately names a removed command.
allowlist=(
  # `my-plugin:` is the placeholder namespace used by authoring examples
  # (agent-development.md, obsidian dev-tools). It names no real plugin by
  # design — a doc showing "how to cite a skill" needs a stand-in.
  'my-plugin:*'

  # A trailing `-` is the extractor hitting a glob form in prose, e.g.
  # `typescript-plugin:bun-*` in a regression-ledger row, or
  # `/blueprint:derive-*` in blueprint-init, which cite a FAMILY of skills
  # rather than one. The bare stem never resolves and should not.
  '*-'

  # Placeholder namespaces for the slash form, used where a doc explains the
  # shape itself: `/plugin-name:skill-name` (skill-naming.md),
  # `/plugin:skill` (plugin-usage-telemetry.md), `/ns:cmd` and
  # `/namespace:command` (bulk-sweep-classify, docs-sync).
  '/ns:*'
  '/namespace:*'
  '/plugin:*'
  '/plugin-name:*'

  # `/blueprint:generate-commands` was removed in #292. The upgrade skill and
  # the v3.0->v3.1 migration exist to DETECT and DELETE its leftover output, so
  # they must name it. Anywhere else, naming it is an instruction to run a
  # command that does not exist.
  'blueprint-plugin/skills/blueprint-upgrade/*|/blueprint:generate-commands'
  'blueprint-plugin/skills/blueprint-migration/migrations/*|/blueprint:generate-commands'

  # bulk-sweep-classify's category-3 example: a foreign project's
  # `/sync:daily` PRD whose colon is part of a designed filename. It is the
  # example of a match a sweep must LEAVE, so it cannot resolve here.
  'code-quality-plugin/skills/bulk-sweep-classify/SKILL.md|/sync:daily'
)

allowed() {
  local id="$1" file="$2" pat subject
  for pat in "${allowlist[@]}"; do
    case "$pat" in
      *'|'*) subject="$file|$id" ;;
      *) subject="$id" ;;
    esac
    # shellcheck disable=SC2254  # glob matching of $pat is intentional
    case "$subject" in
      $pat) return 0 ;;
    esac
  done
  return 1
}

# Build ground truth. Plain sorted files keep this working on bash 3.2 (macOS
# default), which has no associative arrays.
truth="$(mktemp)"
slash_truth="$(mktemp)"
skill_dirs="$(mktemp)"
trap 'rm -f "$truth" "$slash_truth" "$skill_dirs"' EXIT

find . -type f -name 'SKILL.md' \
  -not -path './.claude/worktrees/*' -not -path './dist/*' \
  -not -path '*/node_modules/*' -print |
  sed -n 's#^\./\([^/]*\)/skills/\([^/]*\)/SKILL\.md$#\1 \2#p' |
  sort -u >"$skill_dirs"

{
  sed 's/ /:/' "$skill_dirs"
  find . -type f -name '*.md' -path '*/agents/*' \
    -not -path './.claude/worktrees/*' -not -path './dist/*' \
    -not -path '*/node_modules/*' -print |
    sed -n 's#^\./\([^/]*\)/agents/\([^/]*\)\.md$#\1:\2#p'
} | sort -u >"$truth"

# Short-form slash truth, as `<ns>:<name>` lines. For each plugin, its candidate
# namespaces are its own stem (`git-plugin` -> `git`) plus the first
# hyphen-segment of each of its skill directories; for each such namespace and
# each directory D it owns, `<ns>:D` resolves, and so does `<ns>:<D minus
# "<ns>-">` when D carries that prefix.
LC_ALL=C awk '
  {
    p = $1; d = $2
    dirs[p] = dirs[p] " " d
    ns = p; sub(/-plugin$/, "", ns); cand[p SUBSEP ns] = 1
    first = d; sub(/-.*/, "", first); cand[p SUBSEP first] = 1
  }
  END {
    for (k in cand) {
      split(k, pk, SUBSEP)
      n = split(dirs[pk[1]], ds, " ")
      for (i = 1; i <= n; i++) {
        print pk[2] ":" ds[i]
        if (index(ds[i], pk[2] "-") == 1) print pk[2] ":" substr(ds[i], length(pk[2]) + 2)
      }
    }
  }
' "$skill_dirs" | sort -u >"$slash_truth"

truth_count="$(wc -l <"$truth" | tr -d ' ')"

# A ground truth of zero means the walk found nothing — a broken scan, not a
# clean tree. Fail loudly rather than pass every citation by vacuous default
# (the empty-negative trap: an unrun check and a passing check look identical).
if [ "$truth_count" -eq 0 ]; then
  printf "ERROR: resolved 0 skills/agents on disk -- the discovery walk is broken, not the tree clean\n" >&2
  exit 1
fi

# dist/ is gitignored OpenCode export output and worktree clones are copies of
# sources already scanned — findings there have no fix site. Same pruning as
# lint-mcp-tool-references.sh.
files=()
while IFS= read -r -d '' f; do
  files+=("$f")
done < <(find . -type f \
  \( -name 'SKILL.md' -o -name 'skill.md' -o -name 'REFERENCE.md' \
  -o \( -path '*/skills/*' -name '*.md' \) \
  -o -name '*.workflow.js' -o -path './.claude/rules/*.md' \) \
  -not -path './.claude/worktrees/*' \
  -not -path './dist/*' \
  -not -path '*/node_modules/*' \
  -print0)

# One awk pass over every file: extract both citation shapes, resolve each
# against the truth files, and print only what does not resolve. The former
# per-line `grep -o` cost two processes per matching line; with ~1,500
# slash-command lines added that would have tripled the run time.
counts="$(mktemp)"
trap 'rm -f "$truth" "$slash_truth" "$skill_dirs" "$counts"' EXIT
unresolved="$(LC_ALL=C awk -v truthf="$truth" -v slashf="$slash_truth" \
  -v countsf="$counts" -v idre="$id_re" -v slre="$slash_re" '
  FILENAME == truthf { t[$0] = 1; next }
  FILENAME == slashf { s[$0] = 1; next }
  # Blockquote callouts cite dead IDs on purpose.
  /^>/ || /[ \t]>/ { next }
  {
    rest = " " $0
    while (match(rest, idre)) {
      tok = substr(rest, RSTART + 1, RLENGTH - 1)
      ids++
      if (!(tok in t)) print FILENAME "\t" FNR "\tid\t" tok
      rest = substr(rest, RSTART + RLENGTH)
    }
    rest = " " $0
    while (match(rest, slre)) {
      tok = substr(rest, RSTART + 1, RLENGTH - 1)
      key = substr(tok, 2)
      slashes++
      if (!(key in s) && !(key in t)) print FILENAME "\t" FNR "\tslash\t" tok
      rest = substr(rest, RSTART + RLENGTH)
    }
  }
  END { print (ids + 0) " " (slashes + 0) > countsf }
' "$truth" "$slash_truth" "${files[@]}")"

read -r ids_checked slashes_checked <"$counts"

while IFS="$(printf '\t')" read -r file line_no kind id; do
  [ -n "$id" ] || continue
  rel="${file#./}"
  allowed "$id" "$rel" && continue
  if [ "$kind" = "id" ]; then
    printf "ERROR [dead-skill-reference]: %s:%s\n" "$rel" "$line_no"
    printf "  Found: %s\n" "$id"
    # Offer the closest surviving ID under the same plugin, if there is one.
    plugin="${id%%:*}"
    art_name="${id#*:}"
    suggestion="$(grep "^${plugin}:" "$truth" | grep -- "$art_name" | head -1 || true)"
    if [ -n "$suggestion" ]; then
      printf "  Fix:   did you mean %s ?\n\n" "$suggestion"
    else
      printf "  Fix:   no skill or agent with this ID exists; check %s/skills/ and %s/agents/\n\n" "$plugin" "$plugin"
    fi
  else
    printf "ERROR [dead-slash-command]: %s:%s\n" "$rel" "$line_no"
    printf "  Found: %s\n" "$id"
    ns="${id#/}"
    ns="${ns%%:*}"
    art_name="${id#*:}"
    suggestion="$(grep "^${ns}:" "$slash_truth" | grep -- "$art_name" | head -1 || true)"
    if [ -n "$suggestion" ]; then
      printf "  Fix:   did you mean /%s ?\n\n" "$suggestion"
    else
      printf "  Fix:   no skill resolves it; /<ns>:<name> maps to <ns>-plugin/skills/<ns>-<name>/ or <name>/ (.claude/rules/skill-naming.md)\n\n"
    fi
  fi
  errors=$((errors + 1))
done <<<"$unresolved"

if [ "$errors" -gt 0 ]; then
  printf "Found %d dead skill/agent reference(s) or slash command(s) against %s IDs on disk\n" "$errors" "$truth_count"
  exit 1
fi

printf "All skill/agent references and slash commands resolve (%s IDs on disk; %s files, %s IDs and %s slash commands checked)\n" \
  "$truth_count" "${#files[@]}" "$ids_checked" "$slashes_checked"
exit 0
