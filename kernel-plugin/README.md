# Kernel Plugin

Workflows for investigating Linux kernel behaviour and reporting it upstream:
reading the source at named tags, researching the mailing-list archive,
reducing an application's problem to a standalone reproducer, and sending a
report to a kernel list.

Kernel development is email-based, so these skills work with lore, MAINTAINERS
and `git send-email` rather than GitHub pull requests. Related skills elsewhere:

- `code-quality-plugin:debugging-methodology` finds where threads block (context
  switches, `wchan`, bpftrace off-CPU stacks) before this plugin's work starts.
- `cloud-plugin:gcp-throwaway-vm` rents the stock-kernel VM for checkpoint runs.
- `prose-plugin:prose-check` and `agent-patterns-plugin:cold-read-gate` gate the
  report draft.
- `git-plugin:upstream-pr-contribution` covers contributions to GitHub-hosted
  projects instead.

## Skills

| Skill | Description |
|-------|-------------|
| `kernel-source-history` | Read kernel source at a tag from git.kernel.org, diff functions across releases and `for-next`, find the first release containing a commit, and handle stack frames that differ by version |
| `kernel-lore-search` | Search lore through the public-inbox git mirrors: prior-art sweeps with control queries, quote verification, and confirming a sent message was archived |
| `kernel-repro-harness` | Build a reproducer maintainers can rerun: a minimal multithreaded syscall loop, control trees, loop-device images, matching the real workload's contention domain, OrbStack first and GCP at checkpoints |
| `kernel-list-report` | Write and send a report to a kernel list: recipients from MAINTAINERS, plain-text format with the reproducer inline, draft gates, and `git send-email` through Gmail |

The skills grew out of a 2026-11 report to linux-xfs about FIEMAP on reflinked
files serialising on the AGF buffer lock; the worked examples come from it.

## Installation

```bash
claude plugin install kernel-plugin@laurigates-claude-plugins
```

## License

MIT
