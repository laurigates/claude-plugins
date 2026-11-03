---
name: kernel-lore-search
description: "Search kernel mailing lists via lore git mirrors. Use when checking prior art before a report, verifying a quote, or finding a sent message."
allowed-tools: Bash, Read, Grep, Glob
created: 2026-11-02
modified: 2026-11-02
reviewed: 2026-11-02
---

# Kernel Lore Search

lore.kernel.org archives every kernel mailing list. Its web pages and search sit
behind a bot challenge, so an agent reads lore through the **public-inbox git
mirrors** instead: each list is a git repository in which every commit is one
message.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Checking whether a problem was reported or patched before | Reading the code itself at a tag: `/kernel:source-history` |
| Verifying a quote before citing a maintainer | Searching GitHub issues of a userspace project: `github-actions-plugin:github-issue-search` |
| Confirming your own message reached the archive | Writing or sending the report: `/kernel:list-report` |

## 1. Use the Mirror, Not the Web Interface

WebFetch on lore gets a 403 or a challenge page. Sending a fake user agent to
get past the challenge is bot-check circumvention: Claude Code's auto-mode
classifier blocks it, and it should not be worked around. Cloning the mirror
with plain `git` is the documented way in.

## 2. Find the Epochs and Clone

Large lists are split into numbered epochs, newest highest. Probe until one is
missing:

```bash
for e in 0 1 2 3; do printf 'epoch %s: ' "$e"; git ls-remote "https://lore.kernel.org/linux-btrfs/$e" HEAD 2>&1 | head -1 | cut -c1-12; done
git clone -q --mirror https://lore.kernel.org/linux-xfs/git/0.git linux-xfs-0.git
```

- Both `https://lore.kernel.org/<list>/<N>` and
  `https://lore.kernel.org/<list>/git/<N>.git` worked as clone URLs.
- **Partial clone does not help:** `--filter=blob:none` printed
  `filtering not recognized by server, ignoring` and fetched everything. The
  full linux-xfs epoch 0 holds about 174,000 messages (2006–2026).
- Update an existing clone with `git fetch origin`; it is fast.

## 3. Search

Each commit's subject is the message subject, its author the sender, and the
raw RFC 822 message is the blob `m` in its tree.

```bash
cd linux-xfs-0.git
git log --all --format='%H %ad %s' --date=short --since=2021-01-23 --until=2021-01-26 | grep -i 'reflink/subvol'
git show <commit>:m | grep -i -m3 '^From:\|^Date:\|^Message-ID:'
git show <commit>:m | grep -i -B1 -A1 'diagnostic we use'
```

- **Subject and date filters** run on `git log` and are fast.
- **Body search** means reading `m` blobs: loop `git show <c>:m` over the
  candidates from a subject or date filter, or script a full pass for prior-art
  sweeps (the 2026-11 sweep regex-searched all 174k linux-xfs messages with a
  Python script; that script is not part of this skill).
- **Cross-list search** on lore's `/all/` index is web-only. Clone the other
  lists that matter (linux-fsdevel, linux-btrfs, linux-mm) instead.

## 4. Control-Test Every Negative

"Nobody reported this" gates a report, so prove the search can find things:

- Run a query you know must hit (`reflink` returned 12,518 linux-xfs messages)
  and report the count beside the empty ones.
- Before concluding a recent message is absent, look at the newest commits:
  `git log --all -3 --format='%ad %s' --date=iso`. In 2026-11 a
  `--since`/`--grep` filter returned nothing for a message sent minutes earlier
  while `git log --all -3` showed it at the top; the filter, not the archive,
  was wrong.

## 5. Verify Quotes Before Citing Them

A research agent's summary of a thread is a claim. Before a quote goes into a
report: find the message in the mirror, check the `From:` line, and grep the
exact words in its body, excluding lines that start with `>` (quoted text from
someone else). Cite the lore URL, which is the Message-ID without angle
brackets: `https://lore.kernel.org/<list>/<message-id>/`.

## 6. Confirm a Sent Message Was Archived

After `git send-email` returns `Result: 250`, the archive is the proof that the
list received it:

```bash
git -C linux-xfs-0.git fetch -q origin
c=$(git -C linux-xfs-0.git log --all -1 --format=%H)
git -C linux-xfs-0.git show "$c:m" | grep -m4 -i '^Message-ID:\|^From:\|^To:\|^Cc:'
```

In 2026-11 it was in the mirror within six minutes of sending. Record the Message-ID and the
lore URL where the investigation is tracked.

## 7. Kernel Bugzilla

bugzilla.kernel.org has a REST API, for example
`https://bugzilla.kernel.org/rest/bug?product=File%20System&component=XFS&summary=fiemap`.
Many subsystems, XFS among them, work on the mailing list rather than in
bugzilla, so an empty result there is weak evidence. (A research agent used the
API in 2026-11; the URL shape here is from its report, not re-run.)

## Agentic Optimizations

| Context | Command |
|---|---|
| Which epochs exist | `git ls-remote https://lore.kernel.org/<list>/<N> HEAD` |
| Messages by subject in a window | `git log --all --format='%H %ad %s' --date=short --since=<d> --until=<d> \| grep -i '<words>'` |
| Headers of one message | `git show <c>:m \| grep -m4 -i '^From:\|^Date:\|^Message-ID:\|^Subject:'` |
| Newest messages (control) | `git log --all -3 --format='%ad %s' --date=iso` |
| Permanent link | `https://lore.kernel.org/<list>/<message-id-without-brackets>/` |
