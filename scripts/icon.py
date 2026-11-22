# Draws the Tinyfolk icon (1024x1024, no alpha) and writes the asset catalog (AppIcon, AccentColor, LaunchColor).
# A tiny friend standing on a glowing ring in the corner of a half-open, dotted stage: back wall and floor meet at
# the fold. Original artwork, drawn here. Usage: python scripts/icon.py
from PIL import Image, ImageDraw, ImageFilter
import json, os, math

S = 1024
SS = 2
W = S * SS
img = Image.new('RGB', (W, W))
d = ImageDraw.Draw(img)
for y in range(W):
    t = y / W
    d.line([(0, y), (W, y)], fill=(int(8 + 10 * t), int(12 + 16 * t), int(30 + 30 * t)))


def lerp(a, b, t):
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t)


def quad_point(q, u, v):
    # q: bottom-left, bottom-right, top-right, top-left
    bl, br, tr, tl = q
    return lerp(lerp(bl, br, u), lerp(tl, tr, u), v)


# The two halves in perspective: wall (upper) and floor (lower), meeting at the fold line.
fold_l, fold_r = (W * 0.16, W * 0.60), (W * 0.84, W * 0.60)
wall = [fold_l, fold_r, (W * 0.80, W * 0.16), (W * 0.20, W * 0.16)]
floor = [(W * 0.04, W * 0.90), (W * 0.96, W * 0.90), fold_r, fold_l]

panel = Image.new('RGBA', (W, W), (0, 0, 0, 0))
P = ImageDraw.Draw(panel)
P.polygon(wall, fill=(14, 24, 52, 255))
P.polygon(floor, fill=(18, 32, 66, 255))
img.paste(panel, (0, 0), panel)

dots = Image.new('RGBA', (W, W), (0, 0, 0, 0))
D = ImageDraw.Draw(dots)
for q, n_u, n_v in [(wall, 9, 7), (floor, 11, 5)]:
    for i in range(n_u + 1):
        for j in range(n_v + 1):
            u, v = i / n_u, j / n_v
            x, y = quad_point(q, u, v)
            r = W * (0.0055 if q is wall else 0.004 + 0.004 * (1 - v))
            D.ellipse([x - r, y - r, x + r, y + r], fill=(95, 225, 255, 120))
img.paste(dots, (0, 0), dots)

# Panel rims and the fold.
rim = Image.new('RGBA', (W, W), (0, 0, 0, 0))
R = ImageDraw.Draw(rim)
R.line(wall + [wall[0]], fill=(95, 225, 255, 150), width=int(W * 0.006))
R.line(floor + [floor[0]], fill=(95, 225, 255, 110), width=int(W * 0.006))
R.line([fold_l, fold_r], fill=(150, 240, 255, 230), width=int(W * 0.008))
rim = rim.filter(ImageFilter.GaussianBlur(W * 0.002))
img.paste(rim, (0, 0), rim)

