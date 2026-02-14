# Google Chat Formatting - Reference

Detailed reference material for Google Chat formatting conversion patterns.

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
- Keep numbered lists intact as-is

### Formatting Best Practices

**Use separate formatting for bold and italic**:
```
*bold* and _italic_     (separate)
```

**Keep whitespace clean**:
```
*Header*

Content (no trailing spaces, no extra indentation)
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
    echo "Converted to Google Chat format (in clipboard)"
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

    echo "Created: $output"
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
    echo "Commit message formatted for Google Chat"
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
