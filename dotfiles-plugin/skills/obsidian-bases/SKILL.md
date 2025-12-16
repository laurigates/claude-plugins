---
name: obsidian-bases
description: Obsidian Bases database feature for YAML-based interactive note views. Use when creating .base files, writing filter queries, building formulas, configuring table/card views, or working with Obsidian properties and frontmatter databases.
allowed-tools: Read, Write, Edit, Grep, Glob
---

# Obsidian Bases

Expert knowledge for creating and managing Obsidian Bases - the interactive database feature introduced in Obsidian v1.9.10 that transforms notes into filterable, sortable views using YAML frontmatter properties.

## Core Concepts

**What is Bases?**
- Native core plugin (no community plugins required)
- Creates interactive database views from any set of notes
- Uses `.base` file extension (plain-text YAML format)
- **Only reads YAML frontmatter** - does not parse note content
- Faster performance than Dataview with inline editing support

**Key Distinction from Dataview:**
- Bases: User-friendly, visual, inline editable, YAML frontmatter only
- Dataview: More powerful queries, inline properties, content parsing

## File Structure

```yaml
# example.base
filters:
  # Global filters (apply to all views)
  and:
    - 'status != "done"'
    - taggedWith(file.file, "project")

formulas:
  # Computed properties
  days_left: '(dueDate - today()).days()'
  status_icon: 'if(done, "✅", "⬜")'

views:
  - type: table
    name: "Active Tasks"
    filters:
      'dueDate > now()'      # View-specific filter
    properties:
      - name: title
        displayName: "Task"
      - name: status
      - name: dueDate
    sort:
      - property: dueDate
        direction: asc

  - type: card
    name: "Visual View"
    properties:
      - name: cover
      - name: title
```

## Property Access Patterns

### Note Properties (Frontmatter)

```yaml
# Shorthand access
price
status
tags

# Explicit prefix
note.price
note.status

# Bracket notation (for spaces)
note["property name"]
```

### File Properties (Implicit)

```yaml
file.path      # Full file path
file.name      # File name only
file.folder    # Parent folder
file.size      # File size in bytes
file.ctime     # Creation time
file.mtime     # Modification time
file.ext       # Extension
file.file      # File object (for filter functions)
file.links     # Outgoing links
file.inlinks   # Incoming backlinks
```

### Formula Properties

```yaml
formula.my_formula
formula["formula name"]
```

## Filter Syntax

### Basic Operators

```yaml
# Comparison (must have spaces around operators)
price > 10
status == "done"
age >= 18

# Logical operators
and:
  - condition1
  - condition2

or:
  - condition1
  - condition2

not:
  - condition
```

### Filter Functions

```yaml
# Tag filtering
taggedWith(file.file, "project")
taggedWith(file.file, "project/web")     # Nested tags

# Link filtering
linksTo(file.file, "Note Name")
file.hasLink(this.file)                  # Backlinks to current note

# Folder filtering
inFolder(file.file, "Projects")
inFolder(file.file, "Projects/Web")      # Nested folders

# Date filtering
file.mtime > now() - "1 week"            # Modified recently
dueDate < today()                        # Overdue
createdDate >= "2025-01-01"              # This year

# Regex matching
/\d{4}-\d{2}-\d{2}/.matches(file.name)   # Daily note format
```

### The `this` Variable

Context-aware reference to the active note:

```yaml
# In sidebar: references active note in main pane
file.hasLink(this.file)                  # Find backlinks

# In embedded base: references containing note
file.folder == this.file.folder          # Same folder

# Exclude current note
file.path != this.file.path
```

## Formula Syntax

### Basic Formulas

```yaml
formulas:
  # Arithmetic
  total: "price * quantity"
  discounted: "total * 0.9"

  # String manipulation
  full_name: 'firstName + " " + lastName'

  # Conditional logic
  status_emoji: 'if(status == "done", "✅", if(status == "in-progress", "🔄", "⬜"))'

  # Date calculations
  days_until: '(dueDate - today()).days()'
  overdue: 'dueDate < today()'

  # Link analysis
  backlink_count: 'file.inlinks.length'
  has_backlinks: 'file.inlinks.length > 0'
```

### Built-in Functions

**Global:**
- `today()` - Current date
- `now()` - Current date and time
- `link(target, displayText?)` - Create link
- `image(url)` - Create image object
- `list(value)` - Ensure value is a list
- `if(condition, trueResult, falseResult?)` - Conditional

**String methods:**
- `.toUpperCase()`, `.toLowerCase()`
- `.trim()`, `.split(separator)`
- `.startsWith(prefix)`, `.endsWith(suffix)`
- `.replace(search, replacement)`

**Number methods:**
- `.toFixed(decimals)` - Format decimal places
- `.round()`, `.floor()`, `.ceil()`

**Date methods:**
- `.date()` - Convert to date
- `.startOf(unit)`, `.endOf(unit)`
- `.format(pattern)`
- `.days()`, `.months()`, `.years()` - Duration extraction

