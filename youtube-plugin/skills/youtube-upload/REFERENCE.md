# youtube-upload reference

Facts in this file were read from developers.google.com/youtube/v3 and Google's
OAuth documentation on 2026-10-29. Each line names its page.

## One-time OAuth setup

Done once per machine by the channel owner. Nothing produced here goes into a
repository.

1. **Google Cloud project.** Create one (or reuse one) in the
   [Google Cloud console](https://console.cloud.google.com/). For a Workspace
   channel, create it under the organization that owns the channel.
2. **Enable the API.** APIs & Services, Library, "YouTube Data API v3", Enable.
3. **OAuth consent screen.** Configure it with the user type the organization
   allows (Internal keeps it to the Workspace domain). An External app left in
   "Testing" publishing status issues refresh tokens that expire after 7 days
   ([OAuth 2.0 overview](https://developers.google.com/identity/protocols/oauth2)), so `auth` would have to be re-run weekly.
4. **Scopes.** Add both to the consent screen:

   | Scope | Why |
   |---|---|
   | `https://www.googleapis.com/auth/youtube.upload` | `videos.insert`, `thumbnails.set` |
   | `https://www.googleapis.com/auth/youtube` | `videos.update` (which does not accept `youtube.upload`), `videos.list`, `channels.list`, `videoCategories.list` |

   Scope lists per method: [videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert),
   [videos.update](https://developers.google.com/youtube/v3/docs/videos/update),
   [thumbnails.set](https://developers.google.com/youtube/v3/docs/thumbnails/set).
5. **OAuth client.** Clients, Create client, application type **Desktop app**.
   Download the JSON. A Desktop client opens the system browser and receives the
   code on a loopback redirect
   ([OAuth for installed apps](https://developers.google.com/youtube/v3/guides/auth/installed-apps)).
6. **Point the script at it.** Store the JSON outside any repository with mode
   0600, and export its path, for example from `~/.api_tokens`:
   ```
   export YOUTUBE_CLIENT_SECRETS="$HOME/.config/youtube-plugin/client_secret.json"
   ```
7. **Consent.** Sign in to the browser as the account that owns the target
   channel, then run `uv run <skill>/scripts/youtube_api.py auth`. It prints the
   channel the token belongs to. The token lands in
   `${XDG_CONFIG_HOME:-~/.config}/youtube-plugin/token.json`, or at
   `YOUTUBE_TOKEN_FILE` when that is set.

To switch channel, delete the token file and run `auth` again as the other
account.

## Field rules ([videos resource](https://developers.google.com/youtube/v3/docs/videos))

| Field | Rule |
|---|---|
| `snippet.title` | Max 100 characters, no `<` or `>`. Required on `videos.update` of `snippet` |
| `snippet.description` | Max 5000 **bytes**, no `<` or `>` |
| `snippet.tags[]` | Max 500 characters: commas between tags count, and a tag containing a space counts two extra for the quotes |
| `snippet.categoryId` | Required on `videos.update` of `snippet`; valid ids come from `videoCategories.list` (`categories` subcommand) |
| `status.privacyStatus` | `private`, `public` or `unlisted`. Omitted on insert, it defaults to `public` (some accounts default to `private`) |
| `status.selfDeclaredMadeForKids` | The channel owner's child-directed designation |
| `status.containsSyntheticMedia` | The channel owner's disclosure of realistic altered or synthetic content. Added 2024-10-30 ([revision history](https://developers.google.com/youtube/v3/revision_history)) |
| `status.publishAt` | Only while `private` and never published |

`videos.update` overwrites every mutable property of each part named in
`part=`; a property the body omits is deleted. `selfDeclaredMadeForKids` and
`containsSyntheticMedia` are exempt and change only when sent. The script's
`merge_update()` implements this and is covered by
`scripts/tests/test_youtube_api.py`.

No field or method shares a private video with named users or a Workspace
domain. That step is in YouTube Studio only; see the `youtube-studio-share`
skill.

## Upload mechanics

- Endpoint `POST https://www.googleapis.com/upload/youtube/v3/videos`, max
  256 GB, media type `video/*` or `application/octet-stream`
  ([videos.insert](https://developers.google.com/youtube/v3/docs/videos/insert)).
- The script uploads in 8 MB resumable chunks through
  `googleapiclient.http.MediaFileUpload(resumable=True)` and retries HTTP 500,
  502, 503 and 504 with randomized exponential backoff, the same set Google's
  [upload guide](https://developers.google.com/youtube/v3/guides/uploading_a_video)
  retries.
- `notifySubscribers` defaults to true; `--no-notify-subscribers` turns it off.
- Thumbnails: `image/jpeg` or `image/png`, max 50 MB via the API
  ([thumbnails.set](https://developers.google.com/youtube/v3/docs/thumbnails/set)).
  Custom thumbnails need a verified YouTube account
  ([YouTube Help](https://support.google.com/youtube/answer/72431)); without it
  `thumbnails.set` returns 403 `forbidden`.

## Chapters

YouTube builds chapters from description timestamps when the first is `00:00`,
there are at least three in ascending order, and each chapter is at least
10 seconds ([YouTube Help](https://support.google.com/youtube/answer/9884579)).
`video-plugin` generates the lines; this script only checks them before sending.

## Browser uploads are not an alternative

The Chrome extension's file-upload tool accepts only files under 10 MB that are
shared with the session, so a real video goes through this API (or the user
picks the file in Studio's dialog). A ~100 KB thumbnail JPEG fits through the
browser.
