---
name: tui-keybinding-debug
description: "Debug dead TUI/terminal keybindings — terminal interception (kitty), layout-impossible chords, legacy key aliasing. Use when a configured key does nothing in a TUI, fzf, or shell app."
allowed-tools: Bash, Read, Grep
created: 2026-07-05
modified: 2026-07-05
reviewed: 2026-07-05
---

# TUI Keybinding Debug

## When to Use This Skill

| Use this skill when... | Use something else when... |
|------------------------|----------------------------|
| A configured key does nothing in a TUI (ratatui/crossterm/promkit app), fzf, or a shell picker — no error, no reaction | The app throws a visible error on the key — that's an app bug, debug the app |
| A keybind works on one terminal and is dead on another | You're setting up a *new* keybind and want conventions — this is for diagnosing a *dead* one |
| An fzf/`gh` picker's `ctrl-/` (or other punctuation-Ctrl) toggle does nothing on a non-US keyboard | The key is dead in the shell line editor itself — that's zsh/readline keymap territory, not terminal interception |
| You need to prove *where* a keystroke dies before touching code | General terminal/session recovery — see `kitty-session-persistence` |

## The Core Insight

When a TUI key "does nothing," the instinct is to debug the **app** — its keymap, event matching, focus model. That instinct is wrong about half the time. A keystroke passes through three layers before the app can match it, and it can die silently at any of them:

1. **Terminal interception** — the terminal (kitty, WezTerm, Ghostty, foot) consumes its own configured shortcut *before the program sees the byte*. No bytes reach the app, so no app-side config or code can catch it.
2. **Layout-impossible chord** — on a non-US layout the character itself needs a modifier, so the Ctrl-combo is unproducible. The terminal never emits it; there is nothing to intercept.
3. **App-side legacy aliasing** — the key *does* reach the app, but legacy terminal encoding aliases distinct keys to the same byte (`Ctrl+J` == `Enter`), so the binding fires the wrong action.

**Diagnose the layer first.** One debug run settles where the key dies in seconds, converting an open-ended app-side hunt into a targeted fix. Prefer a key the terminal forwards: bare `Ctrl+<letter>` is the only Ctrl-space that exists on every keyboard layout *and* passes through every terminal.

## Execution

Diagnose this dead-keybinding failure by proving which of the three layers is eating the key. Work top-down — cheapest, most-common cause first.

### Step 1: Prove where the key dies (terminal vs app)

Run these two kitty probes and press the dead key. (Adapt for other terminals — most have a key-debug mode; the reasoning is identical.)

```
kitty +kitten show_key -m kitty
```

Press the dead key. **Nothing printed = the terminal ate it** (layer 1 or 2). A clean `CSI ... u` / escape sequence printed = the key *is* reaching the app, so the bug is app-side (jump to Step 4).

```
kitty --debug-keyboard
```

Press the dead key and read the log. The smoking gun is a line like:

```
KeyPress matched action: <X>, handled as shortcut
```

`handled as shortcut` means the terminal claimed the key — confirm layer 1 and go to Step 2. If `show_key` printed nothing *and* the chord involves a shifted/AltGr character on your layout, suspect layer 2 (Step 3) before the terminal.

### Step 2: Layer 1 — terminal interception

The terminal grabbed the key. Identify whether it's a **user-config** map (changeable) or a **built-in default** (usually not). Grep the kitty config for a map on the offending key:

```
grep -niE '^\s*map\s+' ~/.config/kitty/kitty.conf
```

Match the dead chord against this table of commonly-intercepted combos:

| Combo | Frequently grabbed by | Default or user config? |
|-------|-----------------------|-------------------------|
| `Shift+Arrow` | kitty `move_window` (user config); macOS text-selection (`moveDownAndModifySelection:`) | User config (kitty) — doubly spoken-for on macOS |
| `Ctrl+Shift+Arrow` | kitty scrollback scroll | **Built-in default** — won't appear in `kitty.conf` |
| `Ctrl+Arrow` | kitty `neighboring_window` / word-motion remaps | Often user-mapped |
| `Cmd+*`, `Ctrl+Shift+*` | the terminal's entire shortcut namespace | Reserve for the terminal |
| bare `Ctrl+<letter>` | **passes through to the app** (except flow-control `Ctrl+S`/`Ctrl+Q`, suspend `Ctrl+Z`) | The safe space for app keybinds |

**Fix, in order of preference:**

1. **Rebind the app to a key the terminal forwards** — a bare `Ctrl+<letter>` the app doesn't already use (e.g. `switch_mode = ["Ctrl+T"]`). This is the robust fix: it dodges interception everywhere.
2. **Free the key in the terminal** — only if it's a *user* map: `map shift+down no_op` in `kitty.conf`. A built-in default (like `Ctrl+Shift+Arrow` scrollback) usually can't be freed cleanly without overriding it.

Distinguishing default from user config matters: a user map is changeable; a built-in default is not (without an override that may cost you the terminal feature).

