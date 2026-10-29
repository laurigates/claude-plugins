#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "google-api-python-client>=2.100",
#   "google-auth-oauthlib>=1.2",
#   "google-auth-httplib2>=0.2",
# ]
# ///
"""Upload and edit YouTube videos through the YouTube Data API v3.

Subcommands: auth, whoami, categories, upload, update, thumbnail, status. Every write
subcommand takes --dry-run, which validates the input and prints the exact
request (endpoint, query parameters, JSON body, media file) without importing
the Google client libraries or touching the network.

Configuration (never committed):
  YOUTUBE_CLIENT_SECRETS  path to the Desktop OAuth client JSON from Google Cloud
  YOUTUBE_TOKEN_FILE      token cache; default ${XDG_CONFIG_HOME:-~/.config}/youtube-plugin/token.json

API facts this script relies on (developers.google.com/youtube/v3, checked 2026-10-29):
  - videos.update overwrites every mutable property of each part it names; an
    omitted property is deleted. selfDeclaredMadeForKids and
    containsSyntheticMedia are exempt. So `update` reads the current snippet and
    status first and resends the merged part.
  - snippet.title: max 100 characters, no < or >. snippet.description: max
    5000 bytes, no < or >. snippet.tags: max 500 characters, counted with commas
    between tags and quotes around a tag that contains a space.
  - status.privacyStatus accepts private, public, unlisted. There is no field
    for sharing a private video with people or a Workspace domain; that step is
    browser-only (see the youtube-studio-share skill).

Output: === SECTION === / KEY=VALUE / STATUS= / ISSUE_COUNT=, per the repo's
structured-script-output convention. Exit 0 on OK or WARN, 1 on ERROR.
"""

from __future__ import annotations

import argparse
import itertools
import json
import mimetypes
import os
import random
import re
import sys
import time
from pathlib import Path

SCOPES = [
    # videos.insert and thumbnails.set accept this scope.
    "https://www.googleapis.com/auth/youtube.upload",
    # videos.update requires youtube, youtube.force-ssl or youtubepartner;
    # youtube.upload alone cannot edit a video after upload.
    "https://www.googleapis.com/auth/youtube",
]

UPLOAD_ENDPOINT = "https://www.googleapis.com/upload/youtube/v3/videos"
THUMBNAIL_ENDPOINT = "https://www.googleapis.com/upload/youtube/v3/thumbnails/set"
VIDEOS_ENDPOINT = "https://www.googleapis.com/youtube/v3/videos"

PRIVACY_VALUES = ("private", "public", "unlisted")
SNIPPET_MUTABLE = ("title", "description", "tags", "categoryId", "defaultLanguage")
STATUS_MUTABLE = (
    "privacyStatus",
    "embeddable",
    "license",
    "publicStatsViewable",
    "publishAt",
)

TITLE_MAX_CHARS = 100
DESCRIPTION_MAX_BYTES = 5000
TAGS_MAX_CHARS = 500
THUMBNAIL_MAX_BYTES = 50 * 1024 * 1024
THUMBNAIL_MIMES = ("image/jpeg", "image/png")
CHAPTER_MIN = 3
CHAPTER_MIN_SECONDS = 10

# Quota units per call (developers.google.com/youtube/v3/determine_quota_cost,
# last updated 2026-10-15). videos.insert draws from its own "Video Uploads"
# bucket (default 100 calls/day); everything else from the 10,000-unit pool.
QUOTA = {
    "videos.insert": "1 unit, Video Uploads bucket (100/day)",
    "videos.list": "1 unit",
    "videos.update": "50 units",
    "thumbnails.set": "50 units",
    "channels.list": "1 unit",
    "videoCategories.list": "1 unit",
}

RETRIABLE_STATUS = (500, 502, 503, 504)
MAX_RETRIES = 8
CHUNK_BYTES = 8 * 1024 * 1024

CHAPTER_RE = re.compile(r"^\s*(?:(\d{1,2}):)?(\d{1,2}):(\d{2})\b")


class UsageError(Exception):
    """Invalid input; reported as STATUS=ERROR before any network call."""


