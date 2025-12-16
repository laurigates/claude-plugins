---
allowed-tools: Glob, Read, TodoWrite
description: Audit Claude subagent configurations for completeness, security, and best practices
argument-hint: "[--verbose]"
---

## Context

- Agent definitions: !`find .claude/agents -name "*.md" -not -name "settings*"`
- Settings file: !`find .claude/agents -maxdepth 1 -name "settings.local.json" -type f`

## Your task

### 1. Discovery Phase
- Use **Glob** to find all agent definition files in `.claude/agents/`
- Read each agent file to extract frontmatter and configuration
- Identify the settings.local.json for permission overrides

### 2. Frontmatter Validation
For each agent, verify required fields are present:
- ✅ **name**: Agent identifier (must match filename)
- ✅ **model**: Claude model to use (e.g., "claude-sonnet-4-5")
- ✅ **color**: Hex color code for UI (e.g., "#E53E3E")
- ✅ **description**: Clear usage guidance with "Use proactively when..."
- ✅ **tools**: Tool list or "All" for full access

**Flag issues:**
- Missing required fields
- Mismatched name vs filename
- Invalid model names
- Malformed color codes

### 3. Tool Assignment Analysis
Evaluate tool assignments for security and appropriateness:

**Read-only agents** (should NOT have write access):
- research-documentation
- code-analysis (read + vectorcode only)
- code-review (read + LSP only)
- security-audit (read + LSP + Bash for scanning)

**Write-enabled agents** (appropriate write access):
- code-refactoring (Edit, MultiEdit)
- documentation (Write, MultiEdit)
- cicd-pipelines (Write, Edit, GitHub)

**Special privileges** (validate necessity):
- Bash access (security-audit, system-debugging, cicd-pipelines, test-architecture)
- GitHub access (cicd-pipelines, commit-review)
- Zen MCP access (system-debugging only)
- All tools access (should be rare, validate justification)

**LSP tool assignments** (language-specific):
- Verify LSP tools match agent's language focus
- security-audit should have broad LSP coverage (6+ servers)
- code-review should have multi-language LSP support
- code-analysis should have appropriate LSP access

### 4. Security Assessment
Check for potential security issues:

**Overprivileged agents:**
- Agents with "All" tools without clear justification
- Read-only agents with write/edit capabilities
- Unnecessary Bash or GitHub access
- Research agents with modification permissions

**Missing restrictions:**
- settings.local.json should have deny rules for destructive operations
- Allow list should be minimal and specific
- No wildcard tool access unless justified

**Privilege escalation risks:**
- Agents that can modify other agent configs
- Agents with both read and execute permissions
- Cross-agent permission leakage

### 5. Consistency Checks
Validate configuration consistency:

**Naming conventions:**
- Agent names use kebab-case
- Filenames match agent names
- Descriptions follow consistent format

**Model assignments:**
- All agents use appropriate Claude models
- No deprecated model references
- Consistent model selection strategy

**Tool groupings:**
- Similar agents have similar tool sets
- No duplicate or redundant tool assignments
- Clear separation of concerns

### 6. Report Generation
Create comprehensive audit report with:

**Executive Summary:**
- Total agents audited
- Critical issues found
- Security concerns
- Overall health rating

**Detailed Findings:**
- ❌ **Critical**: Missing required fields, security violations
- ⚠️ **Warnings**: Overprivileged agents, inconsistencies
- ℹ️ **Info**: Best practice suggestions, optimization opportunities

**Agent-by-Agent Analysis:**
For each agent, report:
- Configuration completeness (✅/❌ for each required field)
- Tool assignment appropriateness (✅/⚠️/❌)
- Security assessment (safe/review/risk)
- Recommendations for improvement

**Action Items:**
- Immediate fixes required (with file paths and line numbers)
- Optional improvements
- Configuration validation passed/failed

### 7. Output Format

Structure the report as:

```markdown
# Claude Agent Configuration Audit

## Executive Summary
- **Total Agents**: X
- **Configuration Issues**: Y
- **Security Concerns**: Z
- **Health Rating**: [EXCELLENT|GOOD|NEEDS_WORK|CRITICAL]

## Critical Issues
[List any critical problems requiring immediate fix]

## Agent Analysis Table
| Agent | Model | Tools | Color | Status | Notes |
|-------|-------|-------|-------|--------|-------|
| agent-name | ✅/❌ | ✅/⚠️/❌ | ✅/❌ | PASS/FAIL | Issues |

## Security Assessment
[Tool privilege analysis and security concerns]

## Recommendations
[Prioritized action items with file paths]

## Detailed Findings
[Per-agent breakdown with specific issues]
```

### 8. Best Practices Reference

**Tool access principles:**
- Least privilege principle for tool access
- Clear separation between read-only and write-enabled agents
- Appropriate LSP tool coverage for language-specific work
- Minimal Bash access (only when required)
- Restricted GitHub access (only for git-ops and CI/CD)

**Configuration standards:**
- All required frontmatter fields present
- Consistent model selections across agents
- Appropriate tool permissions for agent role
- Clear descriptions with proactive usage guidance

### 9. Optional: Verbose Mode

If `--verbose` flag is provided:
- Show full frontmatter for each agent
- Display complete tool lists
- Include settings.local.json content
- Provide detailed fix commands for each issue

## Notes

- This is a **read-only audit** - modifications require explicit user request
- Focus on configuration correctness and security implications
- Provide actionable recommendations with specific file locations
- Use TodoWrite to track audit progress if checking multiple agents