> Canonical break (jnv on kitty): the JSON-viewer nav keys looked completely dead. Root cause was not jnv — kitty intercepted `shift+down`/`shift+up` (mapped to `move_window` in the user's `kitty.conf`), so jnv's `switch_mode` focus-switch never fired. Two replacement guesses also collided: `ctrl+shift+arrow` is a kitty built-in scrollback default. The fix was bare `Ctrl+T` — a key kitty forwards.

### Step 3: Layer 2 — layout-impossible chord

On non-US layouts the character itself needs a modifier, so a Ctrl-combo over it can never be typed — the terminal never emits it, and **nothing intercepts it, it simply doesn't exist**. The failure is extra-invisible because a header hint (`^/ preview`) reads as a truncated or garbled label rather than an impossible chord.

Finnish / Nordic ISO layout examples — each of these requires `Shift`/`AltGr`, so the bare Ctrl-combo is unproducible:

| Character | How it's typed on Finnish ISO | Ctrl-combo over it |
|-----------|-------------------------------|--------------------|
| `/` | `Shift+7` | `Ctrl+/` can never fire |
| `?` | `Shift++` | `Ctrl+?` dead |
| `\` | `AltGr+<` | `Ctrl+\` dead |

**Rule of thumb: punctuation Ctrl-combos (`ctrl-/`, `ctrl-?`, `ctrl-\`, `ctrl-]`, `ctrl-;` …) are layout-dependent — treat them as unavailable** when authoring binds meant to work across keyboards. The diagnosis is the same `show_key` run: if pressing the chord prints nothing *and* the character is shifted/AltGr on your layout, the layout is the culprit, not the terminal.

**Fix:** rebind to a bare `Ctrl+<letter>` — the only Ctrl-space that exists on every layout and passes through every terminal.

> Canonical break (dotfiles): every `gh` fzf picker bound `ctrl-/:toggle-preview`; on a Finnish layout the preview toggle was dead in all of them because the keyboard has no bare `/` key. Fix: rebind to bare `Ctrl+T`.

### Step 4: Layer 3 — app-side legacy key aliasing (crossterm)

The key reached the app (Step 1's `show_key` printed a sequence), but legacy terminal encoding aliases distinct keys to the same byte, so a binding fires the wrong action or is unreachable:

| Bound key | Legacy byte | Actually fires |
|-----------|-------------|----------------|
| `Ctrl+J` | `0x0A` | **`Enter`** — a `Ctrl+J` binding triggers `Enter` |
| `Ctrl+I` | `0x09` | **`Tab`** |
| `Ctrl+M` | `0x0D` | **`Enter`** |
| `Ctrl+H` | (decodes to `Char('h')`+CONTROL in crossterm — *not* Backspace) | `Ctrl+H` |

**Fix — negotiate the keyboard enhancement protocol** so these disambiguate. Push `KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES` when `supports_keyboard_enhancement()` is true, and pop it on teardown:

```rust
use crossterm::event::{
    KeyboardEnhancementFlags, PushKeyboardEnhancementFlags, PopKeyboardEnhancementFlags,
};
use crossterm::terminal::supports_keyboard_enhancement;

if supports_keyboard_enhancement().unwrap_or(false) {
    execute!(stdout, PushKeyboardEnhancementFlags(
        KeyboardEnhancementFlags::DISAMBIGUATE_ESCAPE_CODES,
    ))?;
}
// ... run the app ...
execute!(stdout, PopKeyboardEnhancementFlags)?; // on teardown
```

**Caveat — normalize events first, or the protocol breaks exact matches.** If the app matches keybinds by exact `Event` equality, enabling the protocol also makes **release/repeat events** and **`KeyEventState` lock-bits** (Caps/Num Lock) possible — both break exact matches. At the single event-read chokepoint:

1. Drop non-`Press` events (ignore release/repeat).
2. Strip `KeyEventState` to `NONE`.
3. Request **only** `DISAMBIGUATE_ESCAPE_CODES` — *not* `REPORT_EVENT_TYPES` — to keep the stream close to legacy.

## Agentic Optimizations

| Context | Command |
|---------|---------|
| Does the app receive the key at all? | `kitty +kitten show_key -m kitty` (press key; nothing printed = terminal ate it) |
| Does the terminal claim the key? | `kitty --debug-keyboard` (grep the log for `handled as shortcut`) |
| List user key-maps in kitty config | `grep -niE '^\s*map\s+' ~/.config/kitty/kitty.conf` |
| Check for a map on a specific chord | `grep -niE '^\s*map\s+ctrl\+t' ~/.config/kitty/kitty.conf` |
| Query terminal capabilities | `kitten query_terminal` |

## Quick Reference

| Symptom | Likely layer | Fix |
|---------|--------------|-----|
| `show_key` prints nothing; `--debug-keyboard` shows `handled as shortcut` | 1 — terminal interception | Rebind app to bare `Ctrl+<letter>`, or `no_op` the user map |
| `show_key` prints nothing; chord is a shifted/AltGr punctuation on your layout | 2 — layout-impossible | Rebind to bare `Ctrl+<letter>` |
| `show_key` prints a sequence; wrong action fires (`Ctrl+J`→Enter, `Ctrl+I`→Tab) | 3 — legacy aliasing | Enable `DISAMBIGUATE_ESCAPE_CODES` + normalize events |
| `show_key` prints a clean sequence; app still doesn't react | app keymap/focus | Debug the app — the key *is* arriving |

## Related

- `kitty-session-persistence` — kitty session snapshot/restore (sibling kitty skill)
- The user-global `kitty-agent-interaction.md` rule — the read-only kitty remote-control surface; this skill is its keyboard-interception debugging complement.
