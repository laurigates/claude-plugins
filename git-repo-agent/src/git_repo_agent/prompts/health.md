# Health Command

Quick health check for a repository. Runs repo analysis and health scoring without subagent delegation or LLM calls.

## Output Sections

### Header
Repository name, path, and date.

### Health Score
Overall score (0-100) with letter grade and color-coded bar.

### Category Breakdown
Table of 5 categories (docs, tests, security, quality, ci) each scored 0-20.

### Findings
Grouped by category, listing specific issues found.

### Grade Scale
| Grade | Range | Meaning |
|-------|-------|---------|
| A | 90-100 | Excellent — well-maintained |
| B | 80-89 | Good — minor improvements possible |
| C | 70-79 | Needs work — several gaps |
| D | 60-69 | Poor — significant gaps |
| F | < 60 | Critical — major issues |
