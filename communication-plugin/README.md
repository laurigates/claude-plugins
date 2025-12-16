# Communication Plugin

External communication formatting plugin for Claude Code - specialized skills for Google Chat formatting and ticket drafting.

## Overview

This plugin provides two essential communication skills:

1. **Google Chat Formatting** - Convert Markdown to Google Chat compatible syntax
2. **Ticket Drafting Guidelines** - Structured approach to writing GitHub issues and technical tickets

## Installation

### Using the Plugin

To use this plugin in your Claude Code environment:

```bash
# Clone or copy to your plugins directory
cd ~/.claude/plugins/
git clone <repo-url> communication-plugin

# Or symlink from a local copy
ln -s /path/to/communication-plugin ~/.claude/plugins/communication-plugin
```

## Skills Included

### 1. Google Chat Formatting

Converts Markdown and plain text to Google Chat's limited formatting syntax.

**Key Features:**
- Transform Markdown headers to bold text
- Convert list markers to bullet symbols (•)
- Adapt bold/emphasis syntax to Google Chat format
- Preserve code blocks and inline code
- Mobile-friendly spacing and readability

**Activates when:**
- User mentions "Google Chat formatting"
- Converting Markdown for Google Chat
- Formatting messages for Google Chat

**Example Usage:**
```bash
# Convert clipboard content (macOS)
pbpaste | sed -E 's/^#{1,6} (.+)$/*\1*/g' | \
  sed -E 's/\*\*([^*]+)\*\*/\*\1\*/g' | \
  sed -E 's/^[*+-] /• /g' | pbcopy
```

**Conversion Rules:**
- `# Header` → `*Header*` (bold text)
- `**bold**` → `*bold*` (single asterisks)
- `- item` → `• item` (bullet symbol)
- `` `code` `` → `` `code` `` (unchanged)

**Location:** `/skills/google-chat-formatting/skill.md`

### 2. Ticket Drafting Guidelines

Structured guidelines for drafting GitHub issues and technical tickets using What/Why/How format.

**Key Features:**
- What/Why/How structure for clarity
- Concise writing with reference links
- Markdown standards and proper formatting
- Positive framing without negative phrasing
- Neutral tone without claims or estimates

**Activates when:**
- User requests to "draft a ticket"
- Writing GitHub issues or PRs
- Creating bug reports or feature requests
- Structuring technical documentation

**Template Structure:**
```markdown
## What
[Concise description of the subject]

## Why
[Context and motivation]

## How
[Implementation approach or resolution steps]
```

**Writing Principles:**
- Use affirmative language (what to do, not what to avoid)
- Maintain factual, objective tone
- Keep descriptions concise (1-3 sentences)
- Include links to official documentation
- Avoid estimates, percentages, or performance claims

**Location:** `/skills/ticket-drafting-guidelines/skill.md`

## Plugin Structure

```
communication-plugin/
├── .claude-plugin/
│   └── plugin.json          # Plugin metadata
├── skills/
│   ├── google-chat-formatting/
│   │   └── skill.md
│   └── ticket-drafting-guidelines/
│       └── skill.md
├── commands/                 # (empty - no commands)
├── agents/                   # (empty - no agents)
└── README.md
```

## Configuration

The plugin is configured via `.claude-plugin/plugin.json`:

```json
{
  "name": "communication-plugin",
  "version": "1.0.0",
  "description": "External communication formatting - Google Chat, ticket drafting",
  "keywords": ["communication", "google-chat", "formatting", "tickets"]
}
```

## Use Cases

### Google Chat Formatting

**Meeting Notes:**
```markdown
Input:  # Meeting Notes - 2024-01-15
        ## Attendees
        - Alice Johnson
        - Bob Smith

Output: *Meeting Notes - 2024-01-15*
        *Attendees*
        • Alice Johnson
        • Bob Smith
```

**Status Updates:**
```markdown
Input:  ## Project Status
        **Status:** In Progress
        **Blockers:** None

Output: *Project Status*
        *Status:* In Progress
        *Blockers:* None
```

### Ticket Drafting

**Feature Request:**
```markdown
## What
Add dark mode support to the web interface. This provides an alternative
color scheme that reduces eye strain in low-light conditions.

Reference: [CSS color-scheme](https://developer.mozilla.org/en-US/docs/Web/CSS/color-scheme)

## Why
Users requested dark mode in the feedback survey. Many users work in
low-light environments where bright interfaces cause discomfort.

## How
- Add theme toggle component to navigation
- Create CSS custom properties for color scheme
- Implement system preference detection
- Store user preference in localStorage
```

**Bug Report:**
```markdown
## What
Authentication token expires before refresh occurs. Users see login prompt
during active sessions.

See [JWT best practices](https://tools.ietf.org/html/rfc8725) for reference.

## Why
Token refresh logic waits until expiration before requesting new token.
Network latency causes gap between expiration and refresh completion.

## How
- Update refresh trigger to occur before expiration
- Add buffer time of 60 seconds before token expires
- Implement retry logic for failed refresh attempts
```

## Integration

These skills work alongside other Claude Code capabilities:

- **Git workflows** - Format commit messages and PR descriptions
- **Release management** - Structure release notes and changelogs
- **Documentation** - Convert docs for different platforms
- **Team communication** - Standardize issue and ticket formatting

## Best Practices

### Google Chat Formatting

1. Always test converted text in Google Chat before sharing
2. Check rendering on mobile devices
3. Keep lines short (60-80 characters) for readability
4. Use blank lines between sections
5. Format labels consistently (`*Label:* value`)

### Ticket Drafting

1. Research documentation before writing
2. Link to related issues and PRs
3. Keep descriptions concise (1-3 sentences)
4. Use positive, affirmative language
5. Maintain neutral, factual tone
6. Verify all links before submitting

## Limitations

### Google Chat Formatting

- No nested formatting (bold inside italic)
- No tables, images, or advanced Markdown
- 4096 character limit per message
- Limited link formatting

### Ticket Drafting

- Requires knowledge of issue/PR context
- Manual link verification needed
- Best suited for structured technical writing

## Contributing

To add or modify skills:

1. Edit skill files in `/skills/` directory
2. Follow existing skill structure (YAML frontmatter + Markdown)
3. Test in Claude Code environment
4. Update this README with changes

## Version History

- **1.0.0** - Initial release
  - Google Chat formatting skill
  - Ticket drafting guidelines skill

## License

(Add license information here)

## Author

Created for use with Claude Code's plugin system.

## Resources

### Google Chat Formatting
- [Google Chat Formatting Guide](https://support.google.com/chat/answer/7649118)
- [Markdown Guide](https://www.markdownguide.org/basic-syntax/)
- [Sed Reference](https://www.gnu.org/software/sed/manual/sed.html)

### Ticket Drafting
- [GitHub Issue Templates](https://docs.github.com/en/communities/using-templates-to-encourage-useful-issues-and-pull-requests)
- [Writing Better Issues](https://github.com/blog/2111-issue-and-pull-request-templates)
- [Technical Writing Guide](https://developers.google.com/tech-writing)