**List methods:**
- `.length` - Count elements
- `[index]` - Access element (0-based)
- `.filter(condition)` - Filter elements
- `.map(transformation)` - Transform elements
- `.join(separator)` - Concatenate to string

### Duration Units

```yaml
now() + "1 week"
now() - "30 days"
file.mtime > now() - "1 month"

# Available units
y, year, years
M, month, months
w, week, weeks
d, day, days
h, hour, hours
m, minute, minutes
s, second, seconds
```

## View Types

### Table View

```yaml
views:
  - type: table
    name: "Tasks"
    properties:
      - name: title
        displayName: "Task Name"    # Column header
        width: 200                   # Optional width
      - name: status
      - name: dueDate
    sort:
      - property: dueDate
        direction: asc              # or desc
```

### Card View

```yaml
views:
  - type: card
    name: "Projects"
    properties:
      - name: cover              # Cover image
      - name: title
      - name: status
```

## Common Patterns

### Task Management

```yaml
filters:
  taggedWith(file.file, "task")

formulas:
  overdue: 'dueDate < today()'
  priority_icon: 'if(priority == "high", "🔴", if(priority == "medium", "🟡", "🟢"))'

views:
  - type: table
    name: "Active"
    filters:
      'status != "done"'
    sort:
      - property: dueDate
        direction: asc
```

### Enhanced Backlinks

```yaml
# Drag to sidebar for context-aware backlinks
filters:
  file.hasLink(this.file)

views:
  - type: table
    name: "Backlinks"
    properties:
      - name: file.name
        displayName: "Note"
      - name: file.mtime
        displayName: "Modified"
```

### Book/Media Library

```yaml
filters:
  taggedWith(file.file, "book")

formulas:
  year_read: 'dateFinished.date().year()'

views:
  - type: card
    name: "Library"
    properties:
      - name: cover
      - name: title
      - name: author

  - type: table
    name: "Reading List"
    filters:
      'status == "to-read"'
```

### Weekly Review

```yaml
filters:
  file.mtime > now() - "1 week"

formulas:
  days_ago: '(today() - file.mtime.date()).days()'

views:
  - type: table
    name: "Recent Activity"
    sort:
      - property: file.mtime
        direction: desc
```

## Embedding Bases

```markdown
![[MyBase.base]]                # Embed entire base
![[MyBase.base#ViewName]]       # Embed specific view
```

## Best Practices

**Filter Organization:**
- Use global filters for the broadest scope (lowest common denominator)
- Refine with view-level filters for specific subsets
- Global + view filters combine with AND

**Formula Reusability:**
- Create formula properties for repeated logic
- Reference as `formula.name` in views
- No circular references allowed

**Robust List Handling:**
```yaml
# Always wrap in list() for mixed single/array values
list(tags).length
list(tags).filter(value.startsWith("project"))
```

**Date Validation:**
```yaml
valid_date: 'if(dueDate, dueDate, "No date")'
```

## Common Gotchas

**1. Arithmetic operator spacing:**
```yaml
# ✅ Correct
price * 2

# ❌ Wrong (parser error)
price*2
```

**2. Quote nesting in YAML:**
```yaml
# ✅ Correct - single outer, double inner
formulas:
  message: 'Hello "world"'

# ❌ Wrong
formulas:
  message: "Hello "world""
```

**3. Link properties in frontmatter:**
```yaml
# ✅ Correct - must quote
related: "[[Other Note]]"

# ❌ Wrong
related: [[Other Note]]
```

**4. File extension required:**
```markdown
<!-- ✅ Correct -->
![[MyBase.base]]

<!-- ❌ Wrong (looks for .md) -->
![[MyBase]]
```

**5. Global vs view filter scope:**
- Cannot override global filter at view level
- Make global permissive, refine in views

## Current Limitations

- **View types:** Only table and card (no board, calendar, gallery yet)
- **Images:** Display as text, not rendered in cards
- **Inline properties:** Only YAML frontmatter (no Dataview inline fields)
- **Content parsing:** Cannot query note body text
- **Note creation:** Cannot create new notes from base
- **Grouping:** No native group-by (use separate views instead)
- **Aggregations:** No built-in sum/average/count

## Property Types

| Type | Example |
|------|---------|
| Text | `"Project Alpha"` |
| List | `["tag1", "tag2"]` |
| Number | `42`, `3.14` |
| Checkbox | `true`, `false` |
| Date | `2025-11-26` |
| Date & Time | `2025-11-26T14:30:00` |

**Note:** Property types are vault-wide. If `priority` is Number in one note, it must be Number everywhere.

## Resources

- **Official Docs:** https://help.obsidian.md/bases
- **Syntax Reference:** https://help.obsidian.md/bases/syntax
- **Functions:** https://help.obsidian.md/bases/functions
- **Roadmap:** https://help.obsidian.md/bases/roadmap
