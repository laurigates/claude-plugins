# session-wrap — Reference

Supporting detail for [SKILL.md](SKILL.md): the configuration schema,
journal mechanics, signal-filter examples, and edge cases.

## Configuration schema (`session-plugin.local.md`)

Location precedence: project `.claude/session-plugin.local.md` →
`~/.claude/session-plugin.local.md` → none (taskwarrior + GitHub only).
The file follows the `agent-patterns-plugin:plugin-settings` pattern:
YAML frontmatter for structured settings, markdown body for prose the
skills read as context.

| Frontmatter key | Type | Default | Meaning |
|---|---|---|---|
| `journal` | `obsidian` \| `markdown` \| `none` | `none` | Journal backend. `obsidian`/`markdown` both mean "dated markdown files"; `obsidian` additionally uses `[[wikilinks]]` |
| `journal_path` | path | — | Directory of dated notes, `YYYY-MM-DD.md` |
| `journal_template` | path | — | Template for creating a missing daily note |
| `journal_log_heading` | string | `## Log` | Heading to append narrative entries under |
| `journal_todo_heading` | string | `## Todo` | Heading to append `- [ ]` items under |
| `journal_todo_stop` | string | — | Subheading that ends the todo append region (insert new items *before* it) |
| `journal_scopes` | list | `[]` | Taskwarrior project prefixes that gate the journal destination |

Markdown body sections the skills read as context:

- **Scope detection** — heuristics for deciding a session is in journal
  scope (path patterns, git-remote patterns, conversation keywords).
- **Project naming map** — context → `project:` slug table so wraps land
  under consistent taskwarrior projects.

### Worked example (Obsidian journal config)

```markdown
---
journal: obsidian
journal_path: ~/Documents/YourVault/Journal/notes
journal_template: ~/Documents/YourVault/Templates/Daily.md
journal_log_heading: "## Log"
journal_todo_heading: "## Todo"
journal_todo_stop: "### Recurring reminders"
journal_scopes: [work, infrastructure]
---

# Scope detection

The session is in journal scope if ANY of: the taskwarrior project is
`work.*` or `infrastructure*`; the cwd contains the work-org directory
(e.g. `repos/<org>`); the user says so ("this is work"); the
conversation references work repos, ticket items, or internal
infrastructure. Default to out-of-scope when in doubt.

# Project naming map

| Context | project: |
|---|---|
| Work infrastructure | `work.<area>` (e.g. `work.cost-attribution`) |
| A work sub-project | `infrastructure.<name>` |
| claude-plugins work | `claude-plugins`, `claude-plugins.friction` |
| Dotfiles / chezmoi | `dotfiles` |
| Personal vault | `immeral` |
```

## Journal append mechanics

- Daily note path: `<journal_path>/YYYY-MM-DD.md` (today).
- If the file doesn't exist and `journal_template` is set, create it from
  the template (preserve frontmatter and any structural blocks).
- Append narrative items under `journal_log_heading`; append `- [ ]`
  items under `journal_todo_heading`, *before* `journal_todo_stop` when
  set.
- Touch only those two regions — other sections are the user's own voice
  or structural machinery.
- `journal: obsidian` → use `[[wikilinks]]` for cross-references; full
  URLs for PRs and external systems.
- Don't write the journal silently: it is part of the user's personal
  vault, hence the AskUserQuestion gate in Step 3.
- A prior wrap already wrote today? Append cleanly; skip exact-string
  duplicates only.

### Log entry shape

One or two sentences each, with a link for follow-through; group by
topic at 3+ items:

```
- Cost-attribution: PR #1778 landed; #1774 still open after 7 days.
- Hetzner decom: db01-03 need owner pings before shutdown (Podio #838).
```

### Todo entry shape

Single `- [ ]` line with enough context to act without re-reading the
conversation. The redundancy test applies here too — a todo whose whole
content is "merge / nudge PR #N" duplicates a tracker that already
surfaces itself, so write the todo only for the part the PR can't hold:

```
- [ ] Confirm Hetzner db01-03 shutdown date with Aapo (Podio #838)
- [ ] Decide OpenCost vs Kubecost before the ADR-0029 review (no artifact yet)
```

## Taskwarrior conventions

- Add: `task rc.confirmation:no add project:<slug> +<tag> [priority:H] '<description>'`
  — description must make sense in 6 weeks with no context (reference PR
  numbers, paths, decision criteria inline).
- Prefer annotating over adding when a PR or issue already tracks the
  item: `task <uuid> annotate '<PR URL> — <the gate>'` links the two so
  `taskwarrior-plugin:task-reconcile` closes the task when the PR merges.
  A task added *because* a PR is open has no such upside — reconcile just
  closes it later.
- Annotate before closing (`task <uuid> annotate "..."` then
  `task rc.confirmation:no <uuid> done`) — completed tasks lose their
  numeric ID.
- Always carry UUIDs across turns, never numeric IDs — the pending-set
  index shifts on every completion anywhere.
- `priority:H` only for genuinely time-sensitive work.

## Signal-filter examples

| Candidate | Verdict | Why |
|---|---|---|
| PR #1774 opened, awaiting review; task `aaaa-1111` covers that work | Annotate `aaaa-1111` with the PR URL — **no new task** | The annotation is what lets `task-reconcile` close it on merge; the PR itself is the reminder |
| PR #1774 opened, awaiting review; no task exists | SKIP | The digest's `PRS` section replays it next session with `PR_n_STALE_DAYS` — a "merge PR #1774" task would only duplicate it |
| Assigned issue #851 filed today, no local task | SKIP | `GITHUB_DRIFT` surfaces assigned-but-untracked issues at spinup |
| PR #1774 merged, but a DNS record must be flipped by hand afterwards | LOG (GitHub issue linked from the PR) | Post-merge step the PR body can't carry once closed |
| Commit landed, PR merged, task complete | task done only | Finished cleanly; narrating it is noise |
| "We should revisit the retry logic someday" | SKIP | Speculation, rot-magnet |
| Invalid version spec found in passing | LOG (new task) | Real bug, no PR or issue holds it |
| CI still running on a green-trending PR | SKIP | Self-resolving |
| Deploy step the user must run by hand | LOG | Manual follow-up outside Claude Code |

## Edge cases

- **Multiple projects touched** — wrap each independently; one preview
  block per project.
- **No active project detected** — ask which project to log under (or
  "skip taskwarrior pass").
- **User wants to skip the journal** for an in-scope session — honor it;
  the taskwarrior pass still runs.
- **User wants the journal for an out-of-scope session** — honor it
  (default off, override on).
- **No github.com origin** — skip the GitHub-issue pass entirely.

## Rationale

The cross-session tracking rule says "log work that outlives the session
to taskwarrior". This skill enforces it at the natural checkpoint (end of
session) and adds an optional journal destination for narrative
continuity. The signal filter is the value: a wrap that captures 4 real
loose threads beats one that mechanically lists everything touched.

The same rule cuts the other way, which is why the redundancy test exists:
that cross-session rule also says *don't* duplicate something already
tracked durably. An open PR or issue is durable tracking, and
`session-plugin:session-spinup` reads it back — so mirroring it into
taskwarrior buys nothing and costs a task the user has to dismiss twice.
