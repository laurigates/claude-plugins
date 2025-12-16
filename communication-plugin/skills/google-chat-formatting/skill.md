---
name: google-chat-formatting
description: Convert text to Google Chat compatible formatting (Markdown to Google Chat syntax). Use when formatting messages for Google Chat, converting Markdown documents for Google Chat, or when the user mentions Google Chat formatting.
allowed-tools: Read, Write, Edit, Bash
---

# Google Chat Formatting

Expert knowledge for converting Markdown and plain text to Google Chat's limited formatting syntax. Google Chat supports a subset of formatting that differs from standard Markdown.

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
- Bullet symbols (•) instead of hyphen lists
- No nested formatting (bold inside italic, etc.)
- No tables, images, or advanced Markdown features

## Conversion Rules

### Headers → Bold Text

Google Chat has no header support. Convert all headers to bold text:

```markdown
# Header           → *Header*
## Subheader       → *Subheader*
### Section        → *Section*
#### Subsection    → *Subsection*
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

**Behavior**: Backticks work identically in Google Chat.

### Lists

Replace Markdown list markers with bullet symbols:

```markdown
- item            → • item
* item            → • item
+ item            → • item
1. numbered       → 1. numbered (keep numbered lists)
```

**Pattern**: Replace `-`, `*`, `+` at line start with `•` (bullet symbol U+2022).

### Special Patterns

**Label formatting** (common in structured messages):

```markdown
**Label:**        → *Label:*
**Status:** text  → *Status:* text
```

**Pattern**: Bold labels followed by colons become single-asterisk bold.

### Whitespace

Normalize spacing for readability:

```markdown
Multiple



blank lines      → Single blank line between sections

Trailing spaces  → Remove all trailing whitespace
```

**Pattern**: Collapse multiple blank lines to single blank line, strip trailing spaces.

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

## Common Patterns

### Meeting Notes

**Input (Markdown)**:
```markdown
# Meeting Notes - 2024-01-15

## Attendees
- Alice Johnson
- Bob Smith

## Decisions
**Priority:** High
**Timeline:** Q1 2024

### Action Items
1. Review proposal
2. Update docs
```

**Output (Google Chat)**:
```
*Meeting Notes - 2024-01-15*

*Attendees*
• Alice Johnson
• Bob Smith

*Decisions*
*Priority:* High
*Timeline:* Q1 2024

*Action Items*
1. Review proposal
2. Update docs
```

### Status Updates

**Input (Markdown)**:
```markdown
## Project Status

**Status:** In Progress
**Blockers:** None
**Next Steps:**
- Code review
- Deploy to staging
```

**Output (Google Chat)**:
```
*Project Status*

*Status:* In Progress
*Blockers:* None
*Next Steps:*
• Code review
• Deploy to staging
```

### Release Notes

**Input (Markdown)**:
```markdown
# Release v1.2.0

## New Features
- OAuth2 authentication
- Dark mode support

## Bug Fixes
- Fixed timeout issue
- **Critical:** Security patch applied
```

**Output (Google Chat)**:
```
*Release v1.2.0*

*New Features*
• OAuth2 authentication
• Dark mode support

*Bug Fixes*
• Fixed timeout issue
• *Critical:* Security patch applied
```

## Best Practices

### Structure and Readability

**Use blank lines between sections**:
```
*Header*

Content here

*Next Header*
```

**Format labels consistently**:
```
*Label:* description
*Status:* value
*Priority:* high
```

**Keep lines short** for mobile viewing:
- Aim for 60-80 characters per line
- Break long paragraphs into shorter chunks
- Use lists for multiple items

### Preserving Intent

**Maintain hierarchy with indentation**:
```
*Main Topic*
• First-level item
  • Sub-item (2 spaces indent)
• Another first-level item
```

**Preserve code context**:
```
To run the server: `npm start`

Configuration:
```json
{
  "port": 3000
}
```
```

**Keep numbered lists intact**:
- Use numbered lists for sequential steps
- Use bullet lists for unordered items
- Don't convert numbering to bullets

### Avoiding Common Mistakes

**Don't nest formatting**:
```
❌ *bold _and italic_*    (not supported)
✅ *bold* and _italic_     (separate)
```

**Don't use double formatting**:
```
❌ **bold**               (Markdown syntax)
✅ *bold*                 (Google Chat syntax)
```

**Don't leave extra whitespace**:
```
❌ *Header*

   Content

❌ Trailing spaces here

✅ *Header*

Content (no trailing spaces)
```

## Troubleshooting

### Conversion Issues

**Headers not converting**:
```bash
# Check for tabs instead of spaces after #
sed -E 's/^#{1,6}[ \t]+(.+)$/*\1*/g'
```

**Bold not converting**:
```bash
# Handle underscores and asterisks
sed -E 's/(\*\*|__)([^*_]+)(\*\*|__)/\*\2\*/g'
```

**Lists not converting**:
```bash
# Handle indented lists
sed -E 's/^[ \t]*[*+-] /• /g'
```

### Validation

**Check for unconverted Markdown**:
```bash
# Look for remaining double asterisks
grep '\*\*' output.txt

