# D2 Diagrams - Reference

Extended reference material for the D2 diagrams skill. See [skill.md](skill.md) for core syntax and common patterns.

## Special Shapes

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

## Layers and Scenarios

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

## Additional Patterns

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
