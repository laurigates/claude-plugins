---
name: kitty-show-image
description: Show the user an image with a note on what to judge, via a file send or a labelled kitty tab. Use when the user must see an image, or icat fails with no /dev/tty.
allowed-tools: Bash(bash *), Bash(kitty @ ls), Bash(kitty @ ls *), Bash(kitty @ get-text *), Bash(open *), Bash(xdg-open *), Read, Write
created: 2026-10-24
modified: 2026-11-09
reviewed: 2026-11-09
---

# Showing an Image to the User

Claude Code cannot draw images inside the chat. Kitty's graphics protocol
needs escape codes written to a real terminal, and both the Bash tool and the
user's `!` commands run without `/dev/tty`. A plain `kitty +kitten icat` from
either fails with `open /dev/tty: device not configured`.

## When to Use This Skill

| Use this skill when... | Use something else when... |
|---|---|
| The user should look at a screenshot, render or diagram | Only Claude needs to see the image: `Read` it directly |
| A visual gate needs the user's verdict on an image | Running other `kitty @` commands: `kitty-remote-control` |
| `kitty +kitten icat` fails with `open /dev/tty: device not configured` | A keybinding does nothing in kitty: `macos-plugin:tui-keybinding-debug` |

## Every image goes out with a note

The user should never have to switch back to the chat to find out what they
are looking at. Whichever channel you use, send the explanation with the image:

- **What it is**: the subject, the run or commit, and what each panel shows
  when the image has several.
- **What to look at**: for several figures or regions, a table of each one and
  what it should show.
- **What is expected to look off for now**, so the user doesn't report a known
  gap.
- **For a decision**: the question and the exact answer to type back in Claude
  Code ("23 accept", or name the figure that is wrong).

For the kitty tab, write the note to a file and pass `--note`. For a file-send
tool, put the same text in its caption. Send one image per question.

## Pick the channel

| Situation | Channel |
|---|---|
| Default, when the session has a tool that sends a file to the user (for example `SendUserFile`) | That tool, rendered inline, with the note as its caption. It does not touch the terminal, and the file can reach the user's other devices. |
| The user wants it in kitty, or asked to see it "here" | [`show-image.sh`](#show-imagesh). It opens and focuses a tab, so it needs the user's ask; one ask covers the rest of that session's images. |
| No file-send tool, not in kitty (`$KITTY_WINDOW_ID` unset), and the user is at this machine | The desktop viewer: `open <file>` on macOS, `xdg-open <file>` on Linux. Print the note in the chat. |

## show-image.sh

```
bash "${CLAUDE_SKILL_DIR}/scripts/show-image.sh" [--note FILE] IMAGE [IMAGE...]
```

It needs kitty remote control: `allow_remote_control` and `listen_on` set in
`kitty.conf`, so `$KITTY_LISTEN_ON` is exported into the shell. Check with
`kitty @ ls` (read-only) before the first use.

Opens a tab titled **Claude: image viewer** with a banner saying it is
Claude Code's image viewer. Under the images it prints their file names and
then the `--note` text, just above the key prompt. With several images, only
the last stay on screen above the note; earlier ones scroll off the top. One
key press closes the tab, after which kitty returns focus to the previous tab.
The script prints the new window id. To confirm the tab rendered, read it
without touching it: `kitty @ get-text --match id:<id>`.

| Exit | Meaning | Next step |
|---|---|---|
| 0 | Tab launched | Tell the user which tab to look at and that a key press closes it |
| 1 | Bad arguments or missing file | Fix the path |
| 2 | Not in kitty, or remote control unreachable | Fall back to a file-send tool or the desktop viewer |

## Don't

- **Don't send an image without its note.** A bare image makes the user switch
  back to the chat to find out what to judge.
- **Don't hand the user `! kitty +kitten icat …`.** The `!` shell has no TTY,
  so it fails the same way the Bash tool does.
- **Don't use `kitty @ launch --hold`, or `--type=overlay` without a banner.**
  `--hold` leaves an interactive shell prompt behind. An unlabelled overlay with
  a prompt looks exactly like Claude Code has exited; a user who hit this tried
  `fg` before discovering that `ctrl+d` got them back.
- **Don't close the tab for the user.** It closes on their key press;
  `close-window` is on the destructive list in `kitty-remote-control`.

## Agentic Optimizations

| Context | Command |
|---|---|
| Is remote control reachable? | `kitty @ ls >/dev/null && echo ok` |
| Did the tab render? | `kitty @ get-text --match id:<id>` |
| Script contract test | `bash "${CLAUDE_SKILL_DIR}/scripts/tests/test-show-image.sh"` |
