# blueprint-work-order — Next-Action Prompt (Step 10)

Use AskUserQuestion:
```
question: "Work-order ready. What would you like to do?"
options:
  - label: "Execute this work-order (Recommended)"
    description: "Start working on the task with TDD workflow"
  - label: "Create another work-order"
    description: "Generate the next task from pending items"
  - label: "Delegate to subagent"
    description: "Hand off for isolated execution"
  - label: "I'm done for now"
    description: "Exit - work-order is saved and ready"
```
