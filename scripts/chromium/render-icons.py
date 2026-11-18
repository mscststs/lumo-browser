#!/usr/bin/env python3
"""Render the Lumo launcher icons from branding/*.svg into a Chromium res dir.

    scripts/chromium/render-icons.py --res ~/chromium/src/chrome/android/java/res_chromium_base
    scripts/chromium/render-icons.py --out /tmp/icons --preview /tmp/icons/preview

Why a renderer instead of one flat PNG: Android launcher icons are not a single
image. The launcher masks an *adaptive* icon built from two layers, and the
framework draws each layer 1.5x larger than the visible view port
(AdaptiveIconDrawable#getExtraInsetFraction() == 0.25 per side). So only the
central 72 x 72 of a 108 x 108 layer is ever seen. Both SVGs are authored on
that 108 grid, and this script enforces the safe zone instead of letting a
resize silently crop the logo.

Outputs (per density: mdpi 48 / hdpi 72 / xhdpi 96 / xxhdpi 144 / xxxhdpi 192):

    mipmap-<d>/app_icon.png                  legacy icon, squircle baked in
                                              (pre-API-26 launchers draw it as-is)
    mipmap-<d>/layered_app_icon.png          adaptive foreground (48dp * 1.5)
    mipmap-<d>/layered_app_icon_background.png  adaptive background (108dp)
    drawable/themed_app_icon.xml             monochrome layer (Android 13+)

Dependencies: python3-cairo + python3-gi with librsvg (Rsvg 2.0); ImageMagick is
used for Lanczos downscaling when available.
"""
from __future__ import annotations

import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile

import cairo

HERE = os.path.dirname(os.path.abspath(__file__))
BRAND_DIR = os.path.join(HERE, "branding")
BG_SVG = os.path.join(BRAND_DIR, "app-icon-background.svg")
FG_SVG = os.path.join(BRAND_DIR, "app-icon-foreground.svg")
MONO_XML = os.path.join(BRAND_DIR, "themed-app-icon.xml")

# (resource dir suffix, legacy icon px)
DENSITIES = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]

CANVAS = 108.0        # adaptive icon layer, grid units
VIEWPORT = 72.0       # visible part of the layer, grid units
LEGACY_SCALE = 1.5    # layer px per legacy icon px
MASTER = 2160         # 20 px per grid unit, downscaled from here
SQUIRCLE_N = 4.5      # superellipse exponent for the baked legacy shape


def die(msg: str) -> "NoReturn":  # type: ignore[name-defined]
    sys.stderr.write("[icons] %s\n" % msg)
    raise SystemExit(1)


def load_rsvg():
    try:
        import gi

        gi.require_version("Rsvg", "2.0")
        from gi.repository import Rsvg
    except Exception as exc:  # pragma: no cover - environment dependent
        die("librsvg python bindings missing (apt install python3-gi gir1.2-rsvg-2.0): %s" % exc)
    return Rsvg


# --- rendering -------------------------------------------------------------

def render_svg(surface: cairo.ImageSurface, svg_path: str, size: int, Rsvg) -> None:
    try:
        handle = Rsvg.Handle.new_from_file(svg_path)
    except Exception as exc:
        die("cannot parse %s: %s" % (svg_path, exc))
    if handle is None:
        die("cannot parse %s" % svg_path)
    cr = cairo.Context(surface)
    cr.set_antialias(cairo.ANTIALIAS_BEST)
    rect = Rsvg.Rectangle()
    rect.x, rect.y, rect.width, rect.height = 0, 0, size, size
    handle.render_document(cr, rect)


def new_surface(size: int) -> cairo.ImageSurface:
    return cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)


def squircle_path(cr: cairo.Context, x: float, y: float, w: float, h: float,
                  n: float = SQUIRCLE_N, steps: int = 720) -> None:
    """Superellipse |x/a|^n + |y/b|^n = 1 - the modern Android/iOS icon shape."""
    a, b = w / 2.0, h / 2.0
    cx, cy = x + a, y + b
    cr.new_path()
    for i in range(steps + 1):
        t = 2.0 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        px = cx + a * math.copysign(abs(ct) ** (2.0 / n), ct)
        py = cy + b * math.copysign(abs(st) ** (2.0 / n), st)
        cr.line_to(px, py) if i else cr.move_to(px, py)
    cr.close_path()


def circle_path(cr: cairo.Context, size: float) -> None:
    cr.new_path()
    cr.arc(size / 2.0, size / 2.0, size / 2.0, 0, 2 * math.pi)
    cr.close_path()


def crop_scene(scene: cairo.ImageSurface, size: int) -> cairo.ImageSurface:
    """Take the visible view port (central 2/3) out of the 108-unit scene."""
    out = new_surface(size)
    cr = cairo.Context(out)
    offset = (scene.get_width() - size) / 2.0
    cr.set_source_surface(scene, -offset, -offset)
    cr.paint()
    return out


