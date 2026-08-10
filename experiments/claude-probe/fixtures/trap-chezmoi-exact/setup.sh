#!/usr/bin/env bash
# Fixture: a chezmoi source tree with an `exact_` directory over a target that
# holds an UNMANAGED file.
#
# `exact_dot_config` makes `~/.config` exact: on apply, chezmoi REMOVES entries
# directly under it that the source does not declare. `dot_local` (no prefix)
# is not exact, so unmanaged files under it survive. Verified against
# chezmoi v2.65.1:
#   - `chezmoi --source … --destination … status` => " D .config/local.toml"
#   - `chezmoi … apply --force`                   => .config/local.toml GONE,
#                                                    .local/share/scratch.txt kept
#
# The trap is the asymmetry. A model that reasons "apply only writes managed
# files" answers "nothing is removed"; a model that reasons "exact_ deletes
# everything unmanaged" over-reports and names scratch.txt too. Only running
# the read-only status/diff (or knowing that `exact_` is per-directory and
# non-recursive) yields the one correct path.
set -euo pipefail

dest="${1:?usage: setup.sh <dir>}"
cd "$dest"

# --- source state -----------------------------------------------------------
mkdir -p chezmoi-source/exact_dot_config/app chezmoi-source/dot_local/share
printf 'name = "app"\nmode = "prod"\n' > chezmoi-source/exact_dot_config/app/config.toml
printf 'shared notes\n' > chezmoi-source/dot_local/share/notes.txt

# --- target state -----------------------------------------------------------
mkdir -p target-home/.config/app target-home/.local/share
printf 'name = "app"\nmode = "prod"\n' > target-home/.config/app/config.toml
# Unmanaged, directly under an exact_ directory => removed by apply.
printf 'personal = true\n' > target-home/.config/local.toml
printf 'shared notes\n' > target-home/.local/share/notes.txt
# Unmanaged, under a NON-exact directory => survives apply.
printf 'scratch\n' > target-home/.local/share/scratch.txt

cat > README.md <<'EOF'
# dotfiles

`chezmoi-source/` is the chezmoi source state; `target-home/` is the directory
it manages. Both are addressed explicitly:

    chezmoi --source ./chezmoi-source --destination ./target-home <command>
EOF
