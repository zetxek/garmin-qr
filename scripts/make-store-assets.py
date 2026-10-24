#!/usr/bin/env python3
"""Builds the Connect IQ store listing assets in assets/store/.

  python3 scripts/make-store-assets.py prep <raw-dir>   # simulator window captures -> assets/store/source/
  python3 scripts/make-store-assets.py build [target]   # target: hero | icons | screens | video | brand | all

`prep` takes full-window captures of the Connect IQ simulator (fenix 8 43mm) and cuts the watch
out of the white window background. `build` composes everything else from those cut-outs, so the
listing can be regenerated after a UI change by re-capturing the screens and running both steps.
Needs Pillow; the video step also needs ffmpeg.

Portal limits (Connect IQ developer portal, "Edit App Details"):
  hero image   1440x720, JPG/GIF/PNG, <= 2048 KB
  cover image  500x500, JPG/GIF/PNG, < 300 KB  (this is also the icon shown in store lists)
  device icons 128x128, < 150 KB: a 24-bit one (AMOLED) and a 64-colour one (MIP)
  screen images up to 5, JPG/GIF/PNG, < 150 KB each
  preview video: a YouTube or Vimeo link only
"""
import math
import os
import random
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "store")
SRC = os.path.join(OUT, "source")

BG_TOP = (14, 22, 56)
BG_BOT = (31, 54, 132)
GLOW = (70, 120, 255)
BLUE = (37, 84, 224)
NAVY = (11, 18, 48)
AMBER = (255, 194, 71)
WHITE = (255, 255, 255)
MUTED = (180, 194, 232)

FONT_FILE = "/System/Library/Fonts/SFNS.ttf"
_fonts = {}


def font(size, weight="Bold"):
    key = (size, weight)
    if key not in _fonts:
        f = ImageFont.truetype(FONT_FILE, size)
        f.set_variation_by_name(weight)
        _fonts[key] = f
    return _fonts[key]


# --------------------------------------------------------------------------- prep

