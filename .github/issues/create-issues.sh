#!/usr/bin/env bash
# Creates GitHub issues for the Blueprint Maintenance Workflows plan.
# Requires: gh CLI authenticated with repo access
#
# Usage: .github/issues/create-issues.sh
#
# Issues are created with labels and cross-referenced via a tracking issue.

set -euo pipefail

REPO="laurigates/claude-plugins"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure labels exist
ensure_label() {
  local label_name="$1"
  local color="$2"
  local description="$3"
  gh label create "$label_name" --color "$color" --description "$description" --repo "$REPO" 2>/dev/null || true
}

echo "Ensuring labels exist..."
ensure_label "blueprint-maintenance" "0E8A16" "Blueprint documentation maintenance"
ensure_label "github-actions" "1D76DB" "GitHub Actions workflows"
ensure_label "plugin-infrastructure" "D4C5F9" "Plugin metadata and configuration"
ensure_label "automation-enablement" "FBCA04" "Enabling automation of manual tasks"
ensure_label "skill-quality" "F9D0C4" "Skill quality standards"
ensure_label "compliance" "C2E0C6" "Infrastructure compliance"
ensure_label "configure-plugin" "BFD4F2" "Configure plugin related"
ensure_label "blueprint-plugin" "0E8A16" "Blueprint plugin related"

# Track created issue numbers
declare -a ISSUE_NUMBERS=()
declare -a ISSUE_TITLES=()

create_issue() {
  local file="$1"
  local title="$2"
  local labels="$3"

  echo "Creating: $title"

  # Extract body (skip the first line which is the markdown title)
  local body
  body=$(tail -n +2 "$SCRIPT_DIR/$file")

  local issue_url
  issue_url=$(gh issue create \
    --repo "$REPO" \
    --title "$title" \
    --label "$labels" \
    --body "$body")

  local issue_num
  issue_num=$(echo "$issue_url" | grep -oP '\d+$')
  ISSUE_NUMBERS+=("$issue_num")
  ISSUE_TITLES+=("$title")
  echo "  Created: #$issue_num"
}

# Create issues in dependency order
create_issue \
  "04-add-dry-run-modes-to-blueprint-skills.md" \
  "Add --dry-run / --report-only modes to Blueprint skills for CI automation" \
  "enhancement,blueprint-plugin,automation-enablement"

create_issue \
  "01-release-pr-documentation-audit.md" \
  "Workflow: Release PR documentation audit" \
  "enhancement,github-actions,blueprint-maintenance"

create_issue \
  "02-weekly-blueprint-health-check.md" \
  "Workflow: Weekly Blueprint health check" \
  "enhancement,github-actions,blueprint-maintenance"

create_issue \
  "03-plugin-compliance-gate.md" \
  "Workflow: Plugin compliance gate for PRs" \
  "enhancement,github-actions,plugin-infrastructure"

create_issue \
  "05-agentic-quality-audit-workflow.md" \
  "Workflow: Monthly agentic quality audit" \
  "enhancement,github-actions,skill-quality"

create_issue \
  "06-configure-status-compliance-dashboard.md" \
  "Workflow: Infrastructure compliance dashboard" \
  "enhancement,github-actions,compliance,configure-plugin"

echo ""
echo "All issues created. Creating tracking issue..."

# Create tracking issue that references all others
TRACKING_BODY=$(cat <<EOF
## GitHub Workflows for Blueprint Maintenance

Tracking issue for automated maintenance workflows using Claude Code Action with the haiku model.

### Goal

Run Blueprint plugin maintenance skills as GitHub Actions workflows to provide continuous documentation upkeep (ADRs, PRDs, PRPs) and infrastructure compliance checking.

### Phases

#### Phase 0: Automation Enablement (prerequisite)
- [ ] #${ISSUE_NUMBERS[0]} — ${ISSUE_TITLES[0]}

#### Phase 1: PR-Triggered Workflows
- [ ] #${ISSUE_NUMBERS[1]} — ${ISSUE_TITLES[1]}
- [ ] #${ISSUE_NUMBERS[3]} — ${ISSUE_TITLES[3]}

#### Phase 2: Scheduled Maintenance
- [ ] #${ISSUE_NUMBERS[2]} — ${ISSUE_TITLES[2]}
- [ ] #${ISSUE_NUMBERS[4]} — ${ISSUE_TITLES[4]}
- [ ] #${ISSUE_NUMBERS[5]} — ${ISSUE_TITLES[5]}

### Architecture

| Workflow | Trigger | Model | Focus |
|----------|---------|-------|-------|
| Doc Audit | Release PRs | haiku | ADR/PRD/PRP freshness |
| Blueprint Health | Weekly schedule | haiku | Document inventory + validation |
| Compliance Gate | PRs (plugin changes) | haiku | Metadata sync + skill quality |
| Quality Audit | Monthly schedule | haiku | Agentic optimization standards |
| Compliance Dashboard | Bi-monthly schedule | haiku | Infrastructure standards |

### Design Principles

- **haiku for everything**: All maintenance workflows use haiku — these are mechanical checks, not complex reasoning
- **Read-only by default**: Workflows report findings but never modify files
- **Complement existing workflows**: Extends \`skill-quality-review.yml\`, \`validate-plugin-configs.yml\`, \`changelog-review.yml\`
- **Standardized reports**: Consistent markdown format across all workflow outputs

### Dependencies

- \`anthropics/claude-code-action@v1\` (already used in \`claude.yml\`, \`skill-quality-review.yml\`)
- \`CLAUDE_CODE_OAUTH_TOKEN\` secret (already configured)
EOF
)

gh issue create \
  --repo "$REPO" \
  --title "Blueprint maintenance workflows — tracking issue" \
  --label "enhancement,github-actions,blueprint-maintenance" \
  --body "$TRACKING_BODY"

echo ""
echo "Done! All issues created with tracking issue."
