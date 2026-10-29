---
name: youtube-upload
description: Upload a video to YouTube via the Data API v3 and edit its title, description, tags or thumbnail afterwards. Use when publishing or retitling a YouTube video.
allowed-tools: Bash(uv run *), Bash(python3 *), Read, AskUserQuestion
args: "[video-file | video-id]"
argument-hint: path to a video to upload, or the id of an uploaded video to edit
created: 2026-10-29
modified: 2026-10-29
reviewed: 2026-10-29
---

# YouTube upload and edit (Data API v3)

`scripts/youtube_api.py` wraps the four calls this needs: a resumable
`videos.insert`, `thumbnails.set`, `videos.update`, and `videos.list` for
read-back. Every write subcommand has `--dry-run`, which validates the input
and prints the exact request without network access or the Google client
libraries.

## When to Use This Skill

| Use this skill when... | Use instead when... |
|---|---|
| Uploading a video file, setting its metadata and thumbnail | The video should be visible only to a Workspace organization: upload here, then `youtube-studio-share` |
| Changing a title, description, tags, category or privacy after upload | Generating chapter lines or extracting a thumbnail frame: `video-plugin` |

## Before anything else

1. **OAuth is set up once.** `YOUTUBE_CLIENT_SECRETS` must name a Desktop OAuth
   client JSON, and `uv run ${CLAUDE_SKILL_DIR}/scripts/youtube_api.py auth` must
   have been run. If either is missing, stop and point the user at
   [REFERENCE.md](REFERENCE.md) § One-time OAuth setup. The token is cached at
   `${XDG_CONFIG_HOME:-~/.config}/youtube-plugin/token.json` (mode 0600),
   outside any repository.
2. **Confirm the channel.** Run `whoami` and show the user `CHANNEL_TITLE` and
   `CHANNEL_HANDLE`. The token belongs to whichever Google account consented,
   and the wrong account is the common failure: in practice the first browser
   profile was a personal account and the right one was in a second browser.

## Workflow: upload

1. **Collect the metadata.** Title (100 characters max, no `<` or `>`),
   description file (5000 bytes max), tags, category id (`categories --region FI`
   lists valid ids; the default is 22), privacy (default `private`).
   Chapter lines in the description come from `video-plugin`; the script checks
   YouTube's chapter rules (first at 0:00, at least 3, each at least 10 s) and
   reports violations as `STATUS=WARN`.
2. **Ask for the two disclosures.** Both flags are required, and neither has a
   default, because both are the uploader's statement:
   - `--made-for-kids yes|no` sets `status.selfDeclaredMadeForKids`.
   - `--synthetic-media yes|no` sets `status.containsSyntheticMedia`, YouTube's
     disclosure for realistic altered or synthetic content (AI-generated
     footage or voice included). Whether a video needs it is the uploader's
     call; ask, never infer.
3. **Dry run.** Show the user `REQUEST_BODY`:
   ```
   uv run ${CLAUDE_SKILL_DIR}/scripts/youtube_api.py upload clip.mp4 --title "…" --description-file desc.txt --tag … --made-for-kids no --synthetic-media no --thumbnail thumb.jpg --dry-run
   ```
4. **Confirm with `AskUserQuestion`**, then run the same command without
   `--dry-run`. It prints `VIDEO_ID`, `WATCH_URL` and `STUDIO_EDIT_URL`. A
   failed thumbnail after a successful upload is a `WARN`; the video id is
   still reported, and `thumbnail <id> <image>` retries only the thumbnail.
5. **Org-only sharing**, when asked for, follows in the browser with
   `youtube-studio-share`. The API cannot do it: `status.privacyStatus` accepts
   only `private`, `public` and `unlisted`, and no field or method shares a
   private video with people or a domain.

## Workflow: edit after upload

```
uv run ${CLAUDE_SKILL_DIR}/scripts/youtube_api.py update <id> --title "New title" --dry-run
uv run ${CLAUDE_SKILL_DIR}/scripts/youtube_api.py update <id> --description-file desc.txt
```

`videos.update` deletes every mutable property of a named part that the request
omits, so a body carrying only a new title would wipe the description and tags.
`update` therefore reads the current `snippet` and `status` first and resends
them merged with the change. The dry run cannot read the live video; pass
`--current-json` with a saved `videos.list` item to preview the merged body.

## Verify

Run `status <id>` after any write and compare `TITLE`, `PRIVACY` and
`CHAPTER_COUNT` against what was sent. Processing is staged: SD is ready first,
HD a few minutes later. `PROCESSING_STATUS=processing` corresponds to Studio
showing visibility as "Pending" (`Odottaa`).

## Quota

| Call | Cost | Bucket |
|---|---|---|
| `videos.insert` | 1 unit | Video Uploads, 100 calls/day by default |
| `videos.update` | 50 units | shared 10,000 units/day |
| `thumbnails.set` | 50 units | shared |
| `videos.list`, `channels.list`, `videoCategories.list` | 1 unit | shared |

Source: [Quota costs for API requests](https://developers.google.com/youtube/v3/determine_quota_cost)
(page last updated 2026-10-15, read 2026-10-29). The separate upload bucket dates
from 2026-06-01; before 2025-12-04 an upload cost about 1600 units
([revision history](https://developers.google.com/youtube/v3/revision_history)).

## Failure modes

| Output | Cause | Fix |
|---|---|---|
| `no_client_secrets` | `YOUTUBE_CLIENT_SECRETS` unset or not a file | REFERENCE.md § One-time OAuth setup |
| `no_token` | `auth` never run, or the refresh token expired | Run `auth`. An OAuth app left in "Testing" status gets refresh tokens that expire after 7 days |
| `http_403: forbidden` on `thumbnails.set` | Custom thumbnails need a verified YouTube account | Verify the account in YouTube, then retry `thumbnail` |
| `http_403: quotaExceeded` | Daily quota spent | Wait for the reset at midnight Pacific Time |
| `http_400: uploadLimitExceeded` | The channel has hit its own upload limit | Wait; this is a channel limit, not API quota |
| `video_not_found` | Wrong id, or the token's channel does not own it | Run `whoami` |

API facts, field limits and the OAuth setup steps: [REFERENCE.md](REFERENCE.md).
