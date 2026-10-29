# YouTube Plugin

Upload and manage YouTube videos from Claude Code. The YouTube Data API v3 does
everything it can: upload, metadata edits, thumbnails, read-back. YouTube Studio
in the browser covers the one step the API has no field for, sharing a private
video with a whole Google Workspace organization, through JavaScript evaluated
in the page.

```
claude plugin install youtube-plugin@laurigates-claude-plugins
```

## Skills

| Skill | Description |
|-------|-------------|
| `/youtube-plugin:youtube-upload` | Resumable `videos.insert` with title, description, tags, category, privacy and the made-for-kids and synthetic-media disclosures; `thumbnails.set`; `videos.update` for edits after upload; `--dry-run` prints the exact request |
| `/youtube-plugin:youtube-studio-share` | Studio page scripts: signed-in account check, selector probe, Private, Share privately, view access for the whole Workspace domain with email notification kept off, save and read-back |

Chapter lines and thumbnail frames come from `video-plugin`.

## Prerequisites

- `uv` (the API script declares its dependencies inline, PEP 723).
- A Google Cloud project with the YouTube Data API v3 enabled and a Desktop
  OAuth client. `YOUTUBE_CLIENT_SECRETS` names the client JSON; the token is
  cached in `${XDG_CONFIG_HOME:-~/.config}/youtube-plugin/`. Steps:
  [`skills/youtube-upload/REFERENCE.md`](skills/youtube-upload/REFERENCE.md#one-time-oauth-setup).
- For Studio sharing, a browser tool that can evaluate JavaScript in a
  `studio.youtube.com` tab signed in to the channel owner's account.

## Status

The API script's validation, request building and update merge are unit-tested,
and its `--dry-run` output is tested; no request has been sent to the live API.
The Studio scripts pass a jsdom fixture test of the observed flow in English and
Finnish, but have not been run against the live Studio page. `ytStudioProbe()`
reports which selectors resolve there.
