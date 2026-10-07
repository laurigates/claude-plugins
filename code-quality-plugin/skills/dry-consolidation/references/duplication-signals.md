# DRY Consolidation — Duplication Signals

**Duplication signals to classify** (both the jscpd and the Grep path feed the same categories in Step 2):
- Utility functions defined identically in multiple files (string truncation, date formatting, validation)
- Identical error handling blocks (try/catch patterns, error state JSX)
- Copy-pasted UI fragments (pagination controls, confirmation dialogs, loading states)
- Repeated hook/state management patterns (delete confirmation + mutation + handler)
- Duplicated import blocks that signal repeated inline implementations
