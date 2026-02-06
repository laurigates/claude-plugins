---
model: haiku
name: D2 Diagrams
description: |
  Generate diagrams from declarative text using D2 - modern text-to-diagram language with
  automatic layouts, themes, and advanced styling. Use when creating architecture diagrams,
  flowcharts, decision trees, workflow diagrams, sequence flows, or ERDs from text definitions.
allowed-tools: Bash(d2 *), Read, Write, Grep, Glob, TodoWrite
created: 2025-12-26
modified: 2026-02-06
reviewed: 2026-02-06
---

# D2 Diagrams

Expert in generating diagrams from declarative text definitions using D2 - a modern diagram scripting language.

## When to Use This Skill

| Use this skill when... | Use Mermaid instead when... |
|------------------------|-----------------------------|
| Rich styling with classes and themes | Embedding diagrams in GitHub Markdown |
| Complex nested container layouts | Simple flowcharts with minimal styling |
| Architecture diagrams with icons | Diagrams that render natively in docs platforms |
| Decision trees with colored edges | Sequence diagrams (Mermaid has richer syntax) |
| SQL table / ERD diagrams | Wide tool support is a priority |

For a detailed feature comparison, see [REFERENCE.md](REFERENCE.md).

## Core Expertise

- **Declarative syntax**: Describe what to diagram, D2 handles the layout
- **Multiple layout engines**: dagre (default), elk, tala (premium)
- **Rich theming**: 100+ built-in themes with dark mode support
- **Multiple outputs**: SVG, PNG, PDF, GIF (animated)
- **Watch mode**: Auto-regenerate on file changes

## Installation

```bash
# mise (preferred)
mise install d2 && mise use -g d2

# macOS
brew install d2

# Linux/Windows (via curl)
curl -fsSL https://d2lang.com/install.sh | sh -s --

# Go install
go install oss.terrastruct.com/d2@latest
```

## Essential Commands

### Basic Rendering

```bash
# Convert to SVG (default)
d2 diagram.d2 diagram.svg

# Convert to PNG
d2 diagram.d2 diagram.png

# Convert to PDF
d2 diagram.d2 diagram.pdf

# Output to stdout
d2 diagram.d2 -
```

> **PNG prerequisite**: The first PNG render downloads a bundled Chromium (~140 MB). Expect ~1 min delay on the initial run; subsequent renders are fast.

### Watch Mode

```bash
# Watch and auto-regenerate
d2 --watch diagram.d2 diagram.svg

# Watch with browser preview
d2 --watch --browser diagram.d2
```

### Theming

```bash
# List available themes
d2 themes

# Use specific theme (by ID)
d2 -t 101 diagram.d2 output.svg

# Dark theme (respects system preference)
d2 --dark-theme 200 diagram.d2 output.svg

# Combine light and dark themes
d2 -t 1 --dark-theme 200 diagram.d2 output.svg
```

### Layout Engines

```bash
# List available layouts
d2 layout

# Use specific layout
d2 -l elk diagram.d2 output.svg
d2 -l dagre diagram.d2 output.svg
```

### Sketch Mode

```bash
# Hand-drawn style
d2 --sketch diagram.d2 output.svg
```

## D2 Syntax

### Basic Shapes and Connections

```d2
# Shapes (auto-created)
server
database
client

# Connections
client -> server: request
server -> database: query
database -> server: result
server -> client: response

# Bidirectional
a <-> b

# Undirected
a -- b
```

### Shape Types

```d2
# Explicit shapes
rect: {shape: rectangle}
oval: {shape: oval}
cyl: {shape: cylinder}
queue: {shape: queue}
pkg: {shape: package}
step: {shape: step}
page: {shape: page}
doc: {shape: document}
cloud: {shape: cloud}
diamond: {shape: diamond}
hex: {shape: hexagon}
para: {shape: parallelogram}
circle: {shape: circle}
```

### Containers (Nesting)

```d2
server: {
  app: Application
  db: Database
  app -> db
}

client -> server.app
```

### Labels and Icons

```d2
# Labels
a: "My Label"
a -> b: "connection label"

# Icons (from icon packs)
server: {
  icon: https://icons.terrastruct.com/essentials/004-server.svg
}

# Tooltip
node: {
  tooltip: Additional information shown on hover
}

# Links
github: {
  link: https://github.com
}
```

### Styling

```d2
# Inline styles
styled: {
  style: {
    fill: "#ff6b6b"
    stroke: "#c92a2a"
    stroke-width: 2
    border-radius: 8
    shadow: true
    opacity: 0.9
    font-color: white
  }
}

# Connection styles
a -> b: {
  style: {
    stroke: red
    stroke-width: 3
    stroke-dash: 5
    animated: true
  }
}
```

### Glob Patterns