# ---------------------------------------------------------------- validation


def validate_text(name: str, value: str) -> list[str]:
    if "<" in value or ">" in value:
        return [f"{name}_angle_brackets: YouTube rejects < and > in {name}"]
    return []


def validate_title(title: str) -> list[str]:
    issues = validate_text("title", title)
    if not title.strip():
        issues.append("title_empty: a title is required")
    if len(title) > TITLE_MAX_CHARS:
        issues.append(f"title_too_long: {len(title)} characters, max {TITLE_MAX_CHARS}")
    return issues


def validate_description(description: str) -> list[str]:
    issues = validate_text("description", description)
    size = len(description.encode("utf-8"))
    if size > DESCRIPTION_MAX_BYTES:
        issues.append(
            f"description_too_long: {size} bytes, max {DESCRIPTION_MAX_BYTES}"
        )
    return issues


def tags_length(tags: list[str]) -> int:
    """Length as YouTube counts it: commas between tags, quotes around spaced tags."""
    quoted = sum(len(t) + (2 if " " in t else 0) for t in tags)
    return quoted + max(len(tags) - 1, 0)


def validate_tags(tags: list[str]) -> list[str]:
    size = tags_length(tags)
    if size > TAGS_MAX_CHARS:
        return [
            f"tags_too_long: {size} characters by YouTube's count, max {TAGS_MAX_CHARS}"
        ]
    return []


def parse_chapters(description: str) -> list[tuple[int, str]]:
    """Timestamp lines in a description, as (seconds, line)."""
    chapters = []
    for line in description.splitlines():
        m = CHAPTER_RE.match(line)
        if m:
            h, mnt, s = (int(g) if g else 0 for g in m.groups())
            chapters.append((h * 3600 + mnt * 60 + s, line.strip()))
    return chapters


def check_chapters(description: str) -> list[str]:
    """YouTube's chapter rules: first at 0:00, at least 3, ascending, each >= 10 s.

    Warnings, not errors: a description without valid chapters still uploads,
    it just shows no chapter markers. Chapter lines are generated by
    video-plugin; this is the upload-time check of what is being sent.
    """
    chapters = parse_chapters(description)
    if not chapters:
        return []
    warnings = []
    if chapters[0][0] != 0:
        warnings.append(
            f"chapters_first_not_zero: first timestamp is {chapters[0][1]!r}"
        )
    if len(chapters) < CHAPTER_MIN:
        warnings.append(
            f"chapters_too_few: {len(chapters)} timestamps, need {CHAPTER_MIN}"
        )
    for (t0, l0), (t1, l1) in itertools.pairwise(chapters):
        if t1 <= t0:
            warnings.append(f"chapters_not_ascending: {l1!r} after {l0!r}")
        elif t1 - t0 < CHAPTER_MIN_SECONDS:
            warnings.append(
                f"chapter_too_short: {l0!r} lasts {t1 - t0} s, min {CHAPTER_MIN_SECONDS}"
            )
    return warnings


def validate_media(path: Path, kind: str) -> tuple[list[str], str]:
    if not path.is_file():
        return [f"{kind}_missing: {path} is not a file"], ""
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if kind == "thumbnail":
        issues = []
        if mime not in THUMBNAIL_MIMES:
            issues.append(
                f"thumbnail_type: {mime}, accepted {', '.join(THUMBNAIL_MIMES)}"
            )
        if path.stat().st_size > THUMBNAIL_MAX_BYTES:
            issues.append(
                f"thumbnail_too_large: {path.stat().st_size} bytes, max {THUMBNAIL_MAX_BYTES}"
            )
        return issues, mime
    if not (mime.startswith("video/") or mime == "application/octet-stream"):
        return [
            f"video_type: {mime}, accepted video/* or application/octet-stream"
        ], mime
    return [], mime


# ------------------------------------------------------------- request bodies


def yes_no(value: str | None) -> bool | None:
    return None if value is None else value == "yes"


