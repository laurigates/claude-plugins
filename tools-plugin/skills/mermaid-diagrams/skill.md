---
model: haiku
name: Mermaid Diagrams
description: Generate diagrams from text using Mermaid CLI (mmdc) - flowcharts, sequence diagrams, ERDs, class diagrams, state machines, and more.
allowed-tools: Bash, Read, Write, Grep, Glob, TodoWrite
created: 2025-12-26
modified: 2025-12-26
reviewed: 2025-12-26
---

# Mermaid Diagrams

Expert in generating diagrams from Markdown-inspired text definitions using Mermaid CLI.

## Core Expertise

- **Text-to-diagram**: Convert simple text syntax to professional diagrams
- **Wide diagram support**: Flowcharts, sequence, class, state, ERD, Gantt, pie, and more
- **Multiple outputs**: SVG (default), PNG, PDF
- **Markdown integration**: Embed in documentation, GitHub README, wikis

## Installation

```bash
# npm (global)
npm install -g @mermaid-js/mermaid-cli

# npx (no install)
npx @mermaid-js/mermaid-cli -i input.mmd -o output.svg
```

## Essential Commands

### Basic Rendering

```bash
# Convert to SVG (default)
mmdc -i diagram.mmd -o diagram.svg

# Convert to PNG
mmdc -i diagram.mmd -o diagram.png

# Convert to PDF
mmdc -i diagram.mmd -o diagram.pdf

# Pipe from stdin
echo 'graph TD; A-->B' | mmdc --input - -o diagram.svg
```

### Theming and Styling

```bash
# Use built-in theme
mmdc -i diagram.mmd -o diagram.svg -t dark
mmdc -i diagram.mmd -o diagram.svg -t forest
mmdc -i diagram.mmd -o diagram.svg -t neutral

# Custom CSS
mmdc -i diagram.mmd -o diagram.svg -C custom.css

# Background color
mmdc -i diagram.mmd -o diagram.png -b transparent
mmdc -i diagram.mmd -o diagram.png -b '#ffffff'
```

### Image Settings

```bash
# Set dimensions (PNG)
mmdc -i diagram.mmd -o diagram.png -w 1920 -H 1080

# Scale factor
mmdc -i diagram.mmd -o diagram.png -s 2
```

## Diagram Types

### Flowchart

```mermaid
graph TD
    A[Start] --> B{Decision}
    B -->|Yes| C[Action 1]
    B -->|No| D[Action 2]
    C --> E[End]
    D --> E
```

Direction options: `TD` (top-down), `TB`, `BT`, `LR` (left-right), `RL`

### Sequence Diagram

```mermaid
sequenceDiagram
    participant A as Alice
    participant B as Bob
    A->>B: Hello
    B-->>A: Hi there
    A->>+B: Request
    B-->>-A: Response
```

Arrow types:
| Arrow | Description |
|-------|-------------|
| `->` | Solid line |
| `-->` | Dotted line |
| `->>` | Solid with arrowhead |
| `-->>` | Dotted with arrowhead |
| `-x` | Solid with cross |
| `-)` | Async (open arrow) |

### Class Diagram

```mermaid
classDiagram
    class Animal {
        +String name
        +int age
        +makeSound()
    }
    class Dog {
        +fetch()
    }
    Animal <|-- Dog
```

### Entity Relationship (ERD)

```mermaid
erDiagram
    CUSTOMER ||--o{ ORDER : places
    ORDER ||--|{ LINE_ITEM : contains
    PRODUCT ||--o{ LINE_ITEM : "ordered in"
```

### State Diagram

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Processing : submit
    Processing --> Complete : success
    Processing --> Error : failure
    Complete --> [*]
    Error --> Idle : retry
```

### Gantt Chart

```mermaid
gantt
    title Project Timeline
    dateFormat YYYY-MM-DD
    section Phase 1
    Task A :a1, 2024-01-01, 30d
    Task B :after a1, 20d
```

### Pie Chart

```mermaid
pie title Distribution
    "Category A" : 40
    "Category B" : 30
    "Category C" : 30
```

### Git Graph

```mermaid
gitGraph
    commit
    branch develop
    checkout develop
    commit
    commit
    checkout main
    merge develop
    commit
```

## Shape Syntax

| Shape | Syntax |
|-------|--------|
| Rectangle | `[Text]` |
| Rounded | `(Text)` |
| Stadium | `([Text])` |
| Diamond | `{Text}` |
| Hexagon | `{{Text}}` |
| Circle | `((Text))` |
| Asymmetric | `>Text]` |
| Database | `[(Text)]` |
| Subroutine | `[[Text]]` |

## Styling

```mermaid
graph TD
    A[Styled]:::custom --> B
    classDef custom fill:#f96,stroke:#333,stroke-width:2px
    style A fill:#bbf,stroke:#f66
```

## Docker Usage

```bash
# Using Docker
docker run --rm -v "$(pwd)":/data minlag/mermaid-cli -i /data/diagram.mmd -o /data/output.svg

# With UID for correct permissions
docker run -u $UID --rm -v "$(pwd)":/data minlag/mermaid-cli -i /data/diagram.mmd
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick SVG | `mmdc -i diagram.mmd -o diagram.svg` |
| PNG with transparency | `mmdc -i diagram.mmd -o diagram.png -b transparent` |
| High-res PNG | `mmdc -i diagram.mmd -o diagram.png -s 2` |
| Dark theme | `mmdc -i diagram.mmd -o diagram.svg -t dark` |
| Batch process | `for f in *.mmd; do mmdc -i "$f" -o "${f%.mmd}.svg"; done` |
| Stdin pipe | `echo 'graph TD; A-->B' \| mmdc --input - -o out.svg` |

## Quick Reference

| Flag | Description |
|------|-------------|
| `-i, --input` | Input file (use `-` for stdin) |
| `-o, --output` | Output file (determines format) |
| `-t, --theme` | Theme: default, dark, forest, neutral |
| `-b, --backgroundColor` | Background color |
| `-C, --cssFile` | Custom CSS file |
| `-c, --configFile` | Mermaid config JSON |
| `-w, --width` | Output width (PNG) |
| `-H, --height` | Output height (PNG) |
| `-s, --scale` | Scale factor |
| `-p, --puppeteerConfigFile` | Puppeteer config |
| `-h, --help` | Show help |

## Common Patterns

### Architecture Diagram

```mermaid
graph TB
    subgraph Frontend
        A[React App]
    end
    subgraph Backend
        B[API Gateway]
        C[Service 1]
        D[Service 2]
    end
    subgraph Data
        E[(PostgreSQL)]
        F[(Redis)]
    end
    A --> B
    B --> C
    B --> D
    C --> E
    D --> F
```

### API Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant G as Gateway
    participant S as Service
    participant D as Database

    C->>G: HTTP Request
    G->>S: Forward
    S->>D: Query
    D-->>S: Result
    S-->>G: Response
    G-->>C: HTTP Response
```

## Troubleshooting

### Linux Sandbox Issues

Create `puppeteer-config.json`:
```json
{
  "args": ["--no-sandbox", "--disable-setuid-sandbox"]
}
```

```bash
mmdc -p puppeteer-config.json -i diagram.mmd -o diagram.svg
```

### Large Diagrams

```bash
# Increase timeout
mmdc -i large.mmd -o large.svg --timeout 60000
```
