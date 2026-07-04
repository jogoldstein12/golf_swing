#!/usr/bin/env python3
"""Render the Swing Through app icon.

Composition: bone canvas; the swing-plane disc as a tilted hairline ellipse in ink;
the downswing arc as a tapered fairway ribbon sweeping along the disc into the ball —
a bone dot ringed in ink at the low point. Three elements, no text.
Rendered 4x and downsampled for clean edges.
"""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 4096
OUT = 1024

BONE = (245, 243, 238)
INK = (25, 23, 18)
FAIRWAY = (143, 184, 15)       # deep fairway reads better at icon size
FAIRWAY_BRIGHT = (180, 224, 25)

img = Image.new("RGB", (S, S), BONE)
d = ImageDraw.Draw(img)

# Subtle vertical warmth: barely-there gradient so the canvas isn't flat.
top = (247, 245, 241)
for y in range(S):
    t = y / S
    c = tuple(int(top[i] + (BONE[i] - top[i]) * t) for i in range(3))
    d.line([(0, y), (S, y)], fill=c)

cx, cy = S * 0.50, S * 0.52
tilt = math.radians(-28)          # swing-plane tilt
rx, ry = S * 0.355, S * 0.16      # disc radii

def ellipse_pt(theta):
    """Point on the tilted ellipse. theta 0 = +x before tilt."""
    x = rx * math.cos(theta)
    y = ry * math.sin(theta)
    xr = x * math.cos(tilt) - y * math.sin(tilt)
    yr = x * math.sin(tilt) + y * math.cos(tilt)
    return (cx + xr, cy + yr)

# --- Plane disc: hairline ellipse, ink at low opacity (drawn as thin solid line)
disc = Image.new("RGBA", (S, S), (0, 0, 0, 0))
dd = ImageDraw.Draw(disc)
pts = [ellipse_pt(t / 400 * 2 * math.pi) for t in range(401)]
dd.line(pts, fill=(90, 84, 70, 90), width=int(S * 0.005), joint="curve")
img.paste(Image.alpha_composite(img.convert("RGBA"), disc).convert("RGB"), (0, 0))
d = ImageDraw.Draw(img)

# --- Fairway ribbon: sweep along the ellipse from high trail side down to the ball.
# Single flat color; width builds through the strike zone and releases to a point
# that meets the ball.
t0, t1 = math.radians(-50), math.radians(150)
N = 240
ribbon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
rd = ImageDraw.Draw(ribbon)
left_edge, right_edge = [], []
for i in range(N + 1):
    f = i / N
    theta = t0 + (t1 - t0) * f
    p = ellipse_pt(theta)
    # thin start, fullest ~60% through, tapering to a fine tip at the ball
    build = math.sin(math.pi * f) ** 1.1
    release = 1 - max(0, (f - 0.86) / 0.14) ** 1.6
    w = S * (0.010 + 0.056 * build) * max(release, 0.04)
    eps = 1e-3
    p2 = ellipse_pt(theta + eps)
    dx, dy = p2[0] - p[0], p2[1] - p[1]
    L = math.hypot(dx, dy) or 1
    nx, ny = -dy / L, dx / L
    left_edge.append((p[0] + nx * w / 2, p[1] + ny * w / 2))
    right_edge.append((p[0] - nx * w / 2, p[1] - ny * w / 2))
poly = left_edge + right_edge[::-1]
rd.polygon(poly, fill=FAIRWAY_BRIGHT + (255,))
img = Image.alpha_composite(img.convert("RGBA"), ribbon).convert("RGB")
d = ImageDraw.Draw(img)

# --- The ball: bone dot with ink ring just past the ribbon's tip
bx, by = ellipse_pt(t1 + math.radians(11))
r_ball = S * 0.058
ring = S * 0.013
# soft contact shadow
sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
sd = ImageDraw.Draw(sh)
sd.ellipse([bx - r_ball * 1.15, by + r_ball * 0.62, bx + r_ball * 1.15, by + r_ball * 1.38],
           fill=(25, 23, 18, 42))
sh = sh.filter(ImageFilter.GaussianBlur(S * 0.012))
img = Image.alpha_composite(img.convert("RGBA"), sh).convert("RGB")
d = ImageDraw.Draw(img)
d.ellipse([bx - r_ball, by - r_ball, bx + r_ball, by + r_ball], fill=(252, 251, 248), outline=INK, width=int(ring))

img = img.resize((OUT, OUT), Image.LANCZOS)
import sys
out = sys.argv[1] if len(sys.argv) > 1 else "icon.png"
img.save(out)
print("wrote", out)
