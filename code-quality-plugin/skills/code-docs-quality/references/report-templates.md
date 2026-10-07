# Documentation Quality Report Templates

### 8.1 Documentation Inventory

Generate a summary table:

```markdown
## Documentation Inventory

| Document Type | Status | Count | Issues |
|---------------|--------|-------|--------|
| CLAUDE.md | ✅/❌ | 1 | [list issues] |
| .claude/rules/ | ✅/❌ | N files | [list issues] |
| ADRs | ✅/❌ | N files | [list issues] |
| PRDs | ✅/❌ | N files | [list issues] |
| PRPs | ✅/❌ | N files | [list issues] |
```

### 8.2 Quality Score

Calculate an overall quality score:

| Category | Score (0-10) | Notes |
|----------|--------------|-------|
| Structure | X | File organization, naming |
| Completeness | X | Required sections present |
| Freshness | X | Recent updates, git sync |
| Standards Compliance | X | Frontmatter, format |
| Content Quality | X | Clarity, specificity |
| **Overall** | **X** | Average score |

**Rating Guide**:
- 9-10: Excellent - Well-maintained, comprehensive
- 7-8: Good - Minor improvements needed
- 5-6: Fair - Several issues to address
- 3-4: Poor - Major gaps or outdated
- 0-2: Critical - Missing or severely lacking

### 8.3 Issues and Recommendations

Categorize findings:

**Critical Issues** (must fix):
- Missing required documentation
- Severe structural problems
- Completely outdated information

**Warnings** (should fix):
- Stale documentation (>6 months)
- Missing frontmatter
- Incomplete sections
- Minor structural issues

**Suggestions** (nice to have):
- Additional documentation that would help
- Improved organization
- Better cross-referencing
- Enhanced examples

### 8.4 Actionable Recommendations

For each issue, provide specific guidance:

```markdown
## Recommendations

### Immediate Actions
1. [ ] Fix [specific issue] in [file]
   - **Why**: [reason]
   - **How**: [specific steps]
   - **Command**: [if applicable]

2. [ ] Update [document]
   - **Why**: [reason]
   - **How**: [specific steps]

### Maintenance Tasks
1. [ ] Review and update stale documents:
   - [file1] - last modified [date]
   - [file2] - last modified [date]

2. [ ] Improve documentation coverage:
   - [ ] Document [undocumented decision]
   - [ ] Create ADR for [architectural choice]

### Best Practices
- Run `/code:docs-quality` monthly
- Update `modified` dates when editing docs
- Review `reviewed` dates quarterly
- Use `/blueprint:adr` for new architecture decisions
- Use `/blueprint:prd` for new features
```

### 9.1 Executive Summary
Show a clear, concise summary:

```
📊 Documentation Quality Report
═══════════════════════════════

Overall Score: X/10 ([Excellent/Good/Fair/Poor/Critical])

✅ Strengths:
- [strength 1]
- [strength 2]

⚠️  Issues Found:
- [issue 1]
- [issue 2]

📋 Recommendations:
- [top recommendation 1]
- [top recommendation 2]

See full report below for details.
```
