# Cold-Read Gate — Workflow-Script Integration

Moved verbatim from [SKILL.md](../SKILL.md). Open when running the gate as a stage
inside a `Workflow` script.

## Workflow-Script Integration

Inside a `Workflow` script the gate is one schema-enforced stage per item:

```javascript
const cold = await agent(
  `You are an upstream maintainer triaging a newly filed issue. NO context
   beyond the text. Read ONLY ${draft.path}. QUESTIONS / HESITATIONS /
   verdict. Ignore the top HTML comments (stripped before filing).`,
  { label: `coldread:${item.id}`, phase: 'ColdRead', model: 'haiku',
    schema: { type: 'object', properties: {
      verdict: { type: 'string', enum: ['clear', 'needs-revision'] },
      critique: { type: 'string' } },
      required: ['verdict', 'critique'] } },
)
if (cold?.verdict === 'needs-revision') { /* revise agent, then one re-read */ }
```
