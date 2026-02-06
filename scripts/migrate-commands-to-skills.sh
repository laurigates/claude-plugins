#!/bin/bash
# Migrate command files to skill directories
# Usage: ./scripts/migrate-commands-to-skills.sh <plugin-dir>
# Example: ./scripts/migrate-commands-to-skills.sh home-assistant-plugin

set -euo pipefail

PLUGIN_DIR="$1"

if [[ ! -d "$PLUGIN_DIR" ]]; then
  echo "Error: Plugin directory '$PLUGIN_DIR' not found"
  exit 1
fi

if [[ ! -d "$PLUGIN_DIR/commands" ]]; then
  echo "No commands/ directory in $PLUGIN_DIR"
  exit 0
fi

# Ensure skills directory exists
mkdir -p "$PLUGIN_DIR/skills"

# Find all command files (handles flat and nested)
find "$PLUGIN_DIR/commands" -name "*.md" -type f | while IFS= read -r cmd_file; do
  # Derive skill name from file path
  # Flat: commands/foo-bar.md -> foo-bar
  # Nested: commands/group/name.md -> group-name
  rel_path="${cmd_file#$PLUGIN_DIR/commands/}"
  skill_name=$(echo "$rel_path" | sed 's|/|-|g' | sed 's|\.md$||')

  skill_dir="$PLUGIN_DIR/skills/$skill_name"

  # Check for collision with existing skill
  if [[ -d "$skill_dir" ]]; then
    echo "COLLISION: $skill_dir already exists, skipping $cmd_file"
    continue
  fi

  echo "Migrating: $cmd_file -> $skill_dir/SKILL.md"

  # Create skill directory
  mkdir -p "$skill_dir"

  # Read the command file and add 'name' field to frontmatter if missing
  if head -1 "$cmd_file" | grep -q "^---"; then
    # Has frontmatter - add name field after first ---
    awk -v name="$skill_name" '
      BEGIN { in_front=0; added_name=0; has_name=0 }
      /^---$/ && !in_front { in_front=1; print; next }
      /^---$/ && in_front {
        if (!has_name) { print "name: " name }
        in_front=0; print; next
      }
      in_front && /^name:/ { has_name=1 }
      { print }
    ' "$cmd_file" > "$skill_dir/SKILL.md"
  else
    # No frontmatter - just copy
    cp "$cmd_file" "$skill_dir/SKILL.md"
  fi

  # Stage the new file and delete the old
  git add "$skill_dir/SKILL.md"
  git rm -q "$cmd_file"
done

# Remove empty commands directory (and any empty subdirs)
find "$PLUGIN_DIR/commands" -type d -empty -delete 2>/dev/null || true
if [[ -d "$PLUGIN_DIR/commands" ]]; then
  # Check if truly empty (no files left)
  remaining=$(find "$PLUGIN_DIR/commands" -type f | wc -l)
  if [[ "$remaining" -eq 0 ]]; then
    rm -rf "$PLUGIN_DIR/commands"
    echo "Removed empty commands/ directory"
  else
    echo "WARNING: commands/ still has $remaining files"
  fi
fi

echo "Migration complete for $PLUGIN_DIR"
