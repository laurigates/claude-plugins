---
name: youtube-studio-share
description: Share a private YouTube video with a whole Google Workspace organization by scripting YouTube Studio in the browser. Use when a video must be org-only.
allowed-tools: Read, AskUserQuestion, mcp__claude-in-chrome__javascript_tool
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# Org-only sharing in YouTube Studio (browser JavaScript)

On a Google Workspace channel, "visible only to my organization" is a sub-option
of Private, and the Data API has no way to set it: `status.privacyStatus`
accepts only `private`, `public` and `unlisted`. This skill drives YouTube
Studio's own dialog with JavaScript evaluated in the page. Elements are matched
by structure, role and aria state, with UI strings in English and Finnish as the
fallback. Nothing here uses screenshots or coordinates.

> **Pending live verification.** The flow and strings below were observed in
> one live session, but the scripts were written without a browser connected.
> Each step throws an error naming itself when an element is missing. Run
> `ytStudioProbe()` first and treat its report as the source of truth over this
> page. The fixture tests in `scripts/tests/` cover the control flow and the
> safety checks, not Studio's real DOM.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| A private video must be viewable by everyone in the Workspace domain | Uploading, or editing title/description/tags: `youtube-upload` (API) |
| Reading back what Studio shows after a save | Generating chapters or thumbnails: `video-plugin` |

`allowed-tools` pre-approves Claude in Chrome's JavaScript tool. Any browser
tool that evaluates JavaScript in the page works the same way; with another one
the call prompts for permission instead.

## Load the scripts

Open `https://studio.youtube.com/video/<id>/edit` (the `STUDIO_EDIT_URL` that
`youtube-upload` prints). Read each file from `scripts/` and evaluate it in the
page, `env.js` first:

| Script | Global | Purpose |
|---|---|---|
| `scripts/env.js` | `ytStudioEnv` | UI strings (en, fi), selectors, shadow-DOM-aware query, click and wait helpers |
| `scripts/probe.js` | `ytStudioProbe({ domain })` | Which selectors and strings resolve, signed-in account, visible errors |
| `scripts/studio.js` | `ytStudio` | `whoami`, `read`, `shareWithOrg`, `save`, `setField` |

## Workflow

1. **Check the account.** `ytStudio.whoami()` returns the `ytcfg` channel and
   session keys, the `authuser` index and the avatar label; credential-shaped
   keys are never returned. Confirm the channel with the user before any write:
   in practice the first browser profile was a personal account and the right
   one was in a second browser. If the result is inconclusive, open the account
   menu, read its text with JavaScript, and fall back to a screenshot only when
   that also fails.
2. **Probe.** `ytStudioProbe({ domain: 'forumvirium.fi' })`. Proceed only on
   `verdict: 'ok'`. Studio always contains hidden `ytcp-error-section` templates
   reading "Oops, something went wrong" (`Hups, jotain meni pieleen`); probe
   counts them under `hiddenErrorTemplates` and reports only visible ones as
   errors.
3. **Share.** `await ytStudio.shareWithOrg({ domain: 'forumvirium.fi' })` runs:
   Visibility, Private (`Yksityinen`), Share privately (`Jaa yksityisesti`), then
   in the "Share video privately" (`Jaa video yksityisenä`) dialog ticks "Give
   view access to all forumvirium.fi users" (`Anna katseluoikeus kaikille
   forumvirium.fi-käyttäjille`) and Done (`Valmis`). It leaves the email field
   empty.
   - **"Notify via email" (`Ilmoita sähköpostilla`) stays unchecked.** Checked,
     it could email the whole organization. The script unticks it if needed and
     throws rather than continue when it cannot see the checkbox.
   - The domain is matched against the checkbox label, so a tab signed in to a
     different Workspace fails at that step without ticking anything.
   - It does not save. On success the Visibility card reads "Shared privately
     with everyone at forumvirium.fi (save to share)" (`Jaettu yksityisesti
     kaikille osoitteessa forumvirium.fi (tallenna jakaaksesi)`) and the result
     has `unsaved: true`.
4. **Confirm with `AskUserQuestion`, then save.** `await ytStudio.save()` clicks
   Save (`Tallenna`) and waits for "(save to share)" to clear.
5. **Verify after a reload.** Reload the edit page, re-evaluate the scripts and
   call `ytStudio.read()`. Check `visibility` names the domain without the
   "(save to share)" marker. While processing runs, visibility shows "Pending"
   (`Odottaa`, `pending: true`). `hdReady` turns true when the "HD video ready"
   (`Teräväpiirtovideo valmis`) badge text exists; SD processing finishes first,
   HD a few minutes later.

## Editing title or description in the browser

Prefer `youtube-upload`'s `update` subcommand. When the browser is the only
route, `await ytStudio.setField('title', 'New', { replace: 'Old' })` selects a
DOM Range over the target text inside `#textbox[contenteditable="true"]`
(title is the first, description the second), inserts the replacement as typed
input, and reads `innerText` back. If the page refuses `insertText`, call
`ytStudio.selectText(field, target)` and type with the browser tool's typing
action, then call `ytStudio.read()`. Save and verify as in Workflow steps 4 and 5.

## Repairing selectors

When probe or a step fails, inspect the page rather than guess, and update
`STR` or `SEL` in `scripts/env.js`, the only copy. Studio uses Polymer `ytcp-*`
and `tp-yt-*` custom elements; `deepAll` already descends into open shadow
roots. Candidate selectors and which strings were observed live are listed in
[REFERENCE.md](REFERENCE.md).
