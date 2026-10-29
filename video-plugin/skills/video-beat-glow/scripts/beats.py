"""Beats of a song and a per-video-frame pulse envelope for an edge glow.

    beats.py <song> [--json beats.json]   prints the tempo, the beat count and the beat gaps

Onsets are the bass band's spectral flux (the kick drum, below most of the bass line's
harmonics). The tempo is the strongest autocorrelation lag between 90 and 180 BPM, and beats
are placed by dynamic programming (Ellis 2007): each beat sits on strong flux while the gaps
stay close to the tempo period. A beat's strength is the flux at it relative to the song's loud
beats, so the pulse is soft where the kick is soft and absent where it stops. --json writes
{"bpm", "beats": [[time s, strength], ...]}. Library use: beats(decode(path)) and envelope().
Ported from shoreline-recon's work/karaoke/beats.py.
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

SR, HOP, NFFT = 22050, 256, 2048
BASS = (35.0, 160.0)  # Hz
TEMPO = (90.0, 180.0)  # BPM search range
TIGHTNESS = 100.0  # how strongly beat gaps are held to the tempo period
DECAY = 0.22  # s for a pulse to fall to 1/e (default; callers may pass their own)
RISE = 0.03  # s of attack, so a pulse does not start on a hard cut


def decode(path):
    """Mono float32 samples at SR from any file ffmpeg reads (a song, or a video's audio)."""
    out = subprocess.run(
        [
            "ffmpeg",
            "-v",
            "error",
            "-i",
            str(path),
            "-map",
            "0:a:0",
            "-ac",
            "1",
            "-ar",
            str(SR),
            "-f",
            "f32le",
            "-",
        ],
        capture_output=True,
    )
    if out.returncode != 0:
        raise SystemExit(
            f"beats: ffmpeg could not decode audio from {path}: {out.stderr.decode().strip()}"
        )
    return np.frombuffer(out.stdout, np.float32)


def bass_flux(x):
    """Onset strength per hop: positive change in log bass-band magnitude."""
    win = np.hanning(NFFT).astype(np.float32)
    n = 1 + (len(x) - NFFT) // HOP
    frames = np.lib.stride_tricks.as_strided(
        x, (n, NFFT), (x.strides[0] * HOP, x.strides[0])
    )
    freqs = np.fft.rfftfreq(NFFT, 1 / SR)
    band = (freqs >= BASS[0]) & (freqs <= BASS[1])
    mag = np.abs(np.fft.rfft(frames * win, axis=1)[:, band])
    flux = np.maximum(np.diff(np.log1p(100 * mag), axis=0), 0).sum(axis=1)
    return np.concatenate([[0.0], flux])


def tempo_period(flux):
    """Beat period in hops, from the autocorrelation peak inside TEMPO (parabolic refinement)."""
    f = flux - flux.mean()
    ac = np.correlate(f, f, "full")[len(f) - 1 :]
    rate = SR / HOP
    lo, hi = int(rate * 60 / TEMPO[1]), int(rate * 60 / TEMPO[0]) + 1
    i = lo + int(np.argmax(ac[lo:hi]))
    a, b, c = ac[i - 1], ac[i], ac[i + 1]
    return i + 0.5 * (a - c) / (a - 2 * b + c)


def track(flux, period):
    """Beat positions in hops (Ellis 2007 dynamic programming)."""
    env = flux / (flux.std() + 1e-9)
    n = len(env)
    score, back = env.copy(), np.full(n, -1)
    lags = np.arange(int(period / 2), int(2 * period) + 1)
    penalty = -TIGHTNESS * np.log(lags / period) ** 2
    for t in range(lags[0], n):
        prev = t - lags
        ok = prev >= 0
        cand = score[prev[ok]] + penalty[ok]
        j = int(np.argmax(cand))
        if cand[j] > 0:
            score[t] += cand[j]
            back[t] = prev[ok][j]
    # End on the best-scoring beat in the last period, then walk back.
    t = n - int(period) + int(np.argmax(score[n - int(period) :]))
    beats = []
    while t >= 0:
        beats.append(t)
        t = back[t]
    return np.array(beats[::-1])


def beats(x):
    """(beat times in s, strengths 0..1, BPM)."""
    flux = bass_flux(x)
    period = tempo_period(flux)
    b = track(flux, period)
    w = max(1, int(0.05 * SR / HOP))
    peak = np.array([flux[max(0, i - w) : i + w + 1].max() for i in b])
    loud = np.percentile(peak, 90)
    strength = np.clip(peak / loud, 0, 1) ** 1.5
    return (b * HOP + NFFT / 2) / SR, strength, 60 * SR / HOP / period


def envelope(
    t_beats, strength, fps, n, start=0.0, decay=DECAY, every=1, phase=0, floor=0.0
):
    """Pulse intensity 0..1 per video frame: a short rise into each beat, then a decay.

    Only beats whose index is phase modulo every pulse (every=4 gives one per bar, phase picks
    which beat), and floor is a steady share of the peak held between pulses. Pass strength as
    ones to pulse every chosen beat at full height instead of following the kick.
    """
    t = start + np.arange(n) / fps
    out = np.zeros(n)
    for j, (tb, s) in enumerate(zip(t_beats, strength)):
        if (j - phase) % every:
            continue
        i0 = max(0, int((tb - RISE - start) * fps))
        i1 = min(n, int((tb + 5 * decay - start) * fps) + 1)
        if i1 <= i0:
            continue
        dt = t[i0:i1] - tb
        p = (
            np.where(
                dt < 0, np.clip(1 + dt / RISE, 0, 1), np.exp(-np.maximum(dt, 0) / decay)
            )
            * s
        )
        out[i0:i1] = np.maximum(out[i0:i1], p)
    return floor + (1 - floor) * out


def main(argv=None):
    ap = argparse.ArgumentParser(
        description="Tempo and beats of a song (bass-band onsets)."
    )
    ap.add_argument("song", type=Path)
    ap.add_argument(
        "--json", type=Path, help="write {bpm, beats: [[t, strength], ...]} here"
    )
    a = ap.parse_args(argv)
    tb, s, bpm = beats(decode(a.song))
    gaps = np.diff(tb)
    print(
        f"{bpm:.2f} BPM; {len(tb)} beats from {tb[0]:.2f} to {tb[-1]:.2f} s; "
        f"gap median {np.median(gaps):.3f} s, min {gaps.min():.3f}, max {gaps.max():.3f}; "
        f"weak (<0.2) {int((s < 0.2).sum())}"
    )
    if a.json:
        a.json.write_text(
            json.dumps(
                {
                    "bpm": round(float(bpm), 2),
                    "beats": [
                        [round(float(t), 3), round(float(v), 3)] for t, v in zip(tb, s)
                    ],
                }
            )
        )
        print(f"beats: wrote {a.json}", file=sys.stderr)


if __name__ == "__main__":
    main()
