---
created: 2026-04-30
modified: 2026-04-30
reviewed: 2026-04-30
name: dev-tools
description: |
  Obsidian developer commands for plugin and theme development — DevTools,
  Chrome DevTools Protocol, JavaScript eval, captured console/error buffers,
  CSS and DOM inspection, mobile emulation, and screenshots. Use when the
  user is developing a plugin or theme, debugging the Obsidian app, or
  needs to introspect the running renderer state.
user-invocable: false
allowed-tools: Bash(obsidian *), Read, Grep, Glob
---

# Obsidian Developer Tools

## When to Use This Skill

| Use this skill when... | Use the alternative instead when... |
|---|---|
| Developing or debugging a community plugin / theme | Enabling or disabling plugins as a user — use `plugins-themes` |
| Running JavaScript against the live `app` API | Triggering an Obsidian command — use `command-palette` |
| Inspecting CSS or DOM in the running app | Switching themes or snippets in normal use — use `plugins-themes` |
| Capturing console errors during agent-run plugin tests | Reading note content — use `vault-files` |

These commands are **for development and diagnostics**. They expose the same
surface as the in-app DevTools window plus a captured buffer of console
output and JavaScript errors that survives between calls — the leverage
point for agentic plugin testing.

## Prerequisites

- Obsidian desktop v1.12.4+ with CLI enabled
- Obsidian must be running
- For `dev:debug` and `dev:cdp`: Chrome DevTools Protocol available
  (Electron-based Obsidian — true on desktop)

## DevTools Window

```bash
# Toggle the in-app DevTools panel
obsidian devtools
```

## Eval JavaScript

```bash
# Read state from the live app
obsidian eval code="app.vault.getFiles().length"
obsidian eval code="app.workspace.getActiveFile()?.path"

# Drive the app — anything you could type in the DevTools console
obsidian eval code="app.commands.executeCommandById('editor:toggle-bold')"

# Multi-statement: wrap in an IIFE
obsidian eval code="(()=>{const f=app.vault.getFiles();return f.filter(x=>x.extension==='md').length})()"
```

`eval` returns the expression's value (or last statement's value in an IIFE)
serialised to text. Use `JSON.stringify(...)` inside the expression for
structured output you can parse downstream.

## Captured Console & Errors

The CLI maintains rolling buffers of `console.*` calls and JavaScript errors
from the running app — invaluable for agent-driven plugin testing where the
agent doesn't have the DevTools window open.

```bash
# Recent console messages (default limit 50)
obsidian dev:console
obsidian dev:console limit=200
obsidian dev:console level=error
obsidian dev:console level=warn

# Clear the console buffer (e.g. before a test run)
obsidian dev:console clear

# Captured JS errors
obsidian dev:errors
obsidian dev:errors clear
```

Typical agent loop:

```bash
obsidian dev:errors clear
obsidian dev:console clear
obsidian plugin:reload id=my-plugin
obsidian command id=my-plugin:run-test
obsidian dev:errors        # any uncaught exceptions?
obsidian dev:console level=error
```

## CSS Inspection

```bash
# All CSS rules matching a selector, with source location
obsidian dev:css selector=".workspace-leaf"

# Filter to one property
obsidian dev:css selector=".workspace-leaf" prop=background-color
```

Useful for tracking down which snippet or theme is winning a cascade.

## DOM Query

```bash
# First match — full outerHTML
obsidian dev:dom selector=".nav-folder-title"

# Inner HTML only
obsidian dev:dom selector=".nav-folder-title" inner

# Just the text content
obsidian dev:dom selector=".nav-folder-title" text

# All matches (not just the first)
obsidian dev:dom selector=".nav-folder-title" all

# Element count
obsidian dev:dom selector=".nav-folder-title" total

# Read an attribute or computed CSS prop
obsidian dev:dom selector=".workspace-leaf.mod-active" attr=data-type
obsidian dev:dom selector=".workspace-leaf.mod-active" css=display
```

## Chrome DevTools Protocol (CDP)

```bash
# Attach the CDP debugger
obsidian dev:debug on
obsidian dev:debug off

# Run an arbitrary CDP method
obsidian dev:cdp method=Page.captureScreenshot
obsidian dev:cdp method=Runtime.evaluate params='{"expression":"location.href"}'
```

CDP is the right tool when `eval` is too coarse — anything you'd reach for
in `chrome://inspect`.

## Screenshots & Mobile Emulation

```bash
# Capture the running window
obsidian dev:screenshot path=/tmp/state.png

# Toggle mobile emulation (responsive testing without leaving desktop)
obsidian dev:mobile on
obsidian dev:mobile off
```

## Common Patterns

### Plugin reload-test loop

```bash
obsidian dev:console clear
obsidian dev:errors clear
obsidian plugin:reload id=my-plugin
obsidian command id=my-plugin:run-tests
errors=$(obsidian dev:errors)
[ -z "$errors" ] && echo "PASS" || { echo "FAIL"; echo "$errors"; }
```

### Theme regression screenshots

```bash
for theme in Default Minimal Things; do
  obsidian theme:set name="$theme"
  obsidian dev:screenshot path="/tmp/theme-$theme.png"
done
```

### Probe the active workspace

```bash
obsidian eval code="JSON.stringify({file: app.workspace.getActiveFile()?.path, view: app.workspace.activeLeaf?.view?.getViewType()})"
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Run JS, parseable output | `obsidian eval code="JSON.stringify(...)"` |
| Errors since last check | `obsidian dev:errors` |
| Reset error buffer | `obsidian dev:errors clear` |
| Console (errors only) | `obsidian dev:console level=error` |
| DOM element count | `obsidian dev:dom selector=X total` |
| Screenshot for diff | `obsidian dev:screenshot path=/tmp/X.png` |
| CSS source for property | `obsidian dev:css selector=X prop=Y` |

## Related Skills

- **plugins-themes** — Plugin/theme lifecycle (install/enable/reload/disable)
- **command-palette** — Trigger commands the plugin registers
- **workspaces** — Set up the editor state before running diagnostics