```d2
# Style all shapes
*: {
  style.fill: lightblue
}

# Style all connections
* -> *: {
  style.stroke: gray
}
```

### Classes (Reusable Styles)

Define named style sets and apply them to multiple nodes/edges.

```d2
classes: {
  error: {
    style: {
      fill: "#ffebee"
      stroke: "#c62828"
      font-color: "#c62828"
      border-radius: 8
    }
  }
  success: {
    style: {
      fill: "#e8f5e9"
      stroke: "#2e7d32"
      font-color: "#2e7d32"
      border-radius: 8
    }
  }
  decision: {
    shape: diamond
    style: {
      fill: "#fff3e0"
      stroke: "#e65100"
      font-color: "#e65100"
    }
  }
}

# Apply a class
start: Start {class: success}
check: Valid? {class: decision}
fail: Error {class: error}

start -> check
check -> fail: No
```

### Variables

```d2
vars: {
  primary-color: "#4a90d9"
}

box: {
  style.fill: ${primary-color}
}
```

### Configuration in File

```d2
vars: {
  d2-config: {
    layout: elk
    theme: 4
    dark-theme: 200
    pad: 20
    sketch: true
  }
}

# Diagram content
a -> b -> c
```

## Common Diagram Patterns

### System Architecture

```d2
direction: right

client: Client {
  icon: https://icons.terrastruct.com/essentials/user.svg
}

lb: Load Balancer {
  icon: https://icons.terrastruct.com/aws/Networking%20&%20Content%20Delivery/Elastic%20Load%20Balancing.svg
}

services: Services {
  api: API Server
  auth: Auth Service
  api -> auth: validate
}

data: Data Layer {
  db: PostgreSQL {
    shape: cylinder
  }
  cache: Redis {
    shape: cylinder
  }
}

client -> lb -> services.api
services.api -> data.db
services.api -> data.cache
```

### Sequence-like Flow

```d2
direction: right

user: User
frontend: Frontend
api: API
db: Database

user -> frontend: 1. Click button
frontend -> api: 2. POST /action
api -> db: 3. INSERT
db -> api: 4. OK
api -> frontend: 5. 200 OK
frontend -> user: 6. Show success
```

### Decision Tree / Flowchart

Uses classes for consistent styling, diamond shapes for decisions, and colored edges for Yes/No paths.

```d2
classes: {
  decision: {
    shape: diamond
    style: {
      fill: "#fff3e0"
      stroke: "#e65100"
      font-color: "#e65100"
    }
  }
  action: {
    shape: rectangle
    style: {
      fill: "#e3f2fd"
      stroke: "#1565c0"
      font-color: "#1565c0"
      border-radius: 8
    }
  }
  terminal: {
    shape: oval
    style: {
      fill: "#e8f5e9"
      stroke: "#2e7d32"
      font-color: "#2e7d32"
    }
  }
  warn: {
    shape: hexagon
    style: {
      fill: "#ffebee"
      stroke: "#c62828"
      font-color: "#c62828"
    }
  }
}

start: Start {class: terminal}
staged: Staged changes? {class: decision}
lint: Run linter {class: action}
pass: Lint pass? {class: decision}
commit: Create commit {class: action}
done: Done {class: terminal}
fix: Fix issues {class: warn}

start -> staged
staged -> lint: Yes {style.stroke: green}
staged -> done: No {style.stroke: red}
lint -> pass
pass -> commit: Yes {style.stroke: green}
pass -> fix: No {style.stroke: red}
fix -> lint
commit -> done
```

For additional patterns (Database ERD, Kubernetes Deployment), special shapes (sql_table, class, code blocks), layers, theme categories, and a full D2 vs Mermaid comparison, see [REFERENCE.md](REFERENCE.md).

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick SVG | `d2 diagram.d2 diagram.svg` |
| Live preview | `d2 --watch --browser diagram.d2` |
| Dark theme | `d2 --dark-theme 200 diagram.d2 output.svg` |
| Sketch style | `d2 --sketch diagram.d2 output.svg` |
| ELK layout | `d2 -l elk diagram.d2 output.svg` |
| List themes | `d2 themes` |
| PNG export | `d2 --scale 2 diagram.d2 output.png` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `-w, --watch` | Watch and regenerate on changes |
| `--browser` | Open browser preview (with --watch) |
| `-t, --theme` | Theme ID (run `d2 themes` for list) |
| `--dark-theme` | Dark mode theme ID |
| `-l, --layout` | Layout engine: dagre, elk, tala |
| `--sketch` | Hand-drawn style |
| `--scale` | Output scale factor (e.g. `2` for 2x resolution) |
| `--pad` | Diagram padding in pixels |
| `--center` | Center the diagram |
| `--animate-interval` | Animation frame interval (ms) |
| `-h, --help` | Show help |
