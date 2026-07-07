#!/usr/bin/env python3
"""Composite crisp branding onto a banner background -> final 21:9 banner.png.

Layout: icon squircle at left, DisplayName wordmark + tagline to its right,
over a slightly darkened background for legibility. Text is drawn with magick
(sharp, correctly spelled) — never bake the pack name into the diffusion prompt.

  ComfyUI/.venv/bin/python tooling/scripts/registry_banner_compose.py \
    --bg bg.png --icon icon.png --name "Touch Resize" \
    --tagline "Pinch-to-resize nodes on touch" --accent '#ffb02e' --out banner.png

Inputs: --bg from registry_banner_bg.py, --icon the cairosvg-rendered 400x400
icon (see comfy-registry-icons-banners.md — rasterize with cairosvg, NOT magick).

See also: tooling/.claude/rules/comfy-registry-icons-banners.md
"""
import argparse, subprocess, sys

BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
REG = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--bg", required=True, help="background PNG (registry_banner_bg.py)")
    ap.add_argument("--icon", required=True, help="400x400 icon PNG (cairosvg-rendered)")
    ap.add_argument("--name", required=True, help="DisplayName wordmark, e.g. 'Touch Resize'")
    ap.add_argument("--tagline", required=True, help="one-line tagline")
    ap.add_argument("--accent", default="#6ba6ff", help="tagline colour hex (family accent)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--bold-font", default=BOLD)
    ap.add_argument("--reg-font", default=REG)
    a = ap.parse_args()

    cmd = [
        "magick", a.bg, "-brightness-contrast", "-12x4",
        "(", a.icon, "-resize", "300x300", ")",
        "-gravity", "NorthWest", "-geometry", "+72+138", "-composite",
        "-gravity", "NorthWest",
        # wordmark: soft shadow then light fill
        "-font", a.bold_font, "-pointsize", "94",
        "-fill", "rgba(0,0,0,0.55)", "-annotate", "+437+205", a.name,
        "-fill", "#e8e8ea", "-annotate", "+434+202", a.name,
        # tagline in the family accent colour
        "-font", a.reg_font, "-pointsize", "37", "-fill", a.accent, "-annotate", "+438+320", a.tagline,
        a.out,
    ]
    r = subprocess.run(cmd)
    if r.returncode != 0:
        sys.exit(f"magick failed ({r.returncode})")
    print(f"-> {a.out}")


if __name__ == "__main__":
    main()
