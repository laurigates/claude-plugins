# Bulk Sweep — Command Templates

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Enumerate deduped matches | `git grep -nhoE '<pattern>' -- <scope> \| sort -u` |
| Count matches per file | `git grep -cE '<pattern>' -- <scope>` |
| Preview a scoped transform | `perl -ne 's{<from>}{<to>}g and print' <files>` |
| Apply to category-1 files only | `perl -i -pe 's{<from>}{<to>}g' <category-1 files>` |
| Verify preserved-set only | `git grep -nE '<pattern>' -- <scope>` (expect only categories 2–4) |
