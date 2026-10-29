# youtube-studio-share reference

## Why this is a browser step

The [videos resource](https://developers.google.com/youtube/v3/docs/videos)
(checked 2026-10-29) defines `status.privacyStatus` as one of `private`,
`public` or `unlisted`. Neither `videos.update` nor any other method shares a
private video with named users or a Workspace domain. YouTube Help documents the
Studio route: Content, the video, Visibility, Share privately
([Change video privacy settings](https://support.google.com/youtube/answer/157177)).
The org-wide checkbox appears only on Workspace channels and is not in that
help page; it was observed in a live session.

## Observed flow (live session, 2026-10)

| Step | English | Finnish |
|---|---|---|
| Visibility option | Private | Yksityinen |
| Button under Private | Share privately | Jaa yksityisesti |
| Dialog title | Share video privately | Jaa video yksityisenä |
| Org checkbox | Give view access to all `<domain>` users | Anna katseluoikeus kaikille `<domain>`-käyttäjille |
| Keep unchecked | Notify via email | Ilmoita sähköpostilla |
| Close dialog | Done | Valmis |
| Card before save | Shared privately with everyone at `<domain>` (save to share) | Jaettu yksityisesti kaikille osoitteessa `<domain>` (tallenna jakaaksesi) |
| Commit | Save | Tallenna |
| Processing | Pending | Odottaa |
| HD badge tooltip | HD video ready | Teräväpiirtovideo valmis |
| Hidden template, not an error | Oops, something went wrong | Hups, jotain meni pieleen |

The "Visibility" label itself (`Näkyvyys` in Finnish) was not recorded; it is
inferred and marked `observed: false` in `env.js`.

## DOM facts

Observed:

- Studio is built from Polymer `ytcp-*` custom elements.
- Title and description editors are `#textbox[contenteditable="true"]`, title
  first.
- Replacing text worked by selecting a Range over the target text node and then
  typing, verified by reading `innerText` back.
- Every page carries hidden `ytcp-error-section` templates; only a visible one
  is an error.

Candidates that `ytStudioProbe()` checks, not yet seen live:

| Key in `SEL` | Selector | Fallback |
|---|---|---|
| `visibility` | `ytcp-video-metadata-visibility` | the Visibility label's parent |
| `privateRadio` | `tp-yt-paper-radio-button[name="PRIVATE"]` | `[role="radio"]` labelled Private |
| `saveButton` | `ytcp-button#save` | `[role="button"]` labelled Save |
| `dialog` | `tp-yt-paper-dialog, ytcp-dialog, [role="dialog"]` | whole document |

Checkbox state is read from `aria-checked`. `press()` tries `.click()` first and
replays a pointer sequence only when the expected state change did not happen,
so a toggle is never flipped twice.

## Account identification

`whoami()` reads `window.ytcfg.data_` keys matching channel, session, account and
locale names, and drops any key that looks like a credential (`TOKEN`, `KEY`,
`XSRF`, `SAPISID`, `COOKIE`, `SECRET`). Which keys Studio populates was not
verified; the fixture test only pins the filtering.
