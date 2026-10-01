"""Generates the Color Gravity launcher icons + splash art (original artwork).

Run: python tool/gen_icons.py   (requires Pillow)
"""
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), '..', 'android', 'app', 'src', 'main', 'res')
BG_TOP = (29, 35, 80)
BG_BOTTOM = (8, 11, 24)
STOPS = [(255, 77, 94), (180, 92, 255), (61, 139, 255)]


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def gradient_stops(t):
    if t < 0.5:
        return lerp(STOPS[0], STOPS[1], t / 0.5)
    return lerp(STOPS[1], STOPS[2], (t - 0.5) / 0.5)


def background(size, rounded=True, circle=False):
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    grad = Image.new('RGBA', (size, size))
    d = ImageDraw.Draw(grad)
    for y in range(size):
        c = lerp(BG_TOP, BG_BOTTOM, y / size)
        d.line([(0, y), (size, y)], fill=c + (255,))
    mask = Image.new('L', (size, size), 0)
    md = ImageDraw.Draw(mask)
    if circle:
        md.ellipse([0, 0, size - 1, size - 1], fill=255)
    elif rounded:
        md.rounded_rectangle([0, 0, size - 1, size - 1], radius=int(size * 0.22), fill=255)
    else:
        md.rectangle([0, 0, size, size], fill=255)
    img.paste(grad, (0, 0), mask)
    return img


def orb_layer(size, scale=1.0):
    """Gradient orb with white rim, glow, landing line and gravity chevron."""
    layer = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    cx, cy = size / 2, size / 2 - size * 0.04 * scale
    r = size * 0.24 * scale
    # glow
    glow = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([cx - r * 1.5, cy - r * 1.5, cx + r * 1.5, cy + r * 1.5], fill=(139, 107, 255, 110))
    glow = glow.filter(ImageFilter.GaussianBlur(size * 0.06))
    layer = Image.alpha_composite(layer, glow)
    # orb gradient (diagonal), computed per pixel so the disc is fully filled
    yy, xx = np.mgrid[0:size, 0:size]
    t = (((xx - (cx - r)) + (yy - (cy - r))) / (4 * r)).clip(0, 1)
    rgb = np.zeros((size, size, 3), dtype=np.float64)
    a, b, c = (np.array(x, dtype=np.float64) for x in STOPS)
    lo = t < 0.5
    k = np.where(lo, t / 0.5, (t - 0.5) / 0.5)[..., None]
    rgb = np.where(lo[..., None], a + (b - a) * k, b + (c - b) * k)
    inside = ((xx - cx) ** 2 + (yy - cy) ** 2) <= r * r
    alpha = np.where(inside, 255, 0)
    orb = Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), 'RGBA')
    layer = Image.alpha_composite(layer, orb)
    hi = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(hi).ellipse([cx - r * 0.55, cy - r * 0.62, cx - r * 0.15, cy - r * 0.25], fill=(255, 255, 255, 80))
    layer = Image.alpha_composite(layer, hi.filter(ImageFilter.GaussianBlur(size * 0.004)))
    d = ImageDraw.Draw(layer)
    rim = max(2, int(r * 0.13))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=(255, 255, 255, 255), width=rim)
    # gravity chevron under the orb
    ch_y = cy + r * 1.38
    w = r * 0.42
    d.line([(cx - w, ch_y - w * 0.45), (cx, ch_y + w * 0.35), (cx + w, ch_y - w * 0.45)], fill=(255, 255, 255, 230),
           width=max(2, int(r * 0.12)), joint='curve')
    # landing line
    ly = cy + r * 1.85
    d.rounded_rectangle([cx - r * 0.9, ly, cx + r * 0.9, ly + max(2, r * 0.08)], radius=int(r * 0.04) + 1,
                        fill=(255, 255, 255, 120))
    return layer


def save(img, path, size):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.resize((size, size), Image.LANCZOS).save(path)


def main():
    master = 1024
    legacy = Image.alpha_composite(background(master), orb_layer(master))
    rnd = Image.alpha_composite(background(master, circle=True), orb_layer(master, 0.92))
    fg = orb_layer(master, 0.62)  # adaptive foreground: keep inside 66% safe zone
    dens = {'mdpi': 1, 'hdpi': 1.5, 'xhdpi': 2, 'xxhdpi': 3, 'xxxhdpi': 4}
    for name, k in dens.items():
        save(legacy, f'{ROOT}/mipmap-{name}/ic_launcher.png', int(48 * k))
        save(rnd, f'{ROOT}/mipmap-{name}/ic_launcher_round.png', int(48 * k))
        save(fg, f'{ROOT}/mipmap-{name}/ic_launcher_foreground.png', int(108 * k))
        save(orb_layer(master, 0.62), f'{ROOT}/drawable-{name}/splash_icon.png', int(288 * k / 1.5))
    # Play Store icon (512) next to the project for convenience.
    store = os.path.join(os.path.dirname(__file__), '..', 'store')
    os.makedirs(store, exist_ok=True)
    legacy_sq = Image.alpha_composite(background(master, rounded=False), orb_layer(master))
    legacy_sq.resize((512, 512), Image.LANCZOS).save(os.path.join(store, 'play_store_icon_512.png'))
    print('icons written')


if __name__ == '__main__':
    main()