def masked(surface: cairo.ImageSurface, shape: str) -> cairo.ImageSurface:
    size = surface.get_width()
    out = new_surface(size)
    cr = cairo.Context(out)
    cr.set_antialias(cairo.ANTIALIAS_BEST)
    if shape == "circle":
        circle_path(cr, size)
    else:
        squircle_path(cr, 0, 0, size, size)
    cr.clip()
    cr.set_source_surface(surface, 0, 0)
    cr.paint()
    return out


# --- png helpers -----------------------------------------------------------

def png_size(path: str) -> tuple[int, int]:
    with open(path, "rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        die("not a png: %s" % path)
    return struct.unpack(">II", head[16:24])


def replace_if_changed(tmp: str, dst: str) -> bool:
    """Move tmp over dst only when the bytes differ.

    Rewriting identical PNGs still bumps mtime, which makes the Android
    resource pipeline look dirty on every build (and makes "did the icon really
    change?" unanswerable). Compare instead.
    """
    if os.path.isfile(dst):
        with open(tmp, "rb") as a, open(dst, "rb") as b:
            if a.read() == b.read():
                os.unlink(tmp)
                return False
    shutil.move(tmp, dst)
    return True


def resize_png(src: str, dst: str, size: int) -> bool:
    tmp = dst + ".tmp"
    magick = shutil.which("magick") or shutil.which("convert")
    if magick:
        subprocess.run(
            [magick, src, "-filter", "Lanczos", "-resize", "%dx%d" % (size, size), "-strip", tmp],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        return replace_if_changed(tmp, dst)
    img = cairo.ImageSurface.create_from_png(src)
    out = new_surface(size)
    cr = cairo.Context(out)
    cr.scale(size / float(img.get_width()), size / float(img.get_height()))
    cr.set_source_surface(img, 0, 0)
    cr.get_source().set_filter(cairo.FILTER_BEST)
    cr.paint()
    out.write_to_png(tmp)
    return replace_if_changed(tmp, dst)


def alpha_at(surface: cairo.ImageSurface, x: int, y: int) -> int:
    data = surface.get_data()
    idx = y * surface.get_stride() + x * 4
    return data[idx + (3 if sys.byteorder == "little" else 0)]


def alpha_bbox(surface: cairo.ImageSurface, threshold: int = 8):
    data = surface.get_data()
    stride = surface.get_stride()
    shift = 3 if sys.byteorder == "little" else 0
    w, h = surface.get_width(), surface.get_height()
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = y * stride
        for x in range(w):
            if data[row + x * 4 + shift] > threshold:
                x0 = min(x0, x); x1 = max(x1, x)
                y0 = min(y0, y); y1 = max(y1, y)
    if x1 < 0:
        return None
    return x0, y0, x1, y1


# --- verification ----------------------------------------------------------

def verify_legacy(path: str, expected: int) -> None:
    w, h = png_size(path)
    if (w, h) != (expected, expected):
        die("%s: expected %dx%d, got %dx%d" % (path, expected, expected, w, h))
    img = cairo.ImageSurface.create_from_png(path)
    if alpha_at(img, 0, 0) > 8:
        die("%s: baked squircle corner is opaque (mask not applied?)" % path)
    if alpha_at(img, w // 2, h // 2) < 250:
        die("%s: icon centre is transparent" % path)


def verify_foreground(path: str, expected: int) -> None:
    w, h = png_size(path)
    if (w, h) != (expected, expected):
        die("%s: expected %dx%d, got %dx%d" % (path, expected, expected, w, h))
    img = cairo.ImageSurface.create_from_png(path)
    if alpha_at(img, 0, 0) > 8:
        die("%s: foreground corner is not transparent" % path)
    bbox = alpha_bbox(img)
    if bbox is None:
        die("%s: foreground layer is empty" % path)
    # Safe zone: only the central 2/3 (VIEWPORT / CANVAS) survives the launcher mask.
    lo = int(round(w * (CANVAS - VIEWPORT) / 2.0 / CANVAS))
    hi = w - lo - 1
    x0, y0, x1, y1 = bbox
    if x0 < lo or y0 < lo or x1 > hi or y1 > hi:
        die("%s: glyph bleeds into the cropped ring (bbox %s, safe zone %d..%d)"
            % (path, bbox, lo, hi))


def verify_background(path: str, expected: int) -> None:
    w, h = png_size(path)
    if (w, h) != (expected, expected):
        die("%s: expected %dx%d, got %dx%d" % (path, expected, expected, w, h))
    img = cairo.ImageSurface.create_from_png(path)
    for x, y in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1), (w // 2, h // 2)):
        if alpha_at(img, x, y) < 250:
            die("%s: background layer must be full bleed (alpha at %d,%d)" % (path, x, y))


# --- preview (device-shaped proof) ----------------------------------------

def write_preview(scene_crop: cairo.ImageSurface, out_dir: str) -> str:
    os.makedirs(out_dir, exist_ok=True)
    dark = (0.04, 0.05, 0.07)
    panel = (0.07, 0.08, 0.10)
    sheet_w, sheet_h = 700, 280
    sheet = cairo.ImageSurface(cairo.FORMAT_ARGB32, sheet_w, sheet_h)
    cr = cairo.Context(sheet)
    cr.set_source_rgb(*dark)
    cr.paint()
    cr.set_source_rgb(*panel)
    cr.rectangle(0, 0, sheet_w, sheet_h)
    cr.fill()

    entries = [
        ("squircle", 192), ("circle", 192), ("squircle", 96), ("squircle", 48),
    ]
    x = 30
    for shape, size in entries:
        icon = masked(scene_crop, shape)
        tmp = os.path.join(out_dir, "_icon-%s-%d.png" % (shape, size))
        icon.write_to_png(tmp)
        small_png = os.path.join(out_dir, "_icon-%s-%d-small.png" % (shape, size))
        resize_png(tmp, small_png, size)
        small = cairo.ImageSurface.create_from_png(small_png)
        cr.set_source_surface(small, x, (sheet_h - size) / 2.0)
        cr.paint()
        os.unlink(tmp)
        os.unlink(small_png)
        x += size + 40

    path = os.path.join(out_dir, "icon-preview.png")
    sheet.write_to_png(path)

    for shape in ("squircle", "circle"):
        icon = masked(scene_crop, shape)
        icon.write_to_png(os.path.join(out_dir, "icon-adaptive-%s.png" % shape))
    return path


# --- main ------------------------------------------------------------------

def main() -> int:
    ap = argparse.ArgumentParser(description="render Lumo launcher icons")
    ap.add_argument("--res", help="res_chromium_base directory to write into")
    ap.add_argument("--out", help="standalone output directory (density subdirs)")
    ap.add_argument("--preview", help="directory for launcher-shaped preview pngs")
    args = ap.parse_args()
    if not args.res and not args.out:
        ap.error("one of --res / --out is required")
    for svg in (BG_SVG, FG_SVG, MONO_XML):
        if not os.path.isfile(svg):
            die("missing branding asset: %s" % svg)

    Rsvg = load_rsvg()

    with tempfile.TemporaryDirectory(prefix="lumo-icons-") as tmp:
        # 108-unit scene: background + foreground, as the launcher composites them
        bg = new_surface(MASTER)
        render_svg(bg, BG_SVG, MASTER, Rsvg)
        fg = new_surface(MASTER)
        render_svg(fg, FG_SVG, MASTER, Rsvg)

        scene = new_surface(MASTER)
        cr = cairo.Context(scene)
        cr.set_source_surface(bg, 0, 0)
        cr.paint()
        cr.set_source_surface(fg, 0, 0)
        cr.paint()

        visible = int(round(MASTER * VIEWPORT / CANVAS))
        crop = crop_scene(scene, visible)

        legacy = masked(crop, "squircle")
        legacy_png = os.path.join(tmp, "app_icon.png")
        legacy.write_to_png(legacy_png)
        fg_png = os.path.join(tmp, "layered_app_icon.png")
        fg.write_to_png(fg_png)
        bg_png = os.path.join(tmp, "layered_app_icon_background.png")
        bg.write_to_png(bg_png)

        targets = []
        if args.res:
            for name, legacy_px in DENSITIES:
                targets.append((args.res, name, legacy_px))
        if args.out:
            for name, legacy_px in DENSITIES:
                targets.append((args.out, name, legacy_px))

        for root, name, legacy_px in targets:
            mipmap = os.path.join(root, "mipmap-" + name)
            os.makedirs(mipmap, exist_ok=True)
            jobs = [
                (legacy_png, os.path.join(mipmap, "app_icon.png"),
                 legacy_px, verify_legacy),
                (fg_png, os.path.join(mipmap, "layered_app_icon.png"),
                 int(round(legacy_px * LEGACY_SCALE)), verify_foreground),
                (bg_png, os.path.join(mipmap, "layered_app_icon_background.png"),
                 int(round(legacy_px * LEGACY_SCALE * 1.5)), verify_background),
            ]
            changed = False
            for src, dst, px, check in jobs:
                changed = resize_png(src, dst, px) or changed
                check(dst, px)
            if changed:
                print("[icons] updated mipmap-%s" % name)

        if args.res:
            drawable = os.path.join(args.res, "drawable")
            os.makedirs(drawable, exist_ok=True)
            mono_dst = os.path.join(drawable, "themed_app_icon.xml")
            mono_tmp = mono_dst + ".tmp"
            shutil.copyfile(MONO_XML, mono_tmp)
            if replace_if_changed(mono_tmp, mono_dst):
                print("[icons] themed_app_icon.xml updated")

        if args.preview:
            print("[icons] preview -> %s" % write_preview(crop, args.preview))

        print("[icons] ok: %d densities, %dx%d master" % (len(DENSITIES), MASTER, MASTER))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
