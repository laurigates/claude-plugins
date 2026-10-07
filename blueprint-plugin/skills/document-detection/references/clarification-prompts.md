# document-detection — Step 2 Clarification Prompts

One AskUserQuestion per document type, asked after the user accepts.

**For PRD**:
```
question: "Who are the primary users for this feature?"
options:
  - label: "End users"
    description: "Regular users of the application"
  - label: "Administrators"
    description: "Admin users with elevated access"
  - label: "Developers"
    description: "Internal development team"
  - label: "Multiple types"
    description: "I'll specify the user types"
```

**For ADR**:
```
question: "What constraints should I consider for this decision?"
options:
  - label: "Performance requirements"
    description: "Speed, latency, throughput constraints"
  - label: "Team expertise"
    description: "Team familiarity with technologies"
  - label: "Budget/cost"
    description: "Financial or resource constraints"
  - label: "Timeline"
    description: "Delivery deadline constraints"
  - label: "All of the above"
    description: "Consider all constraint types"
```

**For PRP**:
```
question: "What's the priority and scope for this implementation?"
options:
  - label: "High priority, narrow scope"
    description: "MVP implementation, ship quickly"
  - label: "High priority, full scope"
    description: "Complete implementation needed soon"
  - label: "Normal priority"
    description: "Standard development timeline"
  - label: "Exploratory"
    description: "Spike or proof of concept"
```
