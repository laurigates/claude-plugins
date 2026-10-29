import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from chapters_youtube import stamp, youtube_chapters  # noqa: E402

# The shoreline-recon v1 demo's chapters (234 s): a 3.5 s title, then per side six 7.5 s
# processing steps and four longer result views.
SIDE = ["frames", "masks", "sparse", "dense", "raw mesh", "raw splat"]
VIEWS = [
    ("splat · arc", 15.5),
    ("splat · drone", 19.5),
    ("mesh · arc", 15.5),
    ("mesh · drone", 19.5),
]


def demo_chapters():
    chapters, t = [(0.0, "Title")], 3.5
    for side in ("Laajasalo side", "Vartiosaari side"):
        for step in SIDE:
            chapters.append((t, f"{side} · {step}"))
            t += 7.5
        for view, length in VIEWS:
            chapters.append((t, f"{side} · {view}"))
            t += length
    return chapters, t + 0.5  # the last view runs 20 s in the real file


class DemoVideo(unittest.TestCase):
    def test_short_steps_merge_into_one_line_per_side(self):
        chapters, duration = demo_chapters()
        lines, _ = youtube_chapters(chapters, duration, label="processing steps")
        self.assertEqual(lines[0], (0, "Laajasalo side · processing steps"))
        self.assertEqual(lines[1], (48, "Laajasalo side · splat · arc"))
        self.assertEqual(lines[5], (118, "Vartiosaari side · processing steps"))
        self.assertEqual(len(lines), 10)

    def test_without_label_the_run_is_named_first_to_last(self):
        chapters, duration = demo_chapters()
        lines, _ = youtube_chapters(chapters, duration)
        self.assertEqual(lines[0][1], "Laajasalo side · frames–raw splat")

    def test_every_line_is_at_least_min_long(self):
        chapters, duration = demo_chapters()
        lines, _ = youtube_chapters(chapters, duration)
        ends = [s for s, _ in lines[1:]] + [int(duration)]
        self.assertTrue(all(e - s >= 10 for (s, _), e in zip(lines, ends)))


class Rules(unittest.TestCase):
    def test_first_line_is_moved_to_zero(self):
        lines, _ = youtube_chapters([(2.0, "a"), (20, "b"), (40, "c")], 60)
        self.assertEqual(lines[0], (0, "a"))

    def test_timestamps_floor_to_whole_seconds(self):
        lines, _ = youtube_chapters([(0, "a"), (12.9, "b"), (30.99, "c")], 60)
        self.assertEqual([s for s, _ in lines], [0, 12, 30])

    def test_lone_short_chapter_folds_into_previous_line(self):
        lines, merges = youtube_chapters(
            [(0, "a"), (20, "b"), (25, "c"), (40, "d")], 60
        )
        self.assertEqual(lines, [(0, "a"), (25, "c"), (40, "d")])
        self.assertIn("folded into previous line", merges[-1][3])

    def test_short_opening_chapter_folds_into_next_line(self):
        lines, _ = youtube_chapters(
            [(0, "Title"), (4, "intro"), (30, "b"), (50, "c")], 70
        )
        self.assertEqual(lines[0], (0, "intro"))

    def test_short_run_under_min_folds_whole(self):
        lines, _ = youtube_chapters(
            [(0, "a"), (20, "x · 1"), (24, "x · 2"), (28, "b"), (50, "c")], 70
        )
        self.assertEqual(lines, [(0, "a"), (28, "b"), (50, "c")])

    def test_short_final_chapter_folds_into_previous_line(self):
        lines, _ = youtube_chapters([(0, "a"), (20, "b"), (40, "c"), (55, "end")], 60)
        self.assertEqual(lines, [(0, "a"), (20, "b"), (40, "c")])

    def test_run_without_shared_group_uses_titles(self):
        lines, _ = youtube_chapters([(0, "one"), (5, "two"), (12, "b"), (40, "c")], 60)
        self.assertEqual(lines[0], (0, "one–two"))

    def test_run_with_mixed_groups_uses_label_alone(self):
        lines, _ = youtube_chapters(
            [(0, "x · 1"), (5, "y · 2"), (12, "b"), (40, "c")], 60, label="intro"
        )
        self.assertEqual(lines[0], (0, "intro"))

    def test_no_chapters(self):
        self.assertEqual(youtube_chapters([], 60), ([], []))


class Stamp(unittest.TestCase):
    def test_minutes(self):
        self.assertEqual(stamp(0), "0:00")
        self.assertEqual(stamp(118), "1:58")
        self.assertEqual(stamp(3725), "62:05")

    def test_hours(self):
        self.assertEqual(stamp(3725, hours=True), "1:02:05")
        self.assertEqual(stamp(48, hours=True), "0:00:48")


if __name__ == "__main__":
    unittest.main()
