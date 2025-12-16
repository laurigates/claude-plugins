# Tools Plugin

General development utilities for Claude Code - fd, rg, jq, yq, shell, imagemagick, vectorcode.

## Overview

Collection of general-purpose development utilities for file finding, text search, data processing, and more.

## Commands

| Command | Description |
|---------|-------------|
| `/deps:install` | Universal dependency installer - auto-detects package manager |
| `/tools:vectorcode` | Initialize VectorCode with automatic configuration |
| `/generate-image` | Generate images using Nano Banana Pro (Gemini 3 Pro Image) |
| `/handoffs` | List, filter, and manage @HANDOFF markers |

## Skills

### File & Search

| Skill | Description |
|-------|-------------|
| `fd-file-finding` | Fast file finding using fd |
| `rg-code-search` | Fast code search using ripgrep |

### Data Processing

| Skill | Description |
|-------|-------------|
| `jq-json-processing` | JSON querying and transformation with jq |
| `yq-yaml-processing` | YAML querying and transformation with yq |

### System

| Skill | Description |
|-------|-------------|
| `shell-expert` | Shell scripting and bash patterns |
| `justfile-expert` | Just command runner and recipe development |
| `imagemagick-conversion` | Image conversion and manipulation |

### Code Search

| Skill | Description |
|-------|-------------|
| `vectorcode-init` | VectorCode initialization |
| `vectorcode-search` | VectorCode semantic code search |

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

### Run Project Tasks (Justfile)

```bash
just                        # Show available recipes
just test                   # Run tests
just lint                   # Run linters
just build                  # Build project
just dev                    # Development mode with watch
```

### Universal Dependency Install

```bash
/deps:install               # Auto-detects and uses npm/yarn/pnpm/uv/cargo
/deps:install axios --dev   # Install as dev dependency
```

## Installation

```bash
/plugin install tools-plugin@lgates-claude-plugins
```

## License

MIT
