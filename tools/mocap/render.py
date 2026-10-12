"""Stick-figure rendering for mocap review (PIL, orthographic, no matplotlib needed).

render_frames(segments_fn, frames, out_png, views=("side","threequarter"), ...)
segments_fn(frame_index) -> list of (p0, p1, color) in a Y-up world with the fighter facing +Z (library space:
+X right, +Y up, +Z toward the opponent). The "side" view looks from the fighter's left (opponent on the right of
the image, like the game's P1 view); "threequarter" looks from the front-left.
"""
from __future__ import annotations

import math

import numpy as np
from PIL import Image, ImageDraw

LEFT = (90, 170, 255)
RIGHT = (255, 120, 90)
CENTER = (235, 235, 235)


def view_matrix(view: str) -> np.ndarray:
    """Returns a 2x3 projection (image right, image up) for a Y-up library-space world."""
    if view == "side":
        # Camera on the fighter's LEFT (-X), looking toward +X: image right = +Z (toward the opponent).
        right = np.array([0.0, 0.0, 1.0])
    elif view == "front":
        right = np.array([1.0, 0.0, 0.0])
        right = -right
    elif view == "threequarter":
        a = math.radians(40)
        right = np.array([math.sin(a), 0.0, math.cos(a)])
    elif view == "top":
        return np.array([[0.0, 0.0, 1.0], [-1.0, 0.0, 0.0]])
    else:
        raise ValueError(view)
    up = np.array([0.0, 1.0, 0.0])
    return np.stack([right, up])


def draw_panel(segments, view: str, size: int, scale: float, center: np.ndarray, label: str = "",
               floor_y: float = 0.0, extra_points=None) -> Image.Image:
    img = Image.new("RGB", (size, size), (24, 26, 32))
    d = ImageDraw.Draw(img)
    P = view_matrix(view)

    def proj(p):
        q = P @ (np.asarray(p) - center)
        return (size / 2 + q[0] * scale, size * 0.62 - q[1] * scale)

    if view != "top":
        fy = proj(np.array([center[0], floor_y, center[2]]))[1]
        d.line([(0, fy), (size, fy)], fill=(70, 75, 85), width=1)
        for k in range(-6, 7):
            x0 = proj(center + np.array([0, floor_y - center[1], 0]) + P[0] * k * 0.5)[0]
            d.line([(x0, fy), (x0, fy + 4)], fill=(70, 75, 85))
    for p0, p1, col in segments:
        a, b = proj(p0), proj(p1)
        d.line([a, b], fill=col, width=3)
        d.ellipse([b[0] - 2, b[1] - 2, b[0] + 2, b[1] + 2], fill=col)
    if extra_points:
        for p, col in extra_points:
            a = proj(p)
            d.ellipse([a[0] - 4, a[1] - 4, a[0] + 4, a[1] + 4], outline=col, width=2)
    if label:
        d.text((4, 4), label, fill=(255, 230, 120))
    return img


def sheet(rows: list[list[Image.Image]], out: str, title: str = "") -> None:
    h = max(len(r) for r in rows)
    w = rows[0][0].width
    hh = rows[0][0].height
    top = 18 if title else 0
    img = Image.new("RGB", (w * h, hh * len(rows) + top), (10, 10, 12))
    d = ImageDraw.Draw(img)
    if title:
        d.text((4, 3), title, fill=(255, 255, 255))
    for r, row in enumerate(rows):
        for c, panel in enumerate(row):
            img.paste(panel, (c * w, top + r * hh))
    img.save(out)
