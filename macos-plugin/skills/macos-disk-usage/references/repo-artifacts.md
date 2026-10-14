# macOS Disk Usage — Git-Ignored Generated Artifacts Inside Repos

Read this file from [SKILL.md](../SKILL.md) when an `UNKNOWN` line from the suspect scan lands inside a git repository.

The catalog cannot list repo-specific outputs that sit git-ignored inside a project, such as large model fixtures, re-saved weights and build outputs. List the repo's ignored paths and size them:

```bash
git -C <repo> ls-files --others --ignored --exclude-standard --directory | sed "s|^|<repo>/|" | tr '\n' '\0' | xargs -0 du -sh 2>/dev/null | sort -h | tail
```

Trace provenance before deleting anything. The `.gitignore` comment and the justfile/Makefile recipe that writes the file usually say whether it was downloaded or derived, and how to regenerate it. Delete derived copies first: they regenerate locally, while a downloaded original has to be fetched again.
