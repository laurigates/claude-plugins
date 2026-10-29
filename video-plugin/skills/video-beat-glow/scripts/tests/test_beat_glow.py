import json
import math
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import numpy as np

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import beat_glow  # noqa: E402
import beats  # noqa: E402


class Envelope(unittest.TestCase):
    def test_peak_on_the_beat_is_its_strength(self):
        env = beats.envelope([1.0], [0.8], fps=100, n=200, decay=0.2)
        self.assertAlmostEqual(env[100], 0.8)

    def test_decays_to_1_over_e_after_decay_seconds(self):
        env = beats.envelope([1.0], [0.8], fps=100, n=200, decay=0.2)
        self.assertAlmostEqual(env[120], 0.8 / math.e, places=6)

    def test_rises_over_30_ms_before_the_beat(self):
        env = beats.envelope([1.0], [1.0], fps=1000, n=1100, decay=0.2)
        self.assertAlmostEqual(env[985], 0.5, places=6)
        self.assertEqual(env[960], 0.0)

    def test_every_and_phase_pick_the_pulsing_beats(self):
        env = beats.envelope(
            np.arange(10.0), np.ones(10), fps=10, n=100, decay=0.05, every=2, phase=1
        )
        peaks = [round(i / 10) for i in range(100) if env[i] > 0.99]
        self.assertEqual(peaks, [1, 3, 5, 7, 9])

    def test_floor_holds_between_pulses(self):
        env = beats.envelope([5.0], [1.0], fps=10, n=30, floor=0.12)
        self.assertTrue(np.allclose(env, 0.12))

    def test_start_offsets_the_frame_times(self):
        env = beats.envelope([3.0], [1.0], fps=10, n=20, start=2.0, decay=0.2)
        self.assertAlmostEqual(env[10], 1.0)


class Bands(unittest.TestCase):
    """Computing only the edge bands must give exactly the full-frame result."""

    def full(self, pic, width, p, rgb):
        mask = beat_glow.edge_mask(*pic.shape[:2], width)[:, :, None]
        c = np.asarray(rgb, np.float32) / 255
        return (255 - (255 - pic.astype(np.float32)) * (1 - mask * (p * c))).astype(
            np.uint8
        )

    def test_bands_equal_full_frame(self):
        rng = np.random.default_rng(7)
        for h, w, width, intensity in [
            (180, 320, 10.3, 0.54),
            (720, 1280, 20.7, 1.0),
            (60, 90, 31, 0.54),
        ]:
            pic = rng.integers(0, 256, (h, w, 3), dtype=np.uint8)
            mask = beat_glow.edge_mask(h, w, width)
            t = beat_glow.band_px(width, intensity)
            regions = [
                (sy, sx, mask[sy, sx][:, :, None])
                for sy, sx in beat_glow.bands(h, w, t)
            ]
            for p in (intensity, intensity * 0.5, 0.02):
                for rgb in ((20, 184, 166), (255, 255, 255)):
                    got = pic.copy()
                    beat_glow.glow(got, regions, p, rgb)
                    np.testing.assert_array_equal(
                        got,
                        self.full(pic, width, p, rgb),
                        err_msg=f"{h}x{w} w={width} p={p}",
                    )

    def test_bands_cover_without_overlap(self):
        h, w, t = 50, 80, 12
        count = np.zeros((h, w), int)
        for sy, sx in beat_glow.bands(h, w, t):
            count[sy, sx] += 1
        d = np.minimum(
            np.minimum(np.arange(h), h - 1 - np.arange(h))[:, None],
            np.minimum(np.arange(w), w - 1 - np.arange(w))[None, :],
        )
        np.testing.assert_array_equal(count, (d < t).astype(int))


class Accent(unittest.TestCase):
    def test_first_matching_rule_on_the_label(self):
        rules = [
            beat_glow.accent_rule("splat=#14b8a6"),
            beat_glow.accent_rule("mesh=245,158,11"),
        ]
        default = beat_glow.colour("#6366f1")
        self.assertEqual(
            beat_glow.accent("Laajasalo side · splat · arc", rules, default, " · "),
            (20, 184, 166),
        )
        self.assertEqual(
            beat_glow.accent("Laajasalo side · mesh · drone", rules, default, " · "),
            (245, 158, 11),
        )
        self.assertEqual(
            beat_glow.accent("Laajasalo side · frames", rules, default, " · "),
            (99, 102, 241),
        )
        # The group (before the separator) is not matched: only the label is.
        self.assertEqual(
            beat_glow.accent("splat side · frames", rules, default, " · "),
            (99, 102, 241),
        )


@unittest.skipUnless(shutil.which("node"), "node not found")
class TunerAgreesWithEnvelope(unittest.TestCase):
    """The tuner page's pulseAt (extracted from the shipped template) against beats.envelope."""

    def test_js_pulse_matches_python_envelope(self):
        template = (SCRIPTS / "glow-tuner.template.html").read_text()
        js = template.split("// BEGIN pulseAt", 1)[1].split("// END pulseAt", 1)[0]
        js = js.split("\n", 1)[1]  # drop the rest of the BEGIN comment line
        rng = np.random.default_rng(3)
        tb = np.cumsum(rng.uniform(0.35, 0.6, 120))
        strength = rng.uniform(0, 1, 120)
        fps, n = 30.0, int(tb[-1] * 30) + 30
        settings = {"decay": 0.46, "every": 2, "phase": 2, "kick": True, "floor": 0.12}
        beats_js = [[float(t), float(s)] for t, s in zip(tb, strength)]
        with tempfile.TemporaryDirectory() as d:
            script = Path(d) / "pulse.cjs"
            script.write_text(
                js
                + f"\nconst B = {json.dumps(beats_js)}, S = {json.dumps(settings)};\n"
                f"console.log(JSON.stringify(Array.from({{length: {n}}}, (_, i) => pulseAt(i / {fps}, B, S))));"
            )
            out = subprocess.run(
                ["node", str(script)], capture_output=True, text=True, check=True
            ).stdout
        js_env = np.array(json.loads(out))
        py_env = beats.envelope(
            tb, strength, fps, n, decay=0.46, every=2, phase=2, floor=0.12
        )
        # The two cut a pulse's tail at slightly different points (5 decays), so they differ by at
        # most exp(-5) of a pulse there and agree elsewhere.
        self.assertLess(np.abs(js_env - py_env).max(), math.exp(-5) + 1e-9)


if __name__ == "__main__":
    unittest.main()
