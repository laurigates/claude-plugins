# prompt-engineering-plugin

Prompt engineering techniques for accurate, grounded Claude responses.

## Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| ground-response | `/prompt-engineering:ground-response` | Citation-backed analysis with anti-hallucination workflow |

## ground-response

Produces grounded, citation-backed responses from source documents. Applies three techniques from Anthropic's official documentation:

1. **Permit uncertainty** — explicitly allows "I don't know" instead of confabulating
2. **Extract direct quotes first** — grounds analysis in word-for-word source text
3. **Verify claims against quotes** — audits every claim, retracts unsupported ones

### Usage

```
/prompt-engineering:ground-response What auth methods does this API support? --source docs/api.md
/prompt-engineering:ground-response Summarize the key decisions in this ADR --source decisions/
/prompt-engineering:ground-response Is this codebase using dependency injection? --source src/
```

### Output

Every response includes:
- Inline `[QN]` citations for each claim
- Supporting quotes table with exact text and source locations
- Explicit "What the source does not address" section
- Retracted claims (if any were unsupported)

## Install

Add to your Claude Code plugins configuration:

```json
{
  "name": "prompt-engineering-plugin",
  "source": "./prompt-engineering-plugin"
}
```