def build_insert_body(args: argparse.Namespace, description: str) -> dict:
    snippet = {
        "title": args.title,
        "description": description,
        "categoryId": args.category,
    }
    if args.tag:
        snippet["tags"] = args.tag
    if args.language:
        snippet["defaultLanguage"] = args.language
    status = {
        "privacyStatus": args.privacy,
        "selfDeclaredMadeForKids": yes_no(args.made_for_kids),
        "containsSyntheticMedia": yes_no(args.synthetic_media),
    }
    return {"snippet": snippet, "status": status}


def pick(resource: dict, keys: tuple[str, ...]) -> dict:
    return {k: resource[k] for k in keys if k in resource}


def merge_update(current: dict, changes: dict) -> tuple[dict, list[str]]:
    """Build a videos.update body that changes only what `changes` names.

    `current` is a video resource from videos.list (part=snippet,status).
    Each part that `changes` touches is resent in full -- current mutable
    values overlaid with the changes -- because the API deletes any mutable
    property of a named part that the body omits. Read-only fields
    (publishedAt, thumbnails, uploadStatus, ...) are dropped. Returns the body
    and the list of parts to name in `part=`.
    """
    body: dict = {"id": current["id"]}
    parts = []
    for part, mutable in (("snippet", SNIPPET_MUTABLE), ("status", STATUS_MUTABLE)):
        delta = changes.get(part) or {}
        if not delta:
            continue
        merged = pick(current.get(part, {}), mutable)
        merged.update(delta)
        body[part] = merged
        parts.append(part)
    # The two exempt status fields change only when explicitly sent, so they
    # are added on top of whatever status was merged above.
    exempt = changes.get("status_exempt") or {}
    if exempt:
        body.setdefault(
            "status", pick(current.get("status", {}), STATUS_MUTABLE)
        ).update(exempt)
        if "status" not in parts:
            parts.append("status")
    # publishAt is only valid while the video is private.
    if body.get("status", {}).get("privacyStatus", "private") != "private":
        body["status"].pop("publishAt", None)
    return body, parts


def collect_update_changes(args: argparse.Namespace, description: str | None) -> dict:
    snippet = {}
    if args.title is not None:
        snippet["title"] = args.title
    if description is not None:
        snippet["description"] = description
    if args.tag:
        snippet["tags"] = args.tag
    if args.category is not None:
        snippet["categoryId"] = args.category
    status = {"privacyStatus": args.privacy} if args.privacy else {}
    exempt = {}
    if args.made_for_kids is not None:
        exempt["selfDeclaredMadeForKids"] = yes_no(args.made_for_kids)
    if args.synthetic_media is not None:
        exempt["containsSyntheticMedia"] = yes_no(args.synthetic_media)
    return {"snippet": snippet, "status": status, "status_exempt": exempt}


# -------------------------------------------------------------------- output


def emit(
    section: str,
    fields: list[tuple[str, object]],
    errors: list[str],
    warnings: list[str],
) -> int:
    print(f"=== {section} ===")
    for key, value in fields:
        if isinstance(value, (dict, list)):
            value = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        print(f"{key}={value}")
    findings = [("ERROR", e) for e in errors] + [("WARN", w) for w in warnings]
    status = "ERROR" if errors else "WARN" if warnings else "OK"
    print(f"STATUS={status}")
    if findings:
        first = findings[0][1]
        more = f" (+{len(findings) - 1} more)" if len(findings) > 1 else ""
        print(f"REASON={' '.join(first.split())[:180]}{more}")
        print("ISSUES:")
        for severity, msg in findings:
            kind, _, text = msg.partition(": ")
            print(f"  - SEVERITY={severity} TYPE={kind} MSG={text}")
    print(f"ISSUE_COUNT={len(findings)}")
    print(f"=== END {section} ===")
    return 1 if errors else 0


def read_description(args: argparse.Namespace) -> str | None:
    if args.description_file:
        if args.description_file == "-":
            return sys.stdin.read()
        return Path(args.description_file).read_text(encoding="utf-8")
    return args.description


# ---------------------------------------------------------------- API client