def prep(raw_dir):
    """Cut the watch out of simulator window captures (2x retina, 1206x1720)."""
    os.makedirs(SRC, exist_ok=True)
    for name in ("qr", "bar", "wifi", "info", "settings", "sortby", "glance"):
        im = Image.open(os.path.join(raw_dir, name + ".png")).convert("RGB")
        w, h = im.size
        im = im.crop((6, 58, w - 6, h - 62))  # window title bar, status bar and side borders
        w, h = im.size
        bw = im.convert("L").point(lambda v: 255 if v >= 246 else 0)
        # Flood the white background from the border only, so the white QR inside the display stays.
        for xy in [(2, 2), (w - 3, 2), (2, h // 2), (w - 3, h // 2), (w // 2, 2),
                   (w // 2, h - 3), (2, h - 3), (w - 3, h - 3)]:
            if bw.getpixel(xy) == 255:
                ImageDraw.floodfill(bw, xy, 128)
        alpha = bw.point(lambda v: 0 if v == 128 else 255)
        alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.1))
        # The strap runs off the top and bottom of the capture; fade it out rather than cut it.
        fade = Image.new("L", (w, h), 255)
        d = ImageDraw.Draw(fade)
        span = 150
        for y in range(span):
            v = int(255 * (y / span) ** 1.4)
            d.line([(0, y), (w, y)], fill=v)
            d.line([(0, h - 1 - y), (w, h - 1 - y)], fill=v)
        out = im.convert("RGBA")
        out.putalpha(ImageChops.multiply(alpha, fade))
        out = out.resize((round(w * 0.75), round(h * 0.75)), Image.LANCZOS)
        out.save(os.path.join(SRC, name + ".png"), optimize=True)
        print("source", name, out.size)


# --------------------------------------------------------------------------- shared drawing

def background(w, h):
    mask = Image.linear_gradient("L").resize((w, h))
    return Image.composite(Image.new("RGB", (w, h), BG_BOT), Image.new("RGB", (w, h), BG_TOP), mask)


def glow_mask(r):
    # PIL's radial gradient only reaches 255 at the corners, so rescale it to hit 255 at the
    # circle's edge; otherwise the glow ends in a visible square.
    m = Image.radial_gradient("L").resize((2 * r, 2 * r))
    m = m.point(lambda v: int(min(255, v * 1.4143)))
    return m.point(lambda v: int(((255 - v) / 255) ** 1.6 * 255 * 0.5))


def add_glow(canvas, cx, cy, r):
    canvas.paste(Image.new("RGB", (2 * r, 2 * r), GLOW), (cx - r, cy - r), glow_mask(r))


_watch_cache = {}


def watch(name, height, shadow=True):
    """Watch cut-out at the given height, with a soft drop shadow baked in (RGBA, padded)."""
    key = (name, height, shadow)
    if key in _watch_cache:
        return _watch_cache[key]
    im = Image.open(os.path.join(SRC, name + ".png"))
    im = im.resize((round(im.width * height / im.height), height), Image.LANCZOS)
    if shadow:
        pad = 90
        layer = Image.new("RGBA", (im.width + 2 * pad, im.height + 2 * pad), (0, 0, 0, 0))
        sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        sh.paste((0, 0, 0, 255), (pad, pad + 26), im.getchannel("A"))
        sh = sh.filter(ImageFilter.GaussianBlur(28))
        sh.putalpha(sh.getchannel("A").point(lambda v: int(v * 0.5)))
        layer.alpha_composite(sh)
        layer.alpha_composite(im, (pad, pad))
        im = layer
    _watch_cache[key] = im
    return im


def rotated(im, angle):
    return im.rotate(angle, resample=Image.BICUBIC, expand=True)


def put(canvas, layer, cx, cy, opacity=1.0):
    x, y = round(cx - layer.width / 2), round(cy - layer.height / 2)
    if opacity >= 1.0:
        canvas.paste(layer, (x, y), layer)
        return
    if opacity <= 0.0:
        return
    a = layer.getchannel("A").point(lambda v: int(v * opacity))
    canvas.paste(layer, (x, y), a)


def wrap(draw, text, fnt, max_w):
    lines, cur = [], ""
    for word in text.split():
        t = (cur + " " + word).strip()
        if draw.textlength(t, font=fnt) <= max_w:
            cur = t
        else:
            lines.append(cur)
            cur = word
    lines.append(cur)
    return lines


def fit(draw, text, weight, max_w, start, floor=20):
    size = start
    while size > floor and draw.textlength(text, font=font(size, weight)) > max_w:
        size -= 2
    return font(size, weight)


def tracked(draw, xy, text, fnt, fill, tracking):
    x, y = xy
    for ch in text:
        draw.text((x, y), ch, font=fnt, fill=fill)
        x += draw.textlength(ch, font=fnt) + tracking


def text_layer(width, lines, fnt, fill, line_h, align="left"):
    """Pre-rendered RGBA block of text lines, for animated captions."""
    layer = Image.new("RGBA", (width, line_h * len(lines) + 10), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    for i, ln in enumerate(lines):
        tw = d.textlength(ln, font=fnt)
        x = {"left": 0, "center": (width - tw) / 2, "right": width - tw}[align]
        d.text((x, i * line_h), ln, font=fnt, fill=fill)
    return layer


# --------------------------------------------------------------------------- icon / cover

def draw_icon(size, palette64=False):
    """The app icon: a watch bezel around a QR tile, on a solid colour (no text, no Garmin marks)."""
    k = 4
    n = size * k
    im = Image.new("RGB", (n, n), BLUE)
    d = ImageDraw.Draw(im)
    c = n / 2
    r_out = n * 0.455
    ring = n * 0.034
    d.ellipse([c - r_out, c - r_out, c + r_out, c + r_out], fill=WHITE)
    d.ellipse([c - r_out + ring, c - r_out + ring, c + r_out - ring, c + r_out - ring], fill=NAVY)

    tile = n * 0.50
    d.rounded_rectangle([c - tile / 2, c - tile / 2, c + tile / 2, c + tile / 2],
                        radius=tile * 0.06, fill=WHITE)
    cells = 21
    m = tile * 0.84 / cells
    x0 = c - m * cells / 2
    y0 = c - m * cells / 2

    def cell(i, j, col):
        d.rectangle([x0 + i * m, y0 + j * m, x0 + (i + 1) * m - 1, y0 + (j + 1) * m - 1], fill=col)

    def finder(i, j):
        for a in range(7):
            for b in range(7):
                ring_cell = a in (0, 6) or b in (0, 6)
                core = 2 <= a <= 4 and 2 <= b <= 4
                if ring_cell or core:
                    cell(i + a, j + b, NAVY)

    finder(0, 0)
    finder(14, 0)
    finder(0, 14)
    rnd = random.Random(11)
    for i in range(cells):
        for j in range(cells):
            in_finder = (i < 8 and j < 8) or (i > 12 and j < 8) or (i < 8 and j > 12)
            in_accent = i >= 14 and j >= 14
            if not in_finder and not in_accent and rnd.random() < 0.5:
                cell(i, j, NAVY)
    for a in range(5):  # amber alignment pattern
        for b in range(5):
            edge = a in (0, 4) or b in (0, 4)
            if edge or (a == 2 and b == 2):
                cell(15 + a, 15 + b, AMBER)
    out = im.resize((size, size), Image.LANCZOS)
    if palette64:
        steps = (0, 85, 170, 255)  # the 64-colour palette of memory-in-pixel displays
        snap = lambda v: min(steps, key=lambda s: abs(s - v))
        r, g, b = out.split()
        out = Image.merge("RGB", [ch.point(snap) for ch in (r, g, b)])
    return out


def build_icons():
    draw_icon(500).save(os.path.join(OUT, "cover-500.png"), optimize=True)
    draw_icon(128).save(os.path.join(OUT, "icon-128-24bit.png"), optimize=True)
    draw_icon(128, palette64=True).save(os.path.join(OUT, "icon-128-64color.png"), optimize=True)


def publish_brand():
    """Replace the older brand files elsewhere in the repo, keeping their names and sizes."""
    assets = os.path.join(ROOT, "assets")
    Image.open(os.path.join(OUT, "hero-1440x720.png")).convert("RGB").save(
        os.path.join(assets, "hero.jpeg"), quality=92, optimize=True)
    draw_icon(500).save(os.path.join(assets, "cover.jpeg"), quality=95, subsampling=0, optimize=True)
    big = draw_icon(1024)
    big.save(os.path.join(assets, "cover.png"), optimize=True)
    big.save(os.path.join(assets, "demo.jpeg"), format="PNG", optimize=True)  # a copy of cover.png, as before
    big.save(os.path.join(assets, "not-qr.png"), optimize=True)
    small = draw_icon(60)
    small.save(os.path.join(assets, "not-qr-60.png"), optimize=True)
    small.save(os.path.join(ROOT, "resources", "drawables", "qr.png"), optimize=True)  # launcher icon


# --------------------------------------------------------------------------- hero

def build_hero():
    w, h = 1440, 720
    c = background(w, h)
    add_glow(c, 1060, 380, 560)
    put(c, rotated(watch("bar", 700), 13), 1355, 470)
    put(c, rotated(watch("qr", 860), -5), 1055, 392)

    d = ImageDraw.Draw(c)
    x = 84
    tracked(d, (x, 118), "QR + BARCODE", font(30, "Bold"), AMBER, 7)
    f1 = fit(d, "on your wrist.", "Bold", 650, 104)
    d.text((x, 168), "Your codes,", font=f1, fill=WHITE)
    d.text((x, 168 + f1.size * 1.08), "on your wrist.", font=f1, fill=AMBER)
    sub = font(38, "Medium")
    y = 168 + f1.size * 2.35
    for ln in ("QR codes and Code 128 barcodes", "made on the watch. Works offline."):
        d.text((x, y), ln, font=sub, fill=MUTED)
        y += 52
    cx = x
    y += 22
    chip = font(26, "Semibold")
    for label in ("Up to 20 codes", "Glance view", "Open source"):
        tw = d.textlength(label, font=chip)
        d.rounded_rectangle([cx, y, cx + tw + 40, y + 52], radius=26, outline=(120, 148, 225), width=2)
        d.text((cx + 20, y + 9), label, font=chip, fill=WHITE)
        cx += tw + 40 + 14
    c.save(os.path.join(OUT, "hero-1440x720.png"), optimize=True)


# --------------------------------------------------------------------------- screens

SCREENS = [
    ("qr", "Tickets, passes", "and links as QR codes"),
    ("bar", "Membership and loyalty", "cards as barcodes"),
    ("sortby", "Sort your codes", "by date, title or code"),
    ("settings", "Built for easy scanning", "Screen-on and thicker bars"),
    ("glance", "Your first code,", "one glance away"),
]


def build_screens():
    w = h = 800
    for i, (name, l1, l2) in enumerate(SCREENS, 1):
        c = background(w, h)
        add_glow(c, 400, 540, 430)
        put(c, watch(name, 740), 400, 525)
        d = ImageDraw.Draw(c)
        f = fit(d, l2, "Bold", 720, 60)
        for j, ln in enumerate((l1, l2)):
            tw = d.textlength(ln, font=f)
            d.text(((w - tw) / 2, 52 + j * (f.size * 1.15)), ln, font=f, fill=WHITE if j == 0 else AMBER)
        path = os.path.join(OUT, f"screen-{i}-{name}.jpg")
        for q in (92, 88, 84, 80, 74, 68):
            c.save(path, quality=q, optimize=True, subsampling=0 if q >= 88 else 2)
            if os.path.getsize(path) < 150 * 1024:
                break


# --------------------------------------------------------------------------- video

FPS = 30
VW, VH = 1920, 1080
TITLE_END = 3.2
SCENES = [
    ("qr", "Tickets, passes\nand links", "Show any QR code from your wrist.", 3.0, 7.5),
    ("bar", "Cards and\nmemberships", "Code 128 barcodes for gym, loyalty and library cards.", 7.5, 12.0),
    ("wifi", "Made on\nthe watch", "Codes are generated on the watch. Works offline.", 12.0, 16.0),
    ("info", "Manage codes\nanywhere", "Add, edit and delete on the watch, or from the Connect IQ app.", 16.0, 20.5),
    ("settings", "Built for\neasy scanning", "Keep the screen on, and switch to thicker bars.", 20.5, 24.5),
    ("sortby", "Sort your\nway", "Order codes by date added, title or code.", 24.5, 28.5),
    ("glance", "One glance\naway", "Your first code, right in the glance list.", 28.5, 32.5),
]
END_START = 32.0
TOTAL = 37.5


def ease(x):
    x = max(0.0, min(1.0, x))
    return 1 - (1 - x) ** 3


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.width - 1, im.height - 1], radius=radius, fill=255)
    out = im.convert("RGBA")
    out.putalpha(mask)
    return out


