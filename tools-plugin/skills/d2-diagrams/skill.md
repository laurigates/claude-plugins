---
model: haiku
name: D2 Diagrams
description: Generate diagrams from declarative text using D2 - modern text-to-diagram language with automatic layouts, themes, and advanced styling.
allowed-tools: Bash, Read, Write, Grep, Glob, TodoWrite
created: 2025-12-26
modified: 2025-12-26
reviewed: 2025-12-26
---

# D2 Diagrams

Expert in generating diagrams from declarative text definitions using D2 - a modern diagram scripting language.

## Core Expertise

- **Declarative syntax**: Describe what to diagram, D2 handles the layout
- **Multiple layout engines**: dagre (default), elk, tala (premium)
- **Rich theming**: 100+ built-in themes with dark mode support
- **Multiple outputs**: SVG, PNG, PDF, GIF (animated)
- **Watch mode**: Auto-regenerate on file changes

## Installation

```bash
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

### Special Shapes

```d2
# SQL table
users: {
  shape: sql_table
  id: int {constraint: primary_key}
  name: varchar
  email: varchar {constraint: unique}
}

# Class
MyClass: {
  shape: class
  +publicField: string
  -privateField: int
  #protectedField: bool
  +publicMethod(): void
  -privateMethod(): string
}

# Code block
code: |go
  func main() {
    fmt.Println("Hello")
  }
|
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

### Layers and Scenarios

```d2
# Base diagram
a -> b -> c

# Layers (for multi-page output)
layers: {
  layer1: {
    a: Different in layer 1
  }
  layer2: {
    b: Different in layer 2
  }
}
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

### Database ERD

```d2
users: {
  shape: sql_table
  id: int {constraint: primary_key}
  name: varchar(100)
  email: varchar(255) {constraint: unique}
  created_at: timestamp
}

orders: {
  shape: sql_table
  id: int {constraint: primary_key}
  user_id: int {constraint: foreign_key}
  total: decimal
  status: varchar(20)
}

items: {
  shape: sql_table
  id: int {constraint: primary_key}
  order_id: int {constraint: foreign_key}
  product_id: int
  quantity: int
}

users.id <-> orders.user_id
orders.id <-> items.order_id
```

### Kubernetes Deployment

```d2
cluster: Kubernetes Cluster {
  ns: Namespace {
    deploy: Deployment {
      pod1: Pod
      pod2: Pod
      pod3: Pod
    }
    svc: Service {
      shape: hexagon
    }
    svc -> deploy
  }

  ingress: Ingress {
    shape: cloud
  }
  ingress -> ns.svc
}
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick SVG | `d2 diagram.d2 diagram.svg` |
| Live preview | `d2 --watch --browser diagram.d2` |
| Dark theme | `d2 --dark-theme 200 diagram.d2 output.svg` |
| Sketch style | `d2 --sketch diagram.d2 output.svg` |
| ELK layout | `d2 -l elk diagram.d2 output.svg` |
| List themes | `d2 themes` |
| PNG export | `d2 diagram.d2 output.png` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `-w, --watch` | Watch and regenerate on changes |
| `--browser` | Open browser preview (with --watch) |
| `-t, --theme` | Theme ID (run `d2 themes` for list) |
| `--dark-theme` | Dark mode theme ID |
| `-l, --layout` | Layout engine: dagre, elk, tala |
| `--sketch` | Hand-drawn style |
| `--pad` | Diagram padding in pixels |
| `--center` | Center the diagram |
| `--animate-interval` | Animation frame interval (ms) |
| `-h, --help` | Show help |

## Theme Categories

| Range | Category |
|-------|----------|
| 0-99 | Light themes |
| 100-199 | Special themes |
| 200-299 | Dark themes |

Popular themes:
- `0` - Default (Neutral)
- `1` - Neutral Grey
- `3` - Flagship Terrastruct
- `4` - Cool Classics
- `8` - Colorblind Clear
- `100` - Earth Tones
- `101` - Everglade Green
- `200` - Dark Mauve

## D2 vs Mermaid

| Feature | D2 | Mermaid |
|---------|----|---------|
| Layout engines | Multiple (dagre, elk, tala) | Single |
| Theming | 100+ themes | 4 themes |
| Watch mode | Built-in | Requires external tools |
| SQL tables | Native | Limited |
| Sketch mode | Yes | No |
| Icons | Any URL | Limited |
| Containers | Deep nesting | Subgraphs only |
| Markdown embedding | Growing | Excellent |
| GitHub rendering | No | Native |

**Choose D2 when**: Rich styling, complex layouts, SQL schemas, architecture diagrams
**Choose Mermaid when**: Markdown/GitHub integration, simpler syntax, wide tool support
