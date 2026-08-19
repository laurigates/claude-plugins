# Documentation Plugin

Documentation generation, synchronization, and knowledge management for Claude Code projects.

## Overview

Comprehensive documentation tooling for generating API references, maintaining README files, synchronizing docs with codebase, creating decommission plans, converting Markdown to LaTeX PDFs, and keeping published docs honest — link to the single source of truth, verify machine-read facts, and recover failed doc fetches.

## Skills

| Skill | Description |
|-------|-------------|
| `/docs:sync` | Synchronize documentation with actual skills, commands, and agents in codebase |
| `/docs:generate` | Update project documentation from code annotations |
| `/docs:decommission` | Generate comprehensive service decommission documentation |
| `/docs:latex` | Convert Markdown documents to professional LaTeX with TikZ visualizations and compile to PDF |
| `/docs:fetch-fallbacks` | Recover a failed WebFetch: strip the query, `raw.githubusercontent`, `gh api`, context7/WebSearch |
| `claude-blog-sources` | Access Claude Blog for latest features, patterns, and best practices |
| `docs-single-source` | Link docs to the single source of truth instead of restating it |
| `docs-verify-machine-facts` | Verify machine-read values (`scutil`, `route`, `ifconfig`, local config) against the authoritative IaC before publishing |

## Agents

| Agent | Description |
|-------|-------------|
| `documentation` | Generate documentation from code annotations and API references |
| `research-documentation` | Perform documentation lookup and technical research |

## Usage Examples

### Sync Documentation

Keep your documentation in sync with the actual codebase:

```bash
# Sync all documentation
/docs:sync

# Sync only skills documentation
/docs:sync --scope skills

# Preview changes without modifying
/docs:sync --dry-run
```

### Generate Project Documentation

Create comprehensive documentation from your code:

```bash
# Generate all documentation
/docs:generate

# Generate API reference only
/docs:generate --api

# Update README from code analysis
/docs:generate --readme

# Generate changelog from git history
/docs:generate --changelog
```

### Create Decommission Plan

Generate a decommission checklist for a service:

```bash
/docs:decommission my-service-name
```

Creates `DECOMMISSION-my-service-name.md` with comprehensive checklists for:
- Infrastructure resources
- Data management
- Access and security
- DNS and networking
- Integration dependencies
- Monitoring cleanup
- Documentation archival

### Convert Markdown to LaTeX PDF

Convert Markdown documents to professional, print-ready LaTeX PDFs with visualizations:

```bash
# Convert a roadmap document with visualizations
/docs:latex docs/ROADMAP.md --visualizations --report-type=roadmap

# Convert a project lifecycle report
/docs:latex docs/PROJECT_REPORT.md --report-type=lifecycle

# Generate LaTeX source only (no PDF compilation)
/docs:latex docs/DOCUMENT.md --no-compile
```

Produces professional documents with:
- TikZ timeline diagrams and charts
- Color-coded priority indicators
- Styled callout boxes (info, warning, success)
- Professional tables with booktabs
- Hyperlinked table of contents

### Recover a Failed Doc Fetch

When a `WebFetch` returns 404/403 or times out, walk the fallback ladder instead of retrying the same URL:

```bash
/docs:fetch-fallbacks
```

Reads the failure signature and applies the matching fallback — strip the query string, rewrite to `raw.githubusercontent.com`, fall back to `gh api repos/<owner>/<repo>/contents/<path>`, then context7 or `WebSearch`. Stops at two attempts.

### Keep Published Docs Honest

Two reference skills load automatically while you write:

- `docs-single-source` — link to the single source of truth rather than restating it, so the copy cannot drift
- `docs-verify-machine-facts` — check values read off your own host (`ifconfig`, `scutil --dns`, `route get`, local config) against the authoritative IaC before they reach shared docs

## Workflow Integration

### Documentation-First Development

1. Create documentation before implementation
2. Use `/docs:generate` to extract API docs from code
3. Keep docs in sync with `/docs:sync` after changes
4. Research patterns with `claude-blog-sources` skill
5. Link rather than duplicate (`docs-single-source`) and verify host-read facts (`docs-verify-machine-facts`) before publishing

### Service Lifecycle

1. **Deployment**: Create decommission plan with `/docs:decommission`
2. **Development**: Generate docs with `/docs:generate`
3. **Maintenance**: Sync docs with `/docs:sync`
4. **Decommissioning**: Follow the decommission checklist

### Research Workflow

Use the `research-documentation` agent for:
- Finding up-to-date library documentation
- Searching implementation guides
- Retrieving technical specifications
- Comparing technologies

## Companion Plugins

Works well with:
- **project-plugin** - For project initialization and structure
- **git-plugin** - For committing documentation changes
- **testing-plugin** - For documenting test strategies
- **blog-plugin** - For technical write-ups that can be converted to LaTeX

## Installation

```bash
/plugin install documentation-plugin@laurigates-claude-plugins
```

## License

MIT
