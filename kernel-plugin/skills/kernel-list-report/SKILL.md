---
name: kernel-list-report
description: "Write and send a report to a Linux kernel mailing list: recipients, plain text, git send-email. Use when reporting to linux-xfs, fsdevel or similar."
allowed-tools: Bash(git send-email *), Bash(git config --show-origin --get-regexp *), Bash(curl *), Bash(awk *), Bash(grep *), Read, Write, Edit, Grep, Glob
created: 2026-11-02
modified: 2026-11-14
reviewed: 2026-11-02
---

# Kernel Mailing-List Report

Kernel development happens by email. A report to a subsystem list is read by
maintainers in text mail clients, quoted line by line in replies, and archived
on lore forever, so it has to stand alone: mechanism, numbers, reproducer and
question in one plain-text message.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| Reporting a kernel bug, regression or performance problem to a list | Contributing to a GitHub-hosted project: `git-plugin:upstream-pr-contribution` |
| Asking maintainers a design question with measurements | Researching earlier threads first: `/kernel:lore-search` |
| Setting up `git send-email` to send it | Building the reproducer it carries: `/kernel:repro-harness` |

## 1. Before Writing: the Three Preconditions

| Precondition | Skill | What it buys |
|---|---|---|
| No earlier report or patch, or the thread to reply to instead | `/kernel:lore-search` | A new thread only when one is warranted, plus citations |
| The path is unchanged on current mainline and `for-next` | `/kernel:source-history` | Line numbers pinned to the newest tag; no "already fixed in -rc1" reply |
| A reproducer that runs without your application | `/kernel:repro-harness` | Something a maintainer can run in a minute |

## 2. Recipients

- **To:** the subsystem list, the `L:` line of the MAINTAINERS entry.
- **Cc:** the `M:` maintainers of that entry. Read MAINTAINERS at the newest tag:
  `curl -fsSL 'https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/plain/MAINTAINERS?h=<tag>' | awk '/^XFS FILESYSTEM$/,/^$/'`.
- **Extra Cc** (the author of the code, a reviewer who knows the area) only with
  an address verified from the `From:` line of their recent posts in the lore
  mirror. Leave them off rather than guess.

## 3. Format

| Do | Because |
|---|---|
| Plain text, lines wrapped at ~72 columns | vger rejects HTML mail; maintainers quote inline |
| Paste the reproducer source inline after the signature | The archive keeps message and code together; links rot and private repos are unreadable |
| Lead with the mechanism in function names, then the question in one sentence | A maintainer decides in the first screen whether to read on |
| Quote the stack with kernel version, arch and how it was captured | Frames differ by version (`/kernel:source-history`) |
| Give every number its configuration: kernel, machine, AG count, threads, median or mean of how many runs | A bare ratio cannot be checked |
| Cite commits as `<12-char sha> ("subject")` and threads as lore URLs | Readers can verify without asking |
| State caveats and unexplained results openly | It answers the first question before it is asked |
| Name the pushback you expect and answer it from sources | For example, "I am not suggesting dropping the flag", with the thread that shows it is used |
| End with what you can do: test patches, try one with guidance | Maintainers prioritise reports with a willing tester |

Draft into a file in the investigation repo with `To:`, `Cc:` and `Subject:`
header lines at the top and placeholders where the source files go. A bracketed
marker such as `[INLINE repro/run.sh AT SEND TIME]` keeps the reviewed draft
short.

## 4. Gate the Draft

1. `prose-plugin:prose-check` on the draft. Kernel shorthand (`ms`, `alloc`,
   `GiB`) dominates the grammar layer; judge the three tics and long sentences.
2. `agent-patterns-plugin:cold-read-gate` with the persona "an XFS kernel
   maintainer triaging a newly posted message", told to ignore the source
   placeholders. In 2026-11 the first reader returned `needs-revision`
   (unmapped numbers, an x86-only claim stated for both machines, references
   without identifiers) and the second `clear`.

## 5. Build the Send-Ready File

Substitute the sources by script, never by hand, and assert nothing is left:

```bash
python3 -c "
import sys
s=open('report/report.txt').read()
s=s.replace('[INLINE repro/fiemap-mt.c AT SEND TIME]\n', open('repro/fiemap-mt.c').read())
s=s.replace('[INLINE repro/run.sh AT SEND TIME]\n', open('repro/run.sh').read())
assert 'AT SEND TIME' not in s
open(sys.argv[1],'w').write(s)" report.eml
LC_ALL=C grep -n '[^ -~	]' report.eml   # no output: the message is ASCII
```

Rebuild after the draft's PR merges and `cmp` against the file you will send.

## 6. Send With git send-email

Setup (Gmail app password, scoped config, Keychain) is in
[REFERENCE.md](REFERENCE.md). The traps:

- **send-email adds every `To:` and `Cc:` header in the file** (`(mbox) Adding
  to: …`). A test send must use a copy whose headers were rewritten to your own
  address; assert the rewrite before sending.
- **Dry-run first, non-interactively**:
  `perl -e 'alarm 60; exec @ARGV' git send-email --dry-run --confirm=never report.eml </dev/null`.
  Without `</dev/null` it stops at a prompt and the command hangs.
- **The real send runs in the user's own terminal**, with `--confirm=always`.
  The first send prompts for the SMTP password, and a `!` command in Claude
  Code has no TTY.
- **Expected prompts:** "To whom should the emails be sent (if anyone)?" and
  "Message-ID to be used as In-Reply-To…" both take Enter for a new thread; the
  file's headers supply the recipients. Check the confirmation screen's `To:`
  and `Cc:` before answering `y`.
- **Success** is `Result: 250` from the SMTP server. Archive confirmation is
  `/kernel:lore-search` § 6.

Sending is the user's decision: present the dry-run output and the command,
and let them run it.

## 7. After Sending

- Record the Message-ID and lore URL in the investigation repo and close its
  tracking issue.
- Replies come by email, usually reply-all. Answer in plain text, quote inline
  below the lines you answer, and keep the list in Cc. From a file:
  `git send-email --in-reply-to='<their-message-id>' reply.eml`.
- If maintainers want a regression test, the reproducer's long-term home is an
  fstests case, sent as a patch to `fstests@vger.kernel.org`.

## Agentic Optimizations

| Context | Command |
|---|---|
| Recipients from MAINTAINERS | `curl -fsSL '…/plain/MAINTAINERS?h=<tag>' \| awk '/^<ENTRY>$/,/^$/'` |
| Line width check | `awk 'length > 76 && !/^Subject\|^To\|^Cc\|https/ {print FNR": "length}' report.txt` |
| ASCII check | `LC_ALL=C grep -n '[^ -~	]' report.eml` |
| Dry run | `perl -e 'alarm 60; exec @ARGV' git send-email --dry-run --confirm=never report.eml </dev/null` |
| Recipients a send would use | the dry run's `RCPT TO:` lines |