def token_path() -> Path:
    if os.environ.get("YOUTUBE_TOKEN_FILE"):
        return Path(os.environ["YOUTUBE_TOKEN_FILE"]).expanduser()
    base = Path(os.environ.get("XDG_CONFIG_HOME") or Path.home() / ".config")
    return base / "youtube-plugin" / "token.json"


def save_token(path: Path, creds) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.parent.chmod(0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(creds.to_json())


def credentials(interactive: bool):
    from google.auth.exceptions import RefreshError
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials
    from google_auth_oauthlib.flow import InstalledAppFlow

    path = token_path()
    creds = None
    if path.is_file():
        creds = Credentials.from_authorized_user_file(str(path), SCOPES)
        if not creds.has_scopes(SCOPES):
            creds = None
    if creds and creds.expired and creds.refresh_token:
        try:
            creds.refresh(Request())
            save_token(path, creds)
        except RefreshError:
            # An OAuth app in "Testing" publishing status gets refresh tokens
            # that expire after 7 days; that lands here.
            creds = None
    if creds and creds.valid:
        return creds
    if not interactive:
        raise UsageError(
            f"no_token: run `youtube_api.py auth` first (token file {path})"
        )
    secrets = os.environ.get("YOUTUBE_CLIENT_SECRETS")
    if not secrets or not Path(secrets).expanduser().is_file():
        raise UsageError(
            "no_client_secrets: set YOUTUBE_CLIENT_SECRETS to the Desktop OAuth client JSON path"
        )
    flow = InstalledAppFlow.from_client_secrets_file(
        str(Path(secrets).expanduser()), SCOPES
    )
    creds = flow.run_local_server(port=0)
    save_token(path, creds)
    return creds


def youtube_client(interactive: bool = False):
    from googleapiclient.discovery import build

    return build(
        "youtube", "v3", credentials=credentials(interactive), cache_discovery=False
    )


def http_error_reason(err) -> str:
    try:
        detail = json.loads(err.content.decode("utf-8"))["error"]
        reason = detail.get("errors", [{}])[0].get("reason", "")
        return f"http_{err.resp.status}: {reason} {detail.get('message', '')}".strip()
    except (ValueError, KeyError, AttributeError):
        return f"http_{getattr(err.resp, 'status', '?')}: {err}"


def resumable(request, label: str):
    """Drive a resumable upload to completion, retrying 5xx with backoff."""
    from googleapiclient.errors import HttpError

    response, retries = None, 0
    while response is None:
        try:
            progress, response = request.next_chunk()
            if progress:
                print(f"{label}: {int(progress.progress() * 100)}%", file=sys.stderr)
            retries = 0
        except HttpError as err:
            if err.resp.status not in RETRIABLE_STATUS or retries >= MAX_RETRIES:
                raise
            retries += 1
            delay = random.uniform(0, 2**retries)
            print(
                f"{label}: HTTP {err.resp.status}, retry {retries} in {delay:.1f} s",
                file=sys.stderr,
            )
            time.sleep(delay)
    return response


def media(path: Path, mime: str):
    from googleapiclient.http import MediaFileUpload

    return MediaFileUpload(
        str(path), mimetype=mime, chunksize=CHUNK_BYTES, resumable=True
    )


def channel_fields(yt) -> list[tuple[str, object]]:
    items = yt.channels().list(part="snippet", mine=True).execute().get("items", [])
    if not items:
        return [("CHANNEL_ID", ""), ("CHANNEL_TITLE", "")]
    ch = items[0]
    return [
        ("CHANNEL_ID", ch["id"]),
        ("CHANNEL_TITLE", ch["snippet"].get("title", "")),
        ("CHANNEL_HANDLE", ch["snippet"].get("customUrl", "")),
    ]


def fetch_video(yt, video_id: str, parts: str = "snippet,status") -> dict:
    items = yt.videos().list(part=parts, id=video_id).execute().get("items", [])
    if not items:
        raise UsageError(
            f"video_not_found: {video_id} (wrong id, or not owned by the authorized channel)"
        )
    return items[0]


# --------------------------------------------------------------- subcommands


def cmd_auth(args) -> int:
    yt = youtube_client(interactive=True)
    return emit(
        "YOUTUBE AUTH", [("TOKEN_FILE", token_path()), *channel_fields(yt)], [], []
    )


def cmd_whoami(args) -> int:
    return emit("YOUTUBE WHOAMI", channel_fields(youtube_client()), [], [])


def cmd_upload(args) -> int:
    description = read_description(args) or ""
    video = Path(args.file).expanduser()
    errors = (
        validate_title(args.title)
        + validate_description(description)
        + validate_tags(args.tag or [])
    )
    media_issues, mime = validate_media(video, "video")
    errors += media_issues
    thumb, thumb_mime = None, ""
    if args.thumbnail:
        thumb = Path(args.thumbnail).expanduser()
        thumb_issues, thumb_mime = validate_media(thumb, "thumbnail")
        errors += thumb_issues
    warnings = check_chapters(description)
    body = build_insert_body(args, description)
    notify = "false" if args.no_notify_subscribers else "true"
    plan = [
        ("OPERATION", "upload"),
        (
            "REQUEST",
            f"POST {UPLOAD_ENDPOINT}?uploadType=resumable&part=snippet,status&notifySubscribers={notify}",
        ),
        ("MEDIA_FILE", video),
        ("MEDIA_BYTES", video.stat().st_size if video.is_file() else 0),
        ("MEDIA_MIME", mime),
        ("REQUEST_BODY", body),
        ("CHAPTER_COUNT", len(parse_chapters(description))),
    ]
    if thumb:
        plan += [
            ("THUMBNAIL_REQUEST", f"POST {THUMBNAIL_ENDPOINT}?videoId=<new id>"),
            ("THUMBNAIL_FILE", thumb),
            ("THUMBNAIL_MIME", thumb_mime),
        ]
    plan.append(
        (
            "QUOTA",
            f"videos.insert {QUOTA['videos.insert']}"
            + (f"; thumbnails.set {QUOTA['thumbnails.set']}" if thumb else ""),
        )
    )
    if args.dry_run or errors:
        return emit(
            "YOUTUBE DRY RUN" if args.dry_run else "YOUTUBE UPLOAD",
            plan,
            errors,
            warnings,
        )

    yt = youtube_client()
    request = yt.videos().insert(
        part="snippet,status",
        body=body,
        media_body=media(video, mime),
        notifySubscribers=not args.no_notify_subscribers,
    )
    result = resumable(request, "upload")
    video_id = result["id"]
    fields = [
        ("OPERATION", "upload"),
        ("VIDEO_ID", video_id),
        ("WATCH_URL", f"https://youtu.be/{video_id}"),
        ("STUDIO_EDIT_URL", f"https://studio.youtube.com/video/{video_id}/edit"),
        ("PRIVACY", result.get("status", {}).get("privacyStatus", "")),
        ("UPLOAD_STATUS", result.get("status", {}).get("uploadStatus", "")),
    ]
    if thumb:
        from googleapiclient.errors import HttpError

        # The video is already uploaded: report a thumbnail failure as a
        # warning so VIDEO_ID is not lost behind an error exit.
        try:
            yt.thumbnails().set(
                videoId=video_id, media_body=media(thumb, thumb_mime)
            ).execute()
            fields.append(("THUMBNAIL", "set"))
        except HttpError as err:
            warnings.append(f"thumbnail_failed: {http_error_reason(err)}")
    return emit("YOUTUBE UPLOAD", fields, [], warnings)


def cmd_update(args) -> int:
    description = read_description(args)
    errors = []
    if args.title is not None:
        errors += validate_title(args.title)
    if description is not None:
        errors += validate_description(description)
    errors += validate_tags(args.tag or [])
    warnings = check_chapters(description) if description is not None else []
    changes = collect_update_changes(args, description)
    if not any(changes.values()):
        errors.append(
            "nothing_to_update: pass at least one of --title, --description[-file], --tag, --category, --privacy, --made-for-kids, --synthetic-media"
        )
    if errors:
        return emit(
            "YOUTUBE UPDATE",
            [("OPERATION", "update"), ("VIDEO_ID", args.video_id)],
            errors,
            warnings,
        )

    if args.dry_run:
        if args.current_json:
            current = json.loads(Path(args.current_json).read_text(encoding="utf-8"))
            source = args.current_json
        else:
            current = {"id": args.video_id}
            source = "none (real run reads it with videos.list; untouched mutable fields are resent unchanged)"
        body, parts = merge_update(current, changes)
        return emit(
            "YOUTUBE DRY RUN",
            [
                ("OPERATION", "update"),
                (
                    "READ_REQUEST",
                    f"GET {VIDEOS_ENDPOINT}?part=snippet,status&id={args.video_id}",
                ),
                ("CURRENT_SOURCE", source),
                ("REQUEST", f"PUT {VIDEOS_ENDPOINT}?part={','.join(parts)}"),
                ("REQUEST_BODY", body),
                (
                    "QUOTA",
                    f"videos.list {QUOTA['videos.list']}; videos.update {QUOTA['videos.update']}",
                ),
            ],
            [],
            warnings,
        )

    yt = youtube_client()
    current = fetch_video(yt, args.video_id)
    body, parts = merge_update(current, changes)
    if "snippet" in parts and not body["snippet"].get("categoryId"):
        return emit(
            "YOUTUBE UPDATE",
            [("VIDEO_ID", args.video_id)],
            ["no_category: snippet updates need categoryId; pass --category"],
            warnings,
        )
    result = yt.videos().update(part=",".join(parts), body=body).execute()
    return emit(
        "YOUTUBE UPDATE",
        [
            ("OPERATION", "update"),
            ("VIDEO_ID", args.video_id),
            ("PARTS", ",".join(parts)),
            ("TITLE", result.get("snippet", {}).get("title", "")),
            ("PRIVACY", result.get("status", {}).get("privacyStatus", "")),
        ],
        [],
        warnings,
    )


def cmd_thumbnail(args) -> int:
    image = Path(args.image).expanduser()
    errors, mime = validate_media(image, "thumbnail")
    plan = [
        ("OPERATION", "thumbnail"),
        ("REQUEST", f"POST {THUMBNAIL_ENDPOINT}?videoId={args.video_id}"),
        ("THUMBNAIL_FILE", image),
        ("THUMBNAIL_MIME", mime),
        ("QUOTA", f"thumbnails.set {QUOTA['thumbnails.set']}"),
    ]
    if args.dry_run or errors:
        return emit(
            "YOUTUBE DRY RUN" if args.dry_run else "YOUTUBE THUMBNAIL", plan, errors, []
        )
    yt = youtube_client()
    yt.thumbnails().set(videoId=args.video_id, media_body=media(image, mime)).execute()
    return emit(
        "YOUTUBE THUMBNAIL",
        [("OPERATION", "thumbnail"), ("VIDEO_ID", args.video_id), ("THUMBNAIL", "set")],
        [],
        [],
    )


def cmd_categories(args) -> int:
    resp = (
        youtube_client()
        .videoCategories()
        .list(part="snippet", regionCode=args.region)
        .execute()
    )
    rows = [
        f"{c['id']}:{c['snippet']['title']}"
        for c in resp.get("items", [])
        if c["snippet"].get("assignable")
    ]
    return emit(
        "YOUTUBE CATEGORIES",
        [("REGION", args.region), ("ASSIGNABLE", ", ".join(rows))],
        [],
        [],
    )


def cmd_status(args) -> int:
    v = fetch_video(youtube_client(), args.video_id, "snippet,status,processingDetails")
    snippet, status, proc = (
        v.get("snippet", {}),
        v.get("status", {}),
        v.get("processingDetails", {}),
    )
    description = snippet.get("description", "")
    return emit(
        "YOUTUBE STATUS",
        [
            ("VIDEO_ID", v["id"]),
            ("TITLE", snippet.get("title", "")),
            ("CATEGORY_ID", snippet.get("categoryId", "")),
            ("DESCRIPTION_BYTES", len(description.encode("utf-8"))),
            ("CHAPTER_COUNT", len(parse_chapters(description))),
            ("PRIVACY", status.get("privacyStatus", "")),
            ("UPLOAD_STATUS", status.get("uploadStatus", "")),
            ("PROCESSING_STATUS", proc.get("processingStatus", "")),
            ("MADE_FOR_KIDS", status.get("madeForKids", "")),
            ("CONTAINS_SYNTHETIC_MEDIA", status.get("containsSyntheticMedia", "")),
        ],
        [],
        check_chapters(description),
    )


# -------------------------------------------------------------------- parser


def add_metadata_args(p: argparse.ArgumentParser, upload: bool) -> None:
    p.add_argument("--title", required=upload, help="max 100 characters, no < or >")
    group = p.add_mutually_exclusive_group()
    group.add_argument(
        "--description", help="description text (chapter lines included)"
    )
    group.add_argument(
        "--description-file", help="read the description from a file, or - for stdin"
    )
    p.add_argument(
        "--tag", action="append", help="one tag; repeat for more (500 characters total)"
    )
    p.add_argument(
        "--category",
        default="22" if upload else None,
        help="snippet.categoryId (upload default 22; the `categories` subcommand lists valid ids)",
    )
    p.add_argument(
        "--privacy",
        choices=PRIVACY_VALUES,
        default="private" if upload else None,
        help="private (upload default), unlisted or public; org-only sharing is a Studio step",
    )
    p.add_argument(
        "--made-for-kids",
        choices=("yes", "no"),
        required=upload,
        help="status.selfDeclaredMadeForKids; required on upload",
    )
    p.add_argument(
        "--synthetic-media",
        choices=("yes", "no"),
        required=upload,
        help="status.containsSyntheticMedia: realistic altered or synthetic (A/S) content disclosure; "
        "the uploader's call, required on upload",
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="validate and print the request; no network, no client libraries",
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="youtube_api.py",
        description=__doc__.split("\n\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser(
        "auth", help="one-time OAuth consent in the browser; caches the token"
    ).set_defaults(func=cmd_auth)
    sub.add_parser(
        "whoami", help="channel the cached token belongs to (channels.list, 1 unit)"
    ).set_defaults(func=cmd_whoami)

    up = sub.add_parser(
        "upload", help="resumable videos.insert, then thumbnails.set if --thumbnail"
    )
    up.add_argument("file", help="video file")
    add_metadata_args(up, upload=True)
    up.add_argument("--language", help="snippet.defaultLanguage, e.g. fi or en")
    up.add_argument("--thumbnail", help="JPEG or PNG to set after upload")
    up.add_argument(
        "--no-notify-subscribers", action="store_true", help="notifySubscribers=false"
    )
    up.set_defaults(func=cmd_upload)

    upd = sub.add_parser(
        "update", help="change title/description/tags/category/privacy after upload"
    )
    upd.add_argument("video_id")
    add_metadata_args(upd, upload=False)
    upd.add_argument(
        "--current-json",
        help="dry-run only: a videos.list item to merge against instead of fetching",
    )
    upd.set_defaults(func=cmd_update)

    th = sub.add_parser("thumbnail", help="thumbnails.set on an existing video")
    th.add_argument("video_id")
    th.add_argument("image")
    th.add_argument("--dry-run", action="store_true")
    th.set_defaults(func=cmd_thumbnail)

    cat = sub.add_parser(
        "categories",
        help="assignable categoryId values for a region (videoCategories.list, 1 unit)",
    )
    cat.add_argument(
        "--region", default="FI", help="ISO 3166-1 alpha-2 region code (default FI)"
    )
    cat.set_defaults(func=cmd_categories)

    st = sub.add_parser(
        "status", help="read back title, privacy, upload and processing status"
    )
    st.add_argument("video_id")
    st.set_defaults(func=cmd_status)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return args.func(args)
    except UsageError as err:
        return emit(f"YOUTUBE {args.command.upper()}", [], [str(err)], [])
    except Exception as err:
        if type(err).__name__ == "HttpError":
            return emit(
                f"YOUTUBE {args.command.upper()}", [], [http_error_reason(err)], []
            )
        raise


if __name__ == "__main__":
    sys.exit(main())
