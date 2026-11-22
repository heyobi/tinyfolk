"""App Store screenshots for Tinyfolk.

Usage: python -X utf8 scripts/compose-screens.py <raw-dir> <out-dir> <iphone|ipad|duo-outer|duo-inner> [--rotate 90|-90]

iPhone, iPad and the folded iPhone Duo: headline, subline and the simulator screenshot on a deep gradient.

iPhone Duo inner display, stage shots: the app ran half open with simulated viewer eye E and wrote <name>.json
(eye, hinge, window and fold in points). Here the two halves of the raw screenshot are drawn onto a half-open
device seen from exactly that eye. Because the app rendered each half with an off-axis projection from E, the
composite shows what that viewer sees: the character standing in the corner, in 3D. A dashed line marks the fold.
"""
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

BOLD = 'C:/Windows/Fonts/segoeuib.ttf'
SEMI = 'C:/Windows/Fonts/segoeui.ttf'

# raw name → (title, subtitle on Duo, subtitle elsewhere)
TEXT = {
    '1-stage': ('A tiny friend on the fold', 'Stand iPhone Duo half open: true 3D, no glasses', ''),
    '2-two': ('It notices both of you', 'Looks at whoever looks, waves at newcomers', 'Looks at whoever looks, waves at newcomers'),
    '3-dance': ('Dances to live music', 'Original pieces and timeless tunes', ''),
    '4-tide': ('Six little stages', 'From a holo studio to a tide pool', ''),
    '5-well': ('Open it flat. Surprise!', 'Lanterns rise and knock on the glass', ''),
    '1-box': ('A pocket hologram', 'Follows your eyes for true 3D depth', 'Follows your eyes for true 3D depth'),
    '3-well': ('Lay it flat, look down', 'A lantern well beneath the glass', 'A lantern well beneath the glass'),
    '4-snow': ('Six little stages', 'From a holo studio to first snow', 'From a holo studio to first snow'),
    '6-friends': ('Eight original friends', 'Four free, each with their own dance', 'Four free, each with their own dance'),
}
ORDER_DUO_INNER = ['1-stage', '2-two', '3-dance', '4-tide', '5-well', '6-friends']
ORDER_OTHER = ['1-box', '2-two', '3-well', '4-snow', '6-friends']


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.truetype('C:/Windows/Fonts/arial.ttf', size)


