# Tools Plugin

General development utilities for Claude Code - fd, rg, jq, yq, nushell, shell, imagemagick, mermaid, d2.

## Overview

Collection of general-purpose development utilities for file finding, text search, data processing, and more.

## Commands

| Command | Description |
|---------|-------------|
| `/deps:install` | Universal dependency installer - auto-detects package manager |
| `/generate-image` | Generate images using Nano Banana Pro (Gemini 3 Pro Image) |
| `/handoffs` | List, filter, and manage @AGENT-HANDOFF-MARKER markers |

## Skills

### File & Search

| Skill | Description |
|-------|-------------|
| `fd-file-finding` | Fast file finding using fd |
| `rg-code-search` | Fast code search using ripgrep |

### Data Processing

| Skill | Description |
|-------|-------------|
| `nushell-data-processing` | Structured data processing with native tables (JSON, YAML, CSV, TOML) |
| `jq-json-processing` | JSON querying and transformation with jq |
| `yq-yaml-processing` | YAML querying and transformation with yq |

### System

| Skill | Description |
|-------|-------------|
| `shell-expert` | Shell scripting and bash patterns |
| `justfile-expert` | Just command runner and recipe development |
| `imagemagick-conversion` | Image conversion and manipulation |

### Diagrams

| Skill | Description |
|-------|-------------|
| `mermaid-diagrams` | Generate diagrams from text using Mermaid CLI (flowcharts, sequence, ERD, class) |
| `d2-diagrams` | Modern text-to-diagram language with themes, layouts, and advanced styling |

## Usage Examples

### Find Files

```bash
fd -e ts                    # Find TypeScript files
fd -t f config              # Find files with "config" in name
fd -e md -x head -5         # Preview markdown files
```

### Search Code

```bash
rg "TODO|FIXME"             # Find all TODOs
rg -t py "def.*async"       # Find async functions in Python
rg -l "import React"        # List files importing React
```

### Process JSON

```bash
cat data.json | jq '.items[] | .name'
jq -r '.dependencies | keys[]' package.json
```

### Process YAML

```bash
yq '.services' docker-compose.yml
yq -i '.version = "2.0"' config.yaml
```

### Process Structured Data (Nushell)

```bash
# Visual table output
nu -c 'open package.json | get dependencies | transpose name version'

# Cross-file comparison
nu -c 'open .release-please-manifest.json | transpose plugin version | sort-by plugin'

# Multi-format conversion
nu -c 'open config.yaml | to json'
```

### Run Project Tasks (Justfile)

```bash
just                        # Show available recipes
just test                   # Run tests
just lint                   # Run linters
just build                  # Build project
just dev                    # Development mode with watch
```

### Generate Diagrams (Mermaid)

```bash
mmdc -i diagram.mmd -o diagram.svg    # Convert to SVG
mmdc -i diagram.mmd -o diagram.png    # Convert to PNG
mmdc -i diagram.mmd -o out.svg -t dark # Dark theme
```

### Generate Diagrams (D2)

```bash
d2 diagram.d2 diagram.svg             # Convert to SVG
d2 --watch --browser diagram.d2       # Live preview
d2 -t 101 diagram.d2 out.svg          # Themed output
d2 --sketch diagram.d2 out.svg        # Hand-drawn style
```

### Universal Dependency Install

```bash
/deps:install               # Auto-detects and uses npm/yarn/pnpm/uv/cargo
/deps:install axios --dev   # Install as dev dependency
```

## Installation

```bash
/plugin install tools-plugin@laurigates-claude-plugins
```

## License

MIT
