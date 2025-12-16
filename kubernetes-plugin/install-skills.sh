#!/usr/bin/env bash
# Install Kubernetes Plugin Skills
# This script copies the skills from chezmoi source directory to the plugin

set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="/Users/lgates/.local/share/chezmoi/exact_dot_claude/skills"
SKILLS_DIR="$PLUGIN_DIR/skills"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Skills to copy
SKILLS=(
  "kubernetes-operations"
  "helm-chart-development"
  "helm-debugging"
  "helm-release-management"
  "helm-release-recovery"
  "helm-values-management"
  "argocd-login"
)

echo -e "${BLUE}Installing Kubernetes Plugin Skills${NC}"
echo "======================================"
echo ""
echo "Source: $SOURCE_DIR"
echo "Target: $SKILLS_DIR"
echo ""

# Create skills directory if it doesn't exist
mkdir -p "$SKILLS_DIR"

# Copy each skill
for skill in "${SKILLS[@]}"; do
  echo -ne "${BLUE}Copying ${skill}...${NC}"

  if [ -d "$SOURCE_DIR/$skill" ]; then
    cp -r "$SOURCE_DIR/$skill" "$SKILLS_DIR/"
    echo -e " ${GREEN}✓${NC}"
  else
    echo -e " ${RED}✗ Not found${NC}"
    exit 1
  fi
done

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Plugin structure:"
tree -L 2 "$PLUGIN_DIR" 2>/dev/null || find "$PLUGIN_DIR" -type d -maxdepth 2

echo ""
echo "To use this plugin:"
echo "  claude plugins add $PLUGIN_DIR"