def build_video():
    base = background(VW, VH)
    glow = glow_mask(760)
    glow_layer = Image.new("RGB", glow.size, GLOW)
    icon_big = rounded(draw_icon(360), 80)
    icon_small = rounded(draw_icon(260), 58)
    probe = ImageDraw.Draw(Image.new("RGB", (10, 10)))

    watches = {s[0]: watch(s[0], 980) for s in SCENES}
    caps = []
    for name, head, sub, t0, t1 in SCENES:
        hl = head.split("\n")
        head_layer = text_layer(900, hl, font(104, "Bold"), WHITE, 120)
        sub_layer = text_layer(760, wrap(probe, sub, font(42, "Medium"), 720), font(42, "Medium"), MUTED, 58)
        caps.append((head_layer, sub_layer))
    title_h = text_layer(1400, ["QR + Barcode"], font(120, "Bold"), WHITE, 140, "center")
    title_s = text_layer(1400, ["Your codes, on your wrist."], font(54, "Medium"), AMBER, 70, "center")
    end_t = text_layer(1400, ["QR + Barcode"], font(104, "Bold"), WHITE, 124, "center")
    end_s = text_layer(1400, ["Available on the Connect IQ Store"], font(48, "Medium"), MUTED, 64, "center")
    end_u = text_layer(1400, ["github.com/zetxek/garmin-qr  ·  Open source"], font(40, "Medium"), AMBER, 56, "center")

    ff = subprocess.Popen(
        ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24",
         "-s", f"{VW}x{VH}", "-r", str(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow",
         "-crf", "17", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
         os.path.join(OUT, "preview-1080p.mp4")], stdin=subprocess.PIPE)

    n = int(TOTAL * FPS)
    for fi in range(n):
        t = fi / FPS
        c = base.copy()
        gx = 1380 + 40 * math.sin(t * 0.7)
        c.paste(glow_layer, (round(gx - 760), 540 - 760), glow)

        if t < TITLE_END + 0.4:
            a = ease(t / 0.8) * (1 - ease((t - (TITLE_END - 0.4)) / 0.6))
            s = 0.92 + 0.08 * ease(t / 1.0)
            ic = icon_big.resize((round(360 * s), round(360 * s)), Image.LANCZOS)
            put(c, ic, VW / 2, 360, a)
            put(c, title_h, VW / 2, 640, ease((t - 0.3) / 0.7) * (1 - ease((t - (TITLE_END - 0.4)) / 0.6)))
            put(c, title_s, VW / 2, 760, ease((t - 0.6) / 0.7) * (1 - ease((t - (TITLE_END - 0.4)) / 0.6)))

        for i, (name, head, sub, t0, t1) in enumerate(SCENES):
            fade_in = ease((t - t0) / 0.7)
            fade_out = 1 - ease((t - (t1 - 0.1)) / 0.7) if i < len(SCENES) - 1 else 1 - ease((t - (END_START - 0.3)) / 0.7)
            a = fade_in * fade_out
            if a <= 0:
                continue
            bob = 10 * math.sin(t * 1.3)
            slide = (1 - ease((t - t0) / 0.9)) * 70 if i == 0 else 0
            put(c, watches[name], 1380 + slide, 545 + bob, a)
            hl, sl = caps[i]
            ca = ease((t - t0 - 0.1) / 0.55) * (1 - ease((t - (t1 - 0.25)) / 0.4)) if i < len(SCENES) - 1 \
                else ease((t - t0 - 0.1) / 0.55) * (1 - ease((t - (END_START - 0.5)) / 0.4))
            rise = (1 - ease((t - t0 - 0.1) / 0.55)) * 40
            put(c, hl, 140 + hl.width / 2, 400 + rise, ca)
            put(c, sl, 140 + sl.width / 2, 400 + hl.height + 40 + rise, ca)

        if t >= END_START - 0.2:
            a = ease((t - END_START) / 0.8)
            put(c, icon_small, VW / 2, 330, a)
            put(c, end_t, VW / 2, 560, ease((t - END_START - 0.2) / 0.7))
            put(c, end_s, VW / 2, 680, ease((t - END_START - 0.5) / 0.7))
            put(c, end_u, VW / 2, 780, ease((t - END_START - 0.8) / 0.7))

        ff.stdin.write(c.tobytes())
    ff.stdin.close()
    ff.wait()


# --------------------------------------------------------------------------- main

def main():
    if len(sys.argv) < 2 or sys.argv[1] not in ("prep", "build"):
        sys.exit(__doc__)
    if sys.argv[1] == "prep":
        if len(sys.argv) < 3:
            sys.exit("prep needs the directory holding the simulator window captures")
        prep(sys.argv[2])
        return
    target = sys.argv[2] if len(sys.argv) > 2 else "all"
    os.makedirs(OUT, exist_ok=True)
    steps = {"icons": build_icons, "hero": build_hero, "screens": build_screens, "video": build_video,
             "brand": publish_brand}
    for name, fn in steps.items():
        if target in ("all", name):
            print("building", name)
            fn()


if __name__ == "__main__":
    main()