def gradient(w, h, top=(10, 16, 40), bottom=(3, 5, 14)):
    g = Image.new('RGB', (1, h))
    for y in range(h):
        t = y / (h - 1)
        g.putpixel((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    img = g.resize((w, h))
    glow = Image.new('RGBA', (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([w * 0.1, h * 0.35, w * 0.9, h * 1.1], fill=(70, 190, 230, 46))
    glow = glow.filter(ImageFilter.GaussianBlur(min(w, h) * 0.12))
    img.paste(glow, (0, 0), glow)
    return img


def headline(canvas, title, sub, k, y, width=None, x=None):
    d = ImageDraw.Draw(canvas)
    w = width or canvas.size[0]
    f1, f2 = font(BOLD, int(98 * k)), font(SEMI, int(54 * k))
    while d.textlength(title, font=f1) > w - 120 * k and f1.size > 40:
        f1 = font(BOLD, f1.size - 4)
    while sub and d.textlength(sub, font=f2) > w - 120 * k and f2.size > 28:
        f2 = font(SEMI, f2.size - 2)
    x0 = x if x is not None else 0
    for text, f, fill, gap in ((title, f1, (244, 248, 255), 22 * k), (sub, f2, (125, 220, 255), 0)):
        if not text:
            continue
        tw = d.textlength(text, font=f)
        d.text((x0 + (w - tw) / 2, y), text, font=f, fill=fill)
        y += f.size + gap + 14 * k
    return y


def rounded(img, r):
    mask = Image.new('L', img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, *img.size), r, fill=255)
    out = Image.new('RGBA', img.size)
    out.paste(img, (0, 0), mask)
    return out


def framed(canvas, shot, top, k, max_h=None):
    w, h = canvas.size
    sh = min(max_h or int(h * 0.8), h - top - int(50 * k))
    sw = int(sh * shot.size[0] / shot.size[1])
    if sw > w * 0.9:
        sw = int(w * 0.9)
        sh = int(sw * shot.size[1] / shot.size[0])
    r = int(min(sw, sh) * 0.06)
    x = (w - sw) // 2
    pad = int(60 * k)
    shadow = Image.new('RGBA', (sw + 2 * pad, sh + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((pad, pad + 12, sw + pad, sh + pad + 12), r + 10, fill=(0, 0, 0, 170))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(int(34 * k))), (x - pad, top - pad))
    b = max(6, int(9 * k))
    border = Image.new('RGBA', (sw + 2 * b, sh + 2 * b), (0, 0, 0, 0))
    ImageDraw.Draw(border).rounded_rectangle((0, 0, sw + 2 * b - 1, sh + 2 * b - 1), r + b, fill=(22, 24, 32, 255))
    canvas.alpha_composite(border, (x - b, top - b))
    canvas.alpha_composite(rounded(shot.resize((sw, sh), Image.LANCZOS).convert('RGB'), r), (x, top))


def compose_flat(raw, title, sub, out):
    shot = Image.open(raw).convert('RGB')
    w, h = shot.size
    k = min(w, h) / 1206 * (1 if h >= w else 0.8)
    canvas = gradient(w, h).convert('RGBA')
    y = headline(canvas, title, sub, k, int(150 * k) if h > w else int(80 * k))
    framed(canvas, shot, int(y + 70 * k), k)
    canvas.convert('RGB').save(out, optimize=True)


# ---------- half-open hologram mockup ----------

def coeffs(src, dst):
    A, b = [], []
    for (x, y), (u, v) in zip(dst, src):
        A.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        A.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    return np.linalg.solve(np.array(A, float), np.array(b, float)).tolist()


def warp(img, quad, size):
    w, h = img.size
    src = [(0, 0), (w, 0), (w, h), (0, h)]   # TL, TR, BR, BL
    out = img.convert('RGBA').transform(size, Image.PERSPECTIVE, coeffs(src, quad), Image.BICUBIC)
    mask = Image.new('L', size, 0)
    ImageDraw.Draw(mask).polygon(quad, fill=255)
    out.putalpha(mask)
    return out


def look_at(eye, target, up=(0, 1, 0)):
    eye, target, up = np.array(eye, float), np.array(target, float), np.array(up, float)
    f = target - eye; f /= np.linalg.norm(f)
    r = np.cross(f, up); r /= np.linalg.norm(r)
    u = np.cross(r, f)
    return eye, r, u, f


def project(p, cam, focal, cx, cy):
    eye, r, u, f = cam
    d = np.array(p, float) - eye
    z = d @ f
    return (cx + focal * (d @ r) / z, cy - focal * (d @ u) / z)


def compose_stage(raw_path, meta_path, title, sub, out, rotate):
    m = json.load(open(meta_path))
    raw = Image.open(raw_path).convert('RGB')
    if rotate:
        raw = raw.rotate(rotate, expand=True)
    win_w, win_h = m['size']
    fx, fy, fw, fh = m['fold']
    s = raw.size[0] / win_w
    upper_img = raw.crop((0, 0, raw.size[0], int(fy * s)))
    lower_img = raw.crop((0, int((fy + fh) * s), raw.size[0], raw.size[1]))
    hinge = math.radians(m['hinge'])
    uw, uh = m['upper']
    lw, lh = m['lower']
    udir = np.array([0, math.sin(hinge), math.cos(hinge)])
    # Corners (TL, TR, BR, BL as seen in each half's image).
    U = [np.array([-uw / 2, 0, 0]) + udir * uh, np.array([uw / 2, 0, 0]) + udir * uh, np.array([uw / 2, 0, 0]), np.array([-uw / 2, 0, 0])]
    L = [np.array([-lw / 2, 0, 0]), np.array([lw / 2, 0, 0]), np.array([lw / 2, 0, lh]), np.array([-lw / 2, 0, lh])]

    W, H = 2853, 2007
    canvas = gradient(W, H).convert('RGBA')
    k = H / 1206 * 0.8
    # Text on the left third, device on the right two thirds.
    text_w = int(W * 0.36)
    headline_y = int(H * 0.36)
    # Viewer camera at the simulated eye, looking at the middle of the stage.
    cam = look_at(m['eye'], (0, 0.035, 0.03))
    pts = [project(p, cam, 1, 0, 0) for p in U + L]
    xs, ys = [p[0] for p in pts], [p[1] for p in pts]
    avail_w, avail_h = W - text_w - 120, H * 0.86
    focal = min(avail_w / (max(xs) - min(xs)), avail_h / (max(ys) - min(ys)))
    cx = text_w + 40 + avail_w / 2 - focal * (max(xs) + min(xs)) / 2
    cy = H * 0.5 - focal * (max(ys) + min(ys)) / 2
    P = lambda p: project(p, cam, focal, cx, cy)

    # Table shadow under the lower half, then bezels, then screens.
    sh = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    grow = 0.012
    Lb = [L[0] + [-grow, 0, -grow], L[1] + [grow, 0, -grow], L[2] + [grow, 0, grow], L[3] + [-grow, 0, grow]]
    ImageDraw.Draw(sh).polygon([P(p + [0, -0.002, 0.01]) for p in Lb], fill=(0, 0, 0, 200))
    canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(40)))
    bez = 0.0035
    Ub = [U[0] + [-bez, 0, 0] + udir * bez, U[1] + [bez, 0, 0] + udir * bez, U[2] + [bez, 0, 0], U[3] + [-bez, 0, 0]]
    Lbz = [L[0] + [-bez, 0, 0], L[1] + [bez, 0, 0], L[2] + [bez, 0, bez], L[3] + [-bez, 0, bez]]
    dev = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dev)
    dd.polygon([P(p - udir * 0.0005 + np.array([0, 0, -0.0015])) for p in Ub], fill=(28, 30, 38, 255))
    dd.polygon([P(p + np.array([0, -0.0015, 0])) for p in Lbz], fill=(34, 36, 46, 255))
    canvas.alpha_composite(dev)
    canvas.alpha_composite(warp(upper_img, [P(p) for p in U], (W, H)))
    canvas.alpha_composite(warp(lower_img, [P(p) for p in L], (W, H)))
    # Dashed fold line with a label.
    a, b = np.array(P(U[3])), np.array(P(U[2]))
    over = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    od = ImageDraw.Draw(over)
    n = 26
    for i in range(n):
        if i % 2 == 0:
            p0, p1 = a + (b - a) * i / n, a + (b - a) * (i + 1) / n
            od.line([tuple(p0), tuple(p1)], fill=(255, 255, 255, 170), width=5)
    f = font(SEMI, int(40 * k))
    label = 'iPhone Duo fold'
    tw = od.textlength(label, font=f)
    lx, ly = min(W - tw - 60, b[0] - tw * 0.2), b[1] + 34
    od.rounded_rectangle((lx - 18, ly - 6, lx + tw + 18, ly + f.size + 18), radius=(f.size + 24) / 2, fill=(255, 255, 255, 230))
    od.text((lx, ly), label, font=f, fill=(20, 30, 50, 255))
    canvas.alpha_composite(over)
    headline(canvas, title, sub, k * 0.95, headline_y, width=text_w, x=40)
    canvas.convert('RGB').save(out, optimize=True)


def main():
    raw, out, kind = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
    rotate = int(sys.argv[sys.argv.index('--rotate') + 1]) if '--rotate' in sys.argv else 0
    out.mkdir(parents=True, exist_ok=True)
    order = ORDER_DUO_INNER if kind == 'duo-inner' else ORDER_OTHER
    i = 0
    for name in order:
        src = raw / f'{name}.png'
        if not src.exists():
            print('missing', name)
            continue
        i += 1
        title, sub_duo, sub = TEXT[name]
        dst = out / f'{i}-{name[2:]}.png'
        meta = raw / f'{name}.json'
        if kind == 'duo-inner' and meta.exists() and 'upper' in json.load(open(meta)):
            compose_stage(src, meta, title, sub_duo, dst, rotate)
        else:
            compose_flat(src, title, sub_duo if kind.startswith('duo') else (sub or sub_duo), dst)
        print('saved', dst.name)


if __name__ == '__main__':
    main()
