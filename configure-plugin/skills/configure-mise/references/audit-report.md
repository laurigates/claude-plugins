# Audit Report Template

Used by Step 5 (Audit) to format the compliance report.

```
mise Configuration Report
=========================
Config file            mise.toml                 [PRESENT | MISSING]
Runtimes pinned        python, node              [PINNED | UNPINNED]
CLI backends           aqua / pipx               [SECURE | cargo-from-source | mixed]
pipx.uvx setting       true                      [SET | MISSING (pipx tools present)]
Lockfile               mise.lock                 [COMMITTED | MISSING]
Local overrides        mise.local.toml           [GITIGNORED | TRACKED ⚠ | n/a]
Trust                  trusted                    [TRUSTED | UNTRUSTED]
Legacy files remaining .tool-versions            [MIGRATED | STILL PRESENT]

Overall: [N issues]
```
