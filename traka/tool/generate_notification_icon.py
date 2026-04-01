#!/usr/bin/env python3
"""Generate Android notification small icons (white + alpha, padded) from a source PNG."""
from __future__ import annotations

import sys
from pathlib import Path

try:
    from PIL import Image
except ImportError:
    print("Install Pillow: pip install pillow", file=sys.stderr)
    sys.exit(1)

# dp -> px (notification small icon standards)
DENSITIES = {
    "drawable-mdpi": 24,
    "drawable-hdpi": 36,
    "drawable-xhdpi": 48,
    "drawable-xxhdpi": 72,
    "drawable-xxxhdpi": 96,
}


def silhouette_white_rgba(img: Image.Image) -> Image.Image:
    """Non-transparent pixels -> white, preserve alpha."""
    rgba = img.convert("RGBA")
    px = rgba.load()
    w, h = rgba.size
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a > 0:
                px[x, y] = (255, 255, 255, a)
    return rgba


def render_icon(src: Image.Image, size_px: int, safe_frac: float = 0.58) -> Image.Image:
    """Center logo in square; scale so max extent <= safe_frac * size (avoid circular crop)."""
    src = silhouette_white_rgba(src)
    tw = th = int(size_px * safe_frac)
    scale = min(tw / src.width, th / src.height, 1.0)
    nw = max(1, int(src.width * scale))
    nh = max(1, int(src.height * scale))
    resized = src.resize((nw, nh), Image.Resampling.LANCZOS)
    canvas = Image.new("RGBA", (size_px, size_px), (0, 0, 0, 0))
    ox = (size_px - nw) // 2
    oy = (size_px - nh) // 2
    canvas.paste(resized, (ox, oy), resized)
    return canvas


def main() -> None:
    repo = Path(__file__).resolve().parents[1]
    res = repo / "android" / "app" / "src" / "main" / "res"
    src_path = Path(sys.argv[1]) if len(sys.argv) > 1 else None
    if src_path is None or not src_path.is_file():
        print("Usage: generate_notification_icon.py <source.png>", file=sys.stderr)
        sys.exit(1)
    im = Image.open(src_path)
    old_xml = res / "drawable" / "ic_notification.xml"
    if old_xml.is_file():
        old_xml.unlink()
    for folder, px in DENSITIES.items():
        d = res / folder
        d.mkdir(parents=True, exist_ok=True)
        out = render_icon(im, px)
        out_path = d / "ic_notification.png"
        out.save(out_path, format="PNG", optimize=True)
        print(out_path, px)
    print("Done.")


if __name__ == "__main__":
    main()
