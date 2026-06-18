#!/usr/bin/env python3
"""Composite a Sports Manager family app icon from shared chrome-render
sources (shield + glyph + background) into a single accent colour.

Requires Pillow + numpy (not committed as deps anywhere — install into a
throwaway venv: `python3 -m venv /tmp/brand_venv && source
/tmp/brand_venv/bin/activate && pip install Pillow numpy`).

Two recolor strategies, pick per-glyph:
- colorize_metal: full luminance-preserving tint (shadow/mid/highlight ramp).
  Use for glyphs with no fixed colour identity (shield, person+check,
  dartboard, ticket).
- selective_recolor: only re-hues already-saturated pixels (the neon glow
  rim), leaves near-grayscale pixels alone. Use for glyphs whose source
  object has an inherent two-tone identity that must survive recoloring
  (the pool 8-ball's black/white, the football's black/white panels).

Usage example (see __main__ below) — edit SOURCES/APPS and rerun per app.
"""
import colorsys
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

SOURCES = Path(__file__).parent / "sources"
OUT = Path(__file__).parent / "composited"

CANVAS_SIZE = 1024
SHIELD_SIZE = 820
GLYPH_SIZE = 440
SHIELD_DY = 20
GLYPH_DY = 10
BG_DARKEN = 0.55


def load(name: str) -> Image.Image:
    return Image.open(SOURCES / name).convert("RGB")


def colorize_metal(img: Image.Image, size, shadow_hex, mid_hex, highlight_hex) -> Image.Image:
    img = img.resize(size, Image.LANCZOS)
    gray = img.convert("L")
    colorized = ImageOps.colorize(gray, black=shadow_hex, white=highlight_hex, mid=mid_hex)
    l_arr = np.asarray(gray).astype(np.float32) / 255.0
    alpha = np.clip(l_arr * 1.15, 0, 1)
    rgba = np.dstack([np.asarray(colorized), (alpha * 255).astype(np.uint8)])
    return Image.fromarray(rgba.astype(np.uint8), "RGBA")


def selective_recolor(img: Image.Image, size, target_hue_deg, sat_threshold=0.22) -> Image.Image:
    img = img.resize(size, Image.LANCZOS)
    arr = np.asarray(img).astype(np.float32) / 255.0
    maxc = np.max(arr, axis=2)
    minc = np.min(arr, axis=2)
    sat = np.where(maxc > 0, (maxc - minc) / np.maximum(maxc, 1e-6), 0)
    val = maxc
    target_hue = target_hue_deg / 360.0
    out = arr.copy()
    mask = sat > sat_threshold
    for y, x in zip(*np.where(mask)):
        out[y, x] = colorsys.hsv_to_rgb(target_hue, sat[y, x], val[y, x])
    rgb = (out * 255).astype(np.uint8)
    alpha = np.clip(val * 1.15, 0, 1)
    rgba = np.dstack([rgb, (alpha * 255).astype(np.uint8)])
    return Image.fromarray(rgba, "RGBA")


def compose(glyph_colored: Image.Image, shield_shadow, shield_mid, shield_highlight, out_name: str):
    shield = load("shield_chrome.png")
    bg = load("background_floodlights.png")
    shield_colored = colorize_metal(shield, (SHIELD_SIZE, SHIELD_SIZE), shield_shadow, shield_mid, shield_highlight)
    bg_square = ImageOps.fit(bg, (CANVAS_SIZE, CANVAS_SIZE), Image.LANCZOS)
    bg_square = Image.eval(bg_square, lambda p: int(p * BG_DARKEN))
    canvas = bg_square.convert("RGB")
    shield_pos = ((CANVAS_SIZE - SHIELD_SIZE) // 2, (CANVAS_SIZE - SHIELD_SIZE) // 2 + SHIELD_DY)
    gw, gh = glyph_colored.size
    glyph_pos = ((CANVAS_SIZE - gw) // 2, (CANVAS_SIZE - gh) // 2 + GLYPH_DY)
    canvas.paste(shield_colored, shield_pos, shield_colored)
    canvas.paste(glyph_colored, glyph_pos, glyph_colored)
    OUT.mkdir(exist_ok=True)
    canvas.save(OUT / out_name)
    print("saved", OUT / out_name)


# Locked palette — see ../pricing-model.md siblings / style-guide.md for the full table.
PALETTE = {
    "lms": dict(shadow="#3a1505", mid="#F97316", highlight="#FFE3C2"),
    "darts": dict(shadow="#2a0a3d", mid="#A855F7", highlight="#F3E1FF"),
    "pool": dict(shadow="#06141a", mid="#22D3EE", highlight="#E3FBFF"),
    "football": dict(shadow="#04230f", mid="#22C55E", highlight="#E3FFEC"),
    "sweepstake": dict(shadow="#3d2e05", mid="#EAB308", highlight="#FFF3C2"),
}

# hue in degrees, for apps using selective_recolor (glyph has its own
# black/white identity to preserve — only the neon rim gets re-hued)
SELECTIVE_HUE_DEG = {
    "pool": 188,
    "football": 142,
}


if __name__ == "__main__":
    for app, glyph_file in [
        ("lms", "glyph_lms_chrome.png"),
        ("darts", "glyph_darts_chrome.png"),
        ("sweepstake", "glyph_sweepstake_chrome.png"),
    ]:
        pal = PALETTE[app]
        glyph = colorize_metal(load(glyph_file), (GLYPH_SIZE, GLYPH_SIZE), pal["shadow"], pal["mid"], pal["highlight"])
        compose(glyph, pal["shadow"], pal["mid"], pal["highlight"], f"{app}_appicon.png")

    for app, glyph_file in [
        ("pool", "glyph_pool_chrome.png"),
        ("football", "glyph_football_chrome.png"),
    ]:
        pal = PALETTE[app]
        glyph = selective_recolor(load(glyph_file), (GLYPH_SIZE, GLYPH_SIZE), SELECTIVE_HUE_DEG[app])
        compose(glyph, pal["shadow"], pal["mid"], pal["highlight"], f"{app}_appicon.png")
