---
created: 2025-12-16
modified: 2026-04-25
reviewed: 2026-04-25
name: google-chat-formatting
description: Convert text to Google Chat compatible formatting (Markdown to Google Chat syntax). Use when formatting messages for Google Chat, converting Markdown documents for Google Chat, or when the user mentions Google Chat formatting.
user-invocable: false
allowed-tools: Read, Write, Edit, Bash
---

# Google Chat Formatting

Expert knowledge for converting Markdown and plain text to Google Chat's limited formatting syntax. Google Chat supports a subset of formatting that differs from standard Markdown.

## When to Use This Skill

| Use this skill when... | Use ticket-drafting-guidelines instead when... |
|---|---|
| Converting Markdown to Google Chat's single-asterisk bold and bullet syntax | Drafting a GitHub issue, PR description, or technical ticket |
| Formatting status updates, meeting notes, or release notes for posting in Google Chat | Writing a structured What/Why/How bug report or feature request |
| Stripping headers and tables for a chat-channel announcement | Producing prose intended for a GitHub or docs surface (keep standard Markdown) |

## Core Expertise

**Format Conversion**
- Transform Markdown headers to bold text
- Convert list markers to bullet symbols
- Adapt bold/emphasis syntax to Google Chat format
- Preserve code blocks and inline code
- Ensure mobile-friendly spacing and readability

**Google Chat Limitations**
- No native header support (use bold instead)
- Limited text formatting (bold, italic, strikethrough, code)
- Bullet symbols (U+2022) instead of hyphen lists
- No nested formatting (bold inside italic, etc.)
- No tables, images, or advanced Markdown features

## Conversion Rules

### Headers to Bold Text

Google Chat has no header support. Convert all headers to bold text:

```markdown
# Header           → *Header*
## Subheader       → *Subheader*
### Section        → *Section*
```

**Pattern**: Remove all `#` symbols and wrap text in single asterisks.

### Text Formatting

Google Chat uses single asterisks for bold (not double):

```markdown
**bold**          → *bold*
__bold__          → *bold*
*italic*          → _italic_
_italic_          → _italic_
~~strikethrough~~ → ~strikethrough~
```

**Key differences**:
- Bold: Single asterisks `*text*` (not `**text**`)
- Italic: Single underscores `_text_` (not `*text*`)
- Strikethrough: Single tildes `~text~`
- No nested formatting support

### Code Formatting

Preserve code blocks and inline code unchanged:

```markdown
`inline code`     → `inline code` (unchanged)
```code block```  → ```code block``` (unchanged)
```

### Lists

Replace Markdown list markers with bullet symbols:

```markdown
- item            → • item
* item            → • item
+ item            → • item
1. numbered       → 1. numbered (keep numbered lists)
```

**Pattern**: Replace `-`, `*`, `+` at line start with bullet symbol.

### Special Patterns

**Label formatting** (common in structured messages):

```markdown
**Label:**        → *Label:*
**Status:** text  → *Status:* text
```

### Whitespace

Normalize spacing for readability:
- Collapse multiple blank lines to single blank line
- Strip trailing whitespace

## Essential Commands

### Convert Markdown File

```bash
# Read file, convert, write output
cat input.md | sed -E 's/^#{1,6} (.+)$/*\1*/g' | \
  sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g' | \
  sed -E 's/^[*+-] /• /g' > output.txt
```

### Convert Inline Text

```bash
# Quick conversion of text string
echo "## Header\n**bold** text\n- item" | \
  sed -E 's/^#{1,6} (.+)$/*\1*/g' | \
  sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g' | \
  sed -E 's/^[*+-] /• /g'
```

### Process Clipboard (macOS)

```bash
# Convert clipboard content
pbpaste | sed -E 's/^#{1,6} (.+)$/*\1*/g' | \
  sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g' | \
  sed -E 's/^[*+-] /• /g' | pbcopy
```

### Batch Processing

```bash
# Convert all .md files in directory
for file in *.md; do
  sed -E 's/^#{1,6} (.+)$/*\1*/g' "$file" | \
    sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g' | \
    sed -E 's/^[*+-] /• /g' > "${file%.md}.gchat.txt"
done
```

For common conversion patterns (meeting notes, status updates, release notes), best practices, troubleshooting, integration examples, limitations, and advanced patterns, see [REFERENCE.md](REFERENCE.md).

## Quick Reference

### Conversion Patterns

| Markdown | Google Chat | Notes |
|----------|-------------|-------|
| `# Header` | `*Header*` | All header levels |
| `**bold**` | `*bold*` | Single asterisks |
| `__bold__` | `*bold*` | Underscores to asterisks |
| `*italic*` | `_italic_` | Single underscores |
| `- item` | `• item` | Bullet symbol |
| `` `code` `` | `` `code` `` | Unchanged |

### Sed Commands

```bash
# Headers
sed -E 's/^#{1,6} (.+)$/*\1*/g'

# Bold (asterisks)
sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g'

# Bold (underscores)
sed -E 's/__([^_]+)__/\*\1\*/g'

# Lists
sed -E 's/^[*+-] /• /g'

# Collapse blank lines
sed -E '/^$/N;/^\n$/D'

# Strip trailing whitespace
sed -E 's/[ \t]+$//'
```

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Quick convert file | `sed -E 's/^#{1,6} (.+)$/*\1*/g' file.md \| sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g'` |
| Check for unconverted | `grep -E '^\#\|^\*\*' output.txt` |
| Clipboard convert | `pbpaste \| sed -E 's/^#{1,6} (.+)$/*\1*/g' \| pbcopy` |

## Resources

- **Google Chat Formatting**: https://support.google.com/chat/answer/7649118
- **Markdown Guide**: https://www.markdownguide.org/basic-syntax/
- **Sed Reference**: https://www.gnu.org/software/sed/manual/sed.html
- **Unicode Bullet**: U+2022
