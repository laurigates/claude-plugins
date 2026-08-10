#!/usr/bin/env bash
# Fixture: a `${v##*#}` strip that is fine in bash and FATAL in zsh under
# `setopt extended_glob`.
#
# extended_glob makes `#` a pattern operator (zero-or-more of the preceding
# unit), so the pattern `*#` is not "anything up to a literal hash" — it is a
# malformed repetition. Verified on zsh 5.9:
#   setopt extended_glob; entry='deploy#2026-08-10#green'
#     ${entry##*#}    => zsh: bad pattern: *#   (script ABORTS, exit 1)
#     ${entry##*\#}   => green
#     ${entry##*"#"}  => green
#     ${entry##*'#'}  => green
#   without extended_glob, and in bash, ${entry##*#} => green
#
# The trap is that the expansion is textbook-correct POSIX and is exercised
# every day in bash without complaint, so the natural reading of the script is
# "this is fine". The fix must keep extended_glob on — disabling it is the
# plausible wrong answer, since other scripts in a repo that sets it rely on
# the option globally.
set -euo pipefail

dest="${1:?usage: setup.sh <dir>}"
cd "$dest"
mkdir -p bin

cat > bin/parse-channel.zsh <<'EOF'
#!/usr/bin/env zsh
# Extract the deploy channel: the segment after the last '#'.
# The deploy host's shell profile sets `extended_glob` for every script.
setopt extended_glob

entry='deploy#2026-08-10#green'
channel=${entry##*#}

print -r -- "CHANNEL=$channel"
EOF
chmod +x bin/parse-channel.zsh

# The same logic, as it was prototyped and "verified" in bash.
cat > bin/parse-channel-prototype.sh <<'EOF'
#!/usr/bin/env bash
entry='deploy#2026-08-10#green'
channel=${entry##*#}
echo "CHANNEL=$channel"
EOF
chmod +x bin/parse-channel-prototype.sh

cat > README.md <<'EOF'
# deploy-tools

`bin/parse-channel.zsh` reads the deploy channel out of a release entry — the
segment after the last `#`. It should print `CHANNEL=green`.

The deploy host runs zsh and its shell profile sets `extended_glob` for every
script; that option is relied on elsewhere and has to stay on.

The same expansion was prototyped in `bin/parse-channel-prototype.sh` and works
there, which is why the zsh version was assumed correct.
EOF
