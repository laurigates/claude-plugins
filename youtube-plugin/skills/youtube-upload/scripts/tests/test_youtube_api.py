"""Unit tests for youtube_api.py's pure logic and dry-run output.

Stdlib only: the script imports the Google client libraries lazily, inside the
functions that touch the network, so validation, request building and
--dry-run run under a bare python3. Run through test-youtube-api.sh.
"""

from __future__ import annotations

import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from typing import ClassVar

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import youtube_api as yt


def run(argv: list[str]) -> tuple[int, dict, str]:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        code = yt.main(argv)
    text = out.getvalue()
    fields = dict(
        line.split("=", 1)
        for line in text.splitlines()
        if "=" in line and not line.startswith(("=", " "))
    )
    return code, fields, text


class Validation(unittest.TestCase):
    def test_title_limits(self):
        self.assertEqual(yt.validate_title("x" * 100), [])
        self.assertTrue(yt.validate_title("x" * 101)[0].startswith("title_too_long"))
        self.assertTrue(
            yt.validate_title("a <b>")[0].startswith("title_angle_brackets")
        )
        self.assertTrue(
            any(i.startswith("title_empty") for i in yt.validate_title("  "))
        )

    def test_description_counts_bytes_not_characters(self):
        # 2500 two-byte characters = 5000 bytes: at the limit. One more is over.
        self.assertEqual(yt.validate_description("ä" * 2500), [])
        self.assertTrue(
            yt.validate_description("ä" * 2501)[0].startswith("description_too_long")
        )

    def test_tags_length_matches_youtube_rule(self):
        # Docs example: Foo-Baz is 7 characters, Foo Baz is 9 (quotes count).
        self.assertEqual(yt.tags_length(["Foo-Baz"]), 7)
        self.assertEqual(yt.tags_length(["Foo Baz"]), 9)
        # Commas between items count.
        self.assertEqual(yt.tags_length(["ab", "cd"]), 5)
        self.assertEqual(yt.tags_length([]), 0)
        self.assertTrue(yt.validate_tags(["x" * 501])[0].startswith("tags_too_long"))


class Chapters(unittest.TestCase):
    def test_valid_chapters_have_no_warnings(self):
        self.assertEqual(
            yt.check_chapters("Intro text\n0:00 Start\n0:10 Two\n1:02:03 Three\n"), []
        )

    def test_parse_hours(self):
        self.assertEqual(yt.parse_chapters("1:02:03 Outro")[0][0], 3723)

    def test_no_timestamps_is_not_a_warning(self):
        self.assertEqual(yt.check_chapters("just a description"), [])

    def test_rule_violations(self):
        def kinds(description):
            return [w.split(":")[0] for w in yt.check_chapters(description)]

        self.assertIn("chapters_first_not_zero", kinds("0:05 a\n0:20 b\n0:40 c"))
        self.assertIn("chapters_too_few", kinds("0:00 a\n0:20 b"))
        self.assertIn("chapter_too_short", kinds("0:00 a\n0:09 b\n0:40 c"))
        self.assertIn("chapters_not_ascending", kinds("0:00 a\n0:40 b\n0:20 c"))


class MergeUpdate(unittest.TestCase):
    CURRENT: ClassVar[dict] = {
        "id": "abc123",
        "snippet": {
            "title": "Old title",
            "description": "0:00 a\n0:20 b\n0:40 c",
            "tags": ["t1"],
            "categoryId": "10",
            "publishedAt": "2026-10-01T00:00:00Z",
            "channelId": "UCx",
            "thumbnails": {},
            "localized": {},
        },
        "status": {
            "privacyStatus": "private",
            "embeddable": True,
            "license": "youtube",
            "publicStatsViewable": True,
            "uploadStatus": "processed",
            "madeForKids": False,
        },
    }

    def test_title_change_keeps_other_mutable_snippet_fields(self):
        # The API deletes omitted mutable properties of a named part; the merge
        # must resend description, tags and categoryId unchanged.
        body, parts = yt.merge_update(self.CURRENT, {"snippet": {"title": "New"}})
        self.assertEqual(parts, ["snippet"])
        self.assertEqual(
            body["snippet"],
            {
                "title": "New",
                "description": "0:00 a\n0:20 b\n0:40 c",
                "tags": ["t1"],
                "categoryId": "10",
            },
        )
        self.assertNotIn("status", body)

    def test_read_only_fields_are_dropped(self):
        body, _ = yt.merge_update(
            self.CURRENT,
            {"snippet": {"title": "New"}, "status": {"privacyStatus": "unlisted"}},
        )
        for key in ("publishedAt", "channelId", "thumbnails", "localized"):
            self.assertNotIn(key, body["snippet"])
        self.assertNotIn("uploadStatus", body["status"])
        self.assertEqual(body["status"]["license"], "youtube")

    def test_exempt_status_fields_alone_still_send_full_status(self):
        body, parts = yt.merge_update(
            self.CURRENT, {"status_exempt": {"containsSyntheticMedia": True}}
        )
        self.assertEqual(parts, ["status"])
        self.assertEqual(body["status"]["privacyStatus"], "private")
        self.assertTrue(body["status"]["containsSyntheticMedia"])

    def test_publish_at_dropped_when_not_private(self):
        current = json.loads(json.dumps(self.CURRENT))
        current["status"]["publishAt"] = "2026-11-01T00:00:00Z"
        body, _ = yt.merge_update(current, {"status": {"privacyStatus": "public"}})
        self.assertNotIn("publishAt", body["status"])


