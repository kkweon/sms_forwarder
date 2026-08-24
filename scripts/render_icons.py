#!/usr/bin/env python3
"""Render the Android launcher PNGs from the master logo SVG.

The adaptive icon (API 26+) is a vector drawable and needs no rendering; these
PNGs are the legacy fallback for older launchers.

Usage:  pip install cairosvg && python3 scripts/render_icons.py
"""

import pathlib
import re
import sys

import cairosvg

ROOT = pathlib.Path(__file__).resolve().parent.parent
MASTER = ROOT / "assets/logo/sms_forwarder_logo.svg"
RES = ROOT / "android/app/src/main/res"

# dpi bucket -> launcher icon size in px
DENSITIES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}

# Scale of the mark on the 1024 canvas. The square icon is full-bleed so it can
# run a little larger than the round one, which has to stay inside the circle.
SQUARE_SCALE = 0.86
ROUND_SCALE = 0.82


def mark() -> str:
    """The <g class="mark"> block from the master SVG — the single source of geometry."""
    svg = MASTER.read_text()
    m = re.search(r'<g class="mark".*?</g>', svg, re.S)
    if not m:
        sys.exit(f'no <g class="mark"> found in {MASTER}')
    return m.group(0)


def compose(background: str, scale: float) -> str:
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" '
        'viewBox="0 0 1024 1024">'
        f"{background}"
        f'<g transform="translate(512 512) scale({scale}) translate(-512 -512)">'
        f"{mark()}</g></svg>"
    )


def main() -> None:
    variants = {
        "ic_launcher": compose('<rect width="1024" height="1024" fill="#FFFFFF"/>', SQUARE_SCALE),
        "ic_launcher_round": compose('<circle cx="512" cy="512" r="512" fill="#FFFFFF"/>', ROUND_SCALE),
    }
    for name, svg in variants.items():
        for bucket, size in DENSITIES.items():
            out = RES / f"mipmap-{bucket}" / f"{name}.png"
            out.parent.mkdir(parents=True, exist_ok=True)
            cairosvg.svg2png(
                bytestring=svg.encode(),
                write_to=str(out),
                output_width=size,
                output_height=size,
            )
            print(f"{out.relative_to(ROOT)}  {size}x{size}")


if __name__ == "__main__":
    main()
