# shell-commands.awk -- shared "does this line run shell?" recognition.
#
# One definition of what counts as a shell command in skill markdown, used by:
#   scripts/check-unused-bash-grant.sh  (does a skill run any shell at all?)
#   scripts/skill-shell-commands.py     (which commands does it run? #3464)
# Factored out of check-unused-bash-grant.sh so the two cannot drift: a command
# the unused-grant lint accepts as "runs shell" is exactly a command the
# grant helper lists, and vice versa.
#
# Load it with `awk -f scripts/lib/shell-commands.awk -f <your program>`. It
# defines functions and one rule, and that rule fires only when the caller sets
# `-v mode=segments`, so a program that includes the library for its functions
# is unaffected by it. Works in mawk, gawk and BSD awk (no gawk extensions).
#
# Functions:
#   strip_cmd(s)      drop leading space, a "$ " prompt, a `sudo`, and
#                     ENV=val prefixes; returns what is left
#   is_command(s)     1 when s (after strip_cmd) starts with a known command or
#                     an executable path form, else 0
#   is_shell_lang(l)  1 for a shell-ish fence info string OR an empty one
#                     (unlabeled fences carry real commands in ~30 skills)
#
# mode=segments rule. Input rows, tab-separated:
#   id  src_type  lang  seg_idx  text
# src_type is fence_line, inline_code or bang (a !`...` Context command).
# seg_idx 0 is the start of the source line; 1.. are later pipeline/list
# segments or $(...) bodies the caller split out. Output rows:
#   id  seg_idx  is_cmd  stripped_text
# is_cmd for seg 0 also requires the source to be eligible (a shell-ish or
# unlabeled fence, or an inline span); a bang seg 0 is always a command.

BEGIN {
  KNOWN_CMDS = "git|gh|glab|bash|sh|zsh|fish|source|export|cd|pushd|popd|python|python3|uv|uvx|pip|pipx|node|npm|npx|bun|bunx|yarn|pnpm|deno|cargo|rustup|go|gofmt|make|just|task|docker|podman|nerdctl|kubectl|helm|kustomize|skaffold|argocd|terraform|tofu|tflint|ansible|vagrant|jq|yq|rg|fd|sed|awk|grep|egrep|find|ls|cat|head|tail|cut|sort|uniq|wc|tr|xargs|tee|diff|patch|cp|mv|rm|mkdir|rmdir|touch|ln|chmod|chown|stat|realpath|basename|dirname|pwd|echo|printf|read|test|curl|wget|ssh|scp|rsync|tar|unzip|zip|gzip|gunzip|openssl|base64|shasum|sha256sum|md5sum|date|sleep|env|which|type|command|pytest|tox|nox|ruff|black|mypy|ty|basedpyright|vulture|biome|eslint|prettier|oxlint|oxfmt|tsc|vitest|jest|playwright|cypress|knip|stylua|shellcheck|shfmt|actionlint|gitleaks|trufflehog|semgrep|bandit|pre-commit|mise|asdf|brew|apt|apt-get|systemctl|launchctl|defaults|osascript|pmset|powermetrics|ps|top|kill|pkill|lsof|netstat|ss|ip|ifconfig|dig|nslookup|ping|traceroute|nmap|d2|mmdc|ffmpeg|magick|convert|identify|odiff|comfy|obsidian|telegram-notify|telegram-ask|telegram-poll|hyperfine|watch|tmux|kitty|open|code|nvim|vim"
}

function strip_cmd(s) {
  sub(/^[[:space:]]+/, "", s)
  sub(/^\$[[:space:]]+/, "", s)          # a "$ cmd" prompt line
  sub(/^sudo[[:space:]]+/, "", s)
  while (s ~ /^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/)   # ENV=val prefixes
    sub(/^[A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+/, "", s)
  return s
}

function is_command(s) {
  s = strip_cmd(s)
  if (s == "") return 0
  if (s ~ /^#/) return 0                  # comment
  if (s ~ /^\//) return 0                 # a /slash:command (or an absolute path used as prose)
  if (s ~ /^\.\//) return 1               # ./script.sh
  if (s ~ /^\.venv\//) return 1           # .venv/bin/python
  if (s ~ /^\.[a-zA-Z0-9_-]+\//) return 1 # any dot-dir-relative executable
  # An executable reached through a PLACEHOLDER or variable path prefix. Docs
  # routinely write the interpreter that way and it is still a real command:
  #   <venv>/bin/python -c "..."      (comfy-subgraphs-app-mode)
  #   ${CLAUDE_SKILL_DIR}/scripts/x.sh
  #   ~/bin/tool
  if (s ~ /^<[^>]+>\//) return 1
  if (s ~ /^\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\//) return 1
  # ...and the same variable path quoted, run directly (#3464: video-thumbnail
  # runs "${CLAUDE_SKILL_DIR}/scripts/thumbnail.sh" and showed no command).
  if (s ~ /^["']\$\{?[A-Za-z_][A-Za-z0-9_]*\}?\//) return 1
  if (s ~ /^~\//) return 1
  return (s ~ ("^(" KNOWN_CMDS ")([[:space:]]|$)"))
}

function is_shell_lang(lang) {
  lang = tolower(lang)
  return (lang == "" || lang ~ /^(bash|sh|shell|zsh|console|shell-session|shellsession|fish|command|terminal)$/)
}

mode == "segments" {
  src = $2; lang = $3; idx = $4; text = $5
  ok = 0
  if (idx == 0) {
    if (src == "bang") ok = 1
    else if (src == "fence_line") ok = (is_shell_lang(lang) && is_command(text))
    else if (src == "inline_code") ok = is_command(text)
  } else {
    ok = is_command(text)
  }
  print $1 "\t" idx "\t" ok "\t" strip_cmd(text)
}
