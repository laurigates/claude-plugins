---
model: haiku
created: 2026-03-19
modified: 2026-03-19
reviewed: 2026-03-19
name: playwright-cli
description: |
  Playwright CLI browser automation for AI agents. Navigate pages, take screenshots,
  fill forms, click elements from the command line. Use when automating browser tasks
  with shell access. Prefer over Playwright MCP (4-10x more token-efficient).
user-invocable: false
allowed-tools: Bash, Read, Grep, Glob, TodoWrite
---

# Playwright CLI

Playwright CLI (`@playwright/cli`) is a terminal-first browser automation tool designed for AI coding agents. It provides shell commands for browser control, saving snapshots and screenshots to disk instead of injecting them into the LLM context window.

## When to Use This Skill

| Use this skill when... | Use another skill instead when... |
|------------------------|----------------------------------|
| Automating browser tasks from CLI | Writing E2E test suites (use playwright-testing) |
| Navigating pages, clicking, filling forms | Sandboxed env without shell access (use Playwright MCP) |
| Taking screenshots or PDFs of web pages | Testing across multiple browsers systematically (use playwright-testing) |
| Verifying UI state during development | Setting up testing infrastructure (use configure-ux-testing) |
| Scraping or inspecting page content | Short exploratory sessions needing rich DOM inspection (use MCP) |

## CLI vs MCP

| Factor | Playwright CLI | Playwright MCP |
|--------|---------------|----------------|
| Token cost per task | ~27K tokens | ~114K tokens |
| Schema overhead | ~68 tokens (SKILL.md) | ~3,600 tokens (26 tools) |
| Requires | Shell/Bash access | MCP server config |
| Output | Files on disk | Inline in context |
| Best for | AI agents with shell (Claude Code, Copilot) | Sandboxed envs (Claude Desktop, Cursor) |

**Rule of thumb**: If the agent has Bash access, use CLI. If not, use MCP.

## Installation

```bash
# Global install
npm install -g @playwright/cli@latest

# Project-local
npm install --save-dev @playwright/cli@latest

# Verify
playwright-cli --version

# If global binary not found
npx playwright-cli --version
```

Creates a `.playwright-cli/` directory in the workspace for sessions, snapshots, and screenshots.

## Core Workflow

The typical agent loop is: **snapshot → find ref → interact → snapshot again**.

```bash
# 1. Navigate to page
playwright-cli goto https://example.com

# 2. Capture snapshot (YAML with element refs like e21, e35)
playwright-cli snapshot

# 3. Read the snapshot to find element refs
cat .playwright-cli/snapshot.yaml

# 4. Interact using element refs
playwright-cli click e21
playwright-cli fill e35 "user@example.com"

# 5. Verify result
playwright-cli snapshot
```

## Essential Commands

### Navigation

```bash
playwright-cli open [url]           # Open browser, optionally navigate
playwright-cli goto <url>           # Navigate to URL
playwright-cli go-back              # Browser back
playwright-cli go-forward           # Browser forward
playwright-cli reload               # Reload page
playwright-cli close                # Close page
```

### Interaction (using element refs from snapshots)

```bash
playwright-cli click <ref>          # Click element
playwright-cli dblclick <ref>       # Double-click
playwright-cli fill <ref> <text>    # Fill input field
playwright-cli type <text>          # Type into focused element
playwright-cli hover <ref>          # Hover over element
playwright-cli select <ref> <val>   # Select dropdown option
playwright-cli check <ref>          # Check checkbox
playwright-cli uncheck <ref>        # Uncheck checkbox
playwright-cli drag <start> <end>   # Drag and drop
playwright-cli upload <file>        # Upload file
```

### Keyboard & Mouse

```bash
playwright-cli press Enter          # Press key
playwright-cli press Tab
playwright-cli keydown Shift        # Hold key
playwright-cli keyup Shift          # Release key
playwright-cli mousemove 150 300    # Move mouse to coordinates
```

### Snapshots & Screenshots

```bash
playwright-cli snapshot                        # Page snapshot (YAML)
playwright-cli snapshot --filename=login.yaml  # Named snapshot
playwright-cli screenshot                      # Screenshot (PNG to disk)
playwright-cli pdf output.pdf                  # Save as PDF
```

### Session Management

```bash
playwright-cli -s=myapp goto https://app.com  # Named session
playwright-cli -s=myapp snapshot               # Snapshot in session
playwright-cli list                            # List all sessions
playwright-cli -s=myapp close                  # Close session browser
playwright-cli close-all                       # Close all browsers
playwright-cli kill-all                        # Force kill all
```

### Browser Options

```bash
playwright-cli open --headed             # Visible browser
playwright-cli open --persistent         # Persist cookies across restarts
playwright-cli -s=name delete-data       # Clear session data
```

## Common Patterns

### Form Submission

```bash
playwright-cli goto https://app.com/login
playwright-cli snapshot
# Read snapshot, find email/password/submit refs
playwright-cli fill e12 "user@example.com"
playwright-cli fill e15 "password123"
playwright-cli click e18
playwright-cli snapshot  # Verify redirect
```

### Page Verification

```bash
playwright-cli goto https://app.com/dashboard
playwright-cli screenshot
playwright-cli snapshot
# Read snapshot to verify expected elements are present
```

### Multi-Tab Workflow

```bash
playwright-cli -s=tab1 goto https://docs.example.com
playwright-cli -s=tab2 goto https://app.example.com
playwright-cli -s=tab1 snapshot  # Read docs
playwright-cli -s=tab2 fill e5 "value from docs"
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Navigate and verify | `playwright-cli goto <url> && playwright-cli snapshot` |
| Quick visual check | `playwright-cli goto <url> && playwright-cli screenshot` |
| Fill form field | `playwright-cli fill <ref> '<value>'` |
| Click and snapshot | `playwright-cli click <ref> && playwright-cli snapshot` |
| Save page as PDF | `playwright-cli goto <url> && playwright-cli pdf out.pdf` |
| Persistent session | `playwright-cli open --persistent && playwright-cli goto <url>` |
| Named session | `playwright-cli -s=name goto <url>` |
| Clean up | `playwright-cli close-all` |

## Output Behavior

| Command Type | Output |
|--------------|--------|
| snapshot | YAML file saved to `.playwright-cli/` |
| screenshot, pdf | File saved to `.playwright-cli/` |
| click, fill, type | No output (modifies browser state) |
| list | Session list to stdout |
| goto, reload | No output (navigates) |

Snapshots and screenshots are saved to disk — the agent reads them only when needed, keeping token usage minimal.

## See Also

- **playwright-testing** — E2E test framework patterns (`@playwright/test`)
- **configure-ux-testing** — Set up Playwright infrastructure
- Official docs: https://playwright.dev
- CLI repo: https://github.com/microsoft/playwright-cli
- npm: https://www.npmjs.com/package/@playwright/cli