# Glow and ring on the floor.
cx, cy = W * 0.5, W * 0.70
glow = Image.new('RGBA', (W, W), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse([cx - W * 0.25, cy - W * 0.075, cx + W * 0.25, cy + W * 0.075], fill=(95, 225, 255, 120))
glow = glow.filter(ImageFilter.GaussianBlur(W * 0.04))
img.paste(glow, (0, 0), glow)
ring = Image.new('RGBA', (W, W), (0, 0, 0, 0))
ImageDraw.Draw(ring).ellipse([cx - W * 0.17, cy - W * 0.045, cx + W * 0.17, cy + W * 0.045], outline=(170, 245, 255, 255), width=int(W * 0.011))
ring_soft = ring.filter(ImageFilter.GaussianBlur(W * 0.006))
img.paste(ring_soft, (0, 0), ring_soft)
img.paste(ring, (0, 0), ring)

# The tiny friend: a round ceramic robot with a dark visor and two glowing eyes.
fig = Image.new('RGBA', (W, W), (0, 0, 0, 0))
F = ImageDraw.Draw(fig)
# shadow
F.ellipse([cx - W * 0.1, cy - W * 0.02, cx + W * 0.1, cy + W * 0.025], fill=(0, 0, 0, 120))
fig = fig.filter(ImageFilter.GaussianBlur(W * 0.01))
F = ImageDraw.Draw(fig)
body = [cx - W * 0.085, cy - W * 0.19, cx + W * 0.085, cy - W * 0.02]
F.rounded_rectangle(body, radius=W * 0.05, fill=(240, 236, 228, 255))
for sx in (-1, 1):
    F.rounded_rectangle([cx + sx * W * 0.035 - W * 0.022, cy - W * 0.05, cx + sx * W * 0.035 + W * 0.022, cy + W * 0.005], radius=W * 0.02, fill=(140, 152, 166, 255))
head = [cx - W * 0.135, cy - W * 0.43, cx + W * 0.135, cy - W * 0.18]
F.rounded_rectangle(head, radius=W * 0.085, fill=(246, 243, 236, 255))
visor = [cx - W * 0.1, cy - W * 0.37, cx + W * 0.1, cy - W * 0.245]
F.rounded_rectangle(visor, radius=W * 0.05, fill=(20, 24, 32, 255))
for sx in (-1, 1):
    ex, ey = cx + sx * W * 0.045, cy - W * 0.307
    F.ellipse([ex - W * 0.02, ey - W * 0.026, ex + W * 0.02, ey + W * 0.026], fill=(111, 211, 255, 255))
F.line([(cx, cy - W * 0.43), (cx, cy - W * 0.48)], fill=(140, 152, 166, 255), width=int(W * 0.01))
F.ellipse([cx - W * 0.022, cy - W * 0.51, cx + W * 0.022, cy - W * 0.466], fill=(255, 154, 77, 255))
# arm waving
F.line([(cx + W * 0.08, cy - W * 0.15), (cx + W * 0.16, cy - W * 0.26)], fill=(140, 152, 166, 255), width=int(W * 0.032))
F.ellipse([cx + W * 0.14, cy - W * 0.30, cx + W * 0.19, cy - W * 0.25], fill=(246, 243, 236, 255))
F.line([(cx - W * 0.08, cy - W * 0.15), (cx - W * 0.12, cy - W * 0.07)], fill=(140, 152, 166, 255), width=int(W * 0.032))
# soft highlight on the head
hl = Image.new('RGBA', (W, W), (0, 0, 0, 0))
ImageDraw.Draw(hl).ellipse([cx - W * 0.1, cy - W * 0.42, cx - W * 0.02, cy - W * 0.385], fill=(255, 255, 255, 140))
hl = hl.filter(ImageFilter.GaussianBlur(W * 0.006))
fig.paste(hl, (0, 0), hl)
eye_glow = Image.new('RGBA', (W, W), (0, 0, 0, 0))
for sx in (-1, 1):
    ex, ey = cx + sx * W * 0.045, cy - W * 0.307
    ImageDraw.Draw(eye_glow).ellipse([ex - W * 0.04, ey - W * 0.045, ex + W * 0.04, ey + W * 0.045], fill=(111, 211, 255, 90))
eye_glow = eye_glow.filter(ImageFilter.GaussianBlur(W * 0.015))
img.paste(fig, (0, 0), fig)
img.paste(eye_glow, (0, 0), eye_glow)

# Floating motes.
motes = Image.new('RGBA', (W, W), (0, 0, 0, 0))
M = ImageDraw.Draw(motes)
for (x, y, r) in [(0.28, 0.32, 0.008), (0.73, 0.27, 0.006), (0.66, 0.46, 0.005), (0.33, 0.52, 0.006), (0.78, 0.52, 0.004)]:
    M.ellipse([W * (x - r), W * (y - r), W * (x + r), W * (y + r)], fill=(170, 240, 255, 230))
motes2 = motes.filter(ImageFilter.GaussianBlur(W * 0.006))
img.paste(motes2, (0, 0), motes2)
img.paste(motes, (0, 0), motes)

img = img.resize((S, S), Image.LANCZOS)

root = os.path.join(os.path.dirname(__file__), '..', 'Tinyfolk', 'Assets.xcassets')
icon_dir = os.path.join(root, 'AppIcon.appiconset')
os.makedirs(icon_dir, exist_ok=True)
img.save(os.path.join(icon_dir, 'icon-1024.png'))
json.dump({"images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
           "info": {"author": "xcode", "version": 1}}, open(os.path.join(icon_dir, 'Contents.json'), 'w'), indent=2)
json.dump({"info": {"author": "xcode", "version": 1}}, open(os.path.join(root, 'Contents.json'), 'w'), indent=2)


def colorset(name, light, dark):
    p = os.path.join(root, name + '.colorset')
    os.makedirs(p, exist_ok=True)

    def comp(c):
        return {"color-space": "srgb", "components": {"red": f"{c[0]:.3f}", "green": f"{c[1]:.3f}", "blue": f"{c[2]:.3f}", "alpha": "1.000"}}
    json.dump({"colors": [{"idiom": "universal", "color": comp(light)},
                          {"idiom": "universal", "appearances": [{"appearance": "luminosity", "value": "dark"}], "color": comp(dark)}],
               "info": {"author": "xcode", "version": 1}}, open(os.path.join(p, 'Contents.json'), 'w'), indent=2)


colorset('AccentColor', (0.10, 0.62, 0.80), (0.42, 0.85, 1.0))
colorset('LaunchColor', (0.02, 0.03, 0.06), (0.02, 0.03, 0.06))
os.makedirs(os.path.join(os.path.dirname(__file__), '..', 'docs'), exist_ok=True)
img.resize((256, 256), Image.LANCZOS).save(os.path.join(os.path.dirname(__file__), '..', 'docs', 'icon.png'))
print('icon written')