class DryRun(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.video = self.dir / "clip.mp4"
        self.video.write_bytes(b"\0" * 1024)
        self.thumb = self.dir / "thumb.jpg"
        self.thumb.write_bytes(b"\xff\xd8" + b"\0" * 100)

    def tearDown(self):
        self.tmp.cleanup()

    def test_upload_body_carries_required_status_fields(self):
        code, f, _ = run(
            [
                "upload",
                str(self.video),
                "--title",
                "Song",
                "--description",
                "0:00 a\n0:20 b\n0:40 c",
                "--made-for-kids",
                "no",
                "--synthetic-media",
                "yes",
                "--thumbnail",
                str(self.thumb),
                "--dry-run",
            ]
        )
        self.assertEqual(code, 0)
        self.assertEqual(f["STATUS"], "OK")
        body = json.loads(f["REQUEST_BODY"])
        self.assertEqual(
            body["status"],
            {
                "privacyStatus": "private",
                "selfDeclaredMadeForKids": False,
                "containsSyntheticMedia": True,
            },
        )
        self.assertEqual(body["snippet"]["categoryId"], "22")
        self.assertIn("uploadType=resumable", f["REQUEST"])
        self.assertEqual(f["THUMBNAIL_MIME"], "image/jpeg")
        self.assertEqual(f["CHAPTER_COUNT"], "3")

    def test_upload_requires_explicit_disclosures(self):
        # argparse exits 2 when a required flag is missing.
        with (
            self.assertRaises(SystemExit) as ctx,
            contextlib.redirect_stderr(io.StringIO()),
        ):
            yt.main(
                [
                    "upload",
                    str(self.video),
                    "--title",
                    "Song",
                    "--made-for-kids",
                    "no",
                    "--dry-run",
                ]
            )
        self.assertEqual(ctx.exception.code, 2)

    def test_invalid_input_is_an_error_before_network(self):
        code, f, _ = run(
            [
                "upload",
                str(self.dir / "missing.mp4"),
                "--title",
                "x" * 101,
                "--made-for-kids",
                "no",
                "--synthetic-media",
                "no",
            ]
        )
        self.assertEqual(code, 1)
        self.assertEqual(f["STATUS"], "ERROR")
        self.assertEqual(f["ISSUE_COUNT"], "2")
        self.assertTrue(f["REASON"].startswith("title_too_long"))

    def test_chapter_problem_is_a_warning(self):
        code, f, _ = run(
            [
                "upload",
                str(self.video),
                "--title",
                "Song",
                "--description",
                "0:05 a",
                "--made-for-kids",
                "no",
                "--synthetic-media",
                "no",
                "--dry-run",
            ]
        )
        self.assertEqual(code, 0)
        self.assertEqual(f["STATUS"], "WARN")

    def test_update_dry_run_merges_against_current_json(self):
        current = self.dir / "current.json"
        current.write_text(json.dumps(MergeUpdate.CURRENT))
        code, f, _ = run(
            [
                "update",
                "abc123",
                "--title",
                "Renamed",
                "--current-json",
                str(current),
                "--dry-run",
            ]
        )
        self.assertEqual(code, 0)
        self.assertEqual(f["REQUEST"], f"PUT {yt.VIDEOS_ENDPOINT}?part=snippet")
        body = json.loads(f["REQUEST_BODY"])
        self.assertEqual(body["snippet"]["title"], "Renamed")
        self.assertEqual(body["snippet"]["tags"], ["t1"])

    def test_update_with_nothing_is_an_error(self):
        code, f, _ = run(["update", "abc123", "--dry-run"])
        self.assertEqual(code, 1)
        self.assertTrue(f["REASON"].startswith("nothing_to_update"))

    def test_thumbnail_rejects_wrong_type(self):
        gif = self.dir / "t.gif"
        gif.write_bytes(b"GIF89a")
        code, f, _ = run(["thumbnail", "abc123", str(gif), "--dry-run"])
        self.assertEqual(code, 1)
        self.assertTrue(f["REASON"].startswith("thumbnail_type"))

    def test_dry_run_never_imports_google_libraries(self):
        run(
            [
                "upload",
                str(self.video),
                "--title",
                "Song",
                "--made-for-kids",
                "no",
                "--synthetic-media",
                "no",
                "--dry-run",
            ]
        )
        self.assertFalse(
            any(
                m.startswith(("googleapiclient", "google_auth_oauthlib"))
                for m in sys.modules
            )
        )


class Scopes(unittest.TestCase):
    def test_update_capable_scope_present(self):
        # videos.update does not accept youtube.upload; without one of these the
        # update path fails with 403 after a successful upload.
        self.assertTrue(
            {
                "https://www.googleapis.com/auth/youtube",
                "https://www.googleapis.com/auth/youtube.force-ssl",
                "https://www.googleapis.com/auth/youtubepartner",
            }
            & set(yt.SCOPES)
        )


if __name__ == "__main__":
    unittest.main()
