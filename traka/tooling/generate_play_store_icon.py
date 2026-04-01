#!/usr/bin/env python3
"""Build 512x512 Play Store listing icon with rounded corners (white safe background)."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw

DEFAULT_RADIUS_RATIO = 0.18
DEFAULT_PAD_RATIO = 0.14


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument(
        "--input",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "assets/images/traka_brand_logo.png",
    )
    p.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parents[1]
        / "assets/images/traka_play_store_icon_512_rounded.png",
    )
    p.add_argument("--size", type=int, default=512)
    p.add_argument("--radius-ratio", type=float, default=DEFAULT_RADIUS_RATIO)
    p.add_argument("--pad-ratio", type=float, default=DEFAULT_PAD_RATIO)
    args = p.parse_args()

    size = args.size
    radius = max(1, int(round(size * args.radius_ratio)))
    pad = max(0, int(round(size * args.pad_ratio)))

    src = Image.open(args.input).convert("RGBA")
    sw, sh = src.size
    inner = size - 2 * pad
    scale = min(inner / sw, inner / sh)
    nw, nh = max(1, int(round(sw * scale))), max(1, int(round(sh * scale)))
    src = src.resize((nw, nh), Image.Resampling.LANCZOS)

    canvas = Image.new("RGBA", (size, size), (255, 255, 255, 255))
    x, y = (size - nw) // 2, (size - nh) // 2
    canvas.paste(src, (x, y), src)

    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size - 1, size - 1), radius=radius, fill=255)

    rounded = Image.new("RGBA", (size, size), (255, 255, 255, 0))
    rounded.paste(canvas, (0, 0), mask)

    out_rgb = Image.new("RGB", (size, size), (255, 255, 255))
    out_rgb.paste(rounded, mask=rounded.getchannel("A"))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    out_rgb.save(args.output, format="PNG", optimize=True)
    print(f"Wrote {args.output} ({size}x{size}, radius={radius}px)")


if __name__ == "__main__":
    main()