# Look for unconverted headers
grep '^#' output.txt
```

**Test in Google Chat**:
1. Copy converted text
2. Paste into Google Chat
3. Verify formatting renders correctly
4. Check on mobile device

## Integration Examples

### With Clipboard (macOS)

```bash
# Create shell function in ~/.config/fish/functions/gchat.fish
function gchat
    pbpaste | \
      sed -E 's/^#{1,6} (.+)$/*\1*/g' | \
      sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g' | \
      sed -E 's/^[*+-] /• /g' | \
      pbcopy
    echo "✓ Converted to Google Chat format (in clipboard)"
end
```

### With Files

```bash
# Convert README.md for Google Chat
function readme-to-gchat
    set input $argv[1]
    set output (basename $input .md).gchat.txt

    cat $input | \
      sed -E 's/^#{1,6} (.+)$/*\1*/g' | \
      sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g' | \
      sed -E 's/^[*+-] /• /g' > $output

    echo "✓ Created: $output"
end
```

### With Git Commit Messages

```bash
# Format commit message for Google Chat
function commit-to-gchat
    git log -1 --pretty=%B | \
      sed -E 's/^#{1,6} (.+)$/*\1*/g' | \
      sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g' | \
      sed -E 's/^[*+-] /• /g' | \
      pbcopy
    echo "✓ Commit message formatted for Google Chat"
end
```

## Limitations

### Unsupported Markdown Features

**Tables** - No equivalent in Google Chat:
```
Use plain text lists or key-value pairs instead
```

**Images** - No inline image support:
```
Share image links or upload separately
```

**Links** - Limited link formatting:
```markdown
[text](url) → text: url (expand links)
```

**Block quotes** - No block quote support:
```
> Quote → "Quote" (use quotation marks)
```

**Horizontal rules** - No HR support:
```
--- → ────────── (use Unicode box drawing)
```

### Google Chat Constraints

**Character limit**: 4096 characters per message
- Split long messages into multiple parts
- Use threaded replies for continuations

**Formatting restrictions**:
- No nested bold/italic
- No custom fonts or colors (except via bots)
- No superscript/subscript

**Mobile rendering**:
- Test on mobile devices
- Use simple, readable formatting
- Keep lines short

## Advanced Patterns

### Sed-Based Transformation Chain

```bash
# Complete conversion pipeline
cat input.md | \
  # Convert headers
  sed -E 's/^#{1,6} (.+)$/*\1*/g' | \
  # Convert double asterisk bold to single
  sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g' | \
  # Convert underscore bold to asterisk
  sed -E 's/__([^_]+)__/\*\1\*/g' | \
  # Convert list markers to bullets
  sed -E 's/^[*+-] /• /g' | \
  # Normalize multiple blank lines
  sed -E '/^$/N;/^\n$/D' | \
  # Remove trailing whitespace
  sed -E 's/[ \t]+$//' > output.txt
```

### Preserving Code Blocks

```bash
# Skip code blocks during conversion
awk '
  /^```/ { in_code = !in_code }
  in_code { print; next }
  /^#{1,6} / { gsub(/^#{1,6} /, "*"); gsub(/$/, "*") }
  /\*\*[^*]+\*\*/ { gsub(/\*\*/, "*") }
  /^[*+-] / { gsub(/^[*+-] /, "• ") }
  { print }
' input.md > output.txt
```

### Handling Edge Cases

```bash
# Complex conversion with edge case handling
function convert-to-gchat
    set input $argv[1]

    cat $input | \
      # Protect code blocks
      awk '/^```/,/^```/ { print; next } { print }' | \
      # Convert headers (all levels)
      sed -E 's/^#{1,6}[ \t]+(.+)$/*\1*/g' | \
      # Convert bold (asterisk and underscore)
      sed -E 's/(\*\*|__)([^*_]+)(\*\*|__)/\*\2\*/g' | \
      # Convert lists (handle indentation)
      sed -E 's/^([ \t]*)[*+-] /\1• /g' | \
      # Clean whitespace
      sed -E 's/[ \t]+$//' | \
      sed -E '/^$/N;/^\n$/D'
end
```

## Quick Reference

### Conversion Patterns

| Markdown | Google Chat | Notes |
|----------|-------------|-------|
| `# Header` | `*Header*` | All header levels |
| `**bold**` | `*bold*` | Single asterisks |
| `__bold__` | `*bold*` | Underscores → asterisks |
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

## Resources

- **Google Chat Formatting**: https://support.google.com/chat/answer/7649118
- **Markdown Guide**: https://www.markdownguide.org/basic-syntax/
- **Sed Reference**: https://www.gnu.org/software/sed/manual/sed.html
- **Unicode Bullet**: U+2022 (•)
