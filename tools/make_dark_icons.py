#!/usr/bin/env python3
# Dark Icons (3.0.9.13, mockup A102): one picture per Icon Shape and edge thickness, laid over an icon
# (SetAllPoints on it, so it follows any size): a solid black edge k/64 of the icon wide, following the
# shape, and inside it a slight dark vignette (55% black at the edge, gone a quarter of the way in; a
# square's corners a little darker, as two edges meet). Rounded and Circle take their outline from
# Mask_Rounded / Mask_Circle, so the edge covers exactly where the masked icon ends.
#   Media/Textures/Dark_<Square|Rounded|Circle>_<k>.tga, 128 x 128, k = 5, 6, 7
# Run from the repo root: python3 tools/make_dark_icons.py
import os

import numpy as np
from PIL import Image

OUT = os.path.join("Media", "Textures")
SIZE, SS = 128, 4             # final size, supersampling
VIG_A, VIG_W = 0.55, 0.24     # the vignette: alpha at its edge, width (part of the inside)
KS = (5, 6, 7)                # edge thickness in 64ths of the icon


def mask_alpha(name, n):
    a = Image.open(os.path.join(OUT, name + ".tga")).convert("RGBA").split()[3]
    return np.asarray(a.resize((n, n), Image.LANCZOS), dtype=np.float64) / 255.0


def make(shape, k):
    n = SIZE * SS
    c = (np.arange(n) + 0.5) / n          # pixel centers, 0..1
    x, y = np.meshgrid(c, c)
    band = k / 64.0                        # the black edge, part of the icon
    inner = 1.0 - 2 * band                 # the inside's width
    w = VIG_W * inner                      # how far in the vignette reaches
    if shape == "Circle":
        r = np.hypot(x - 0.5, y - 0.5)
        d = (0.5 - band) - r               # distance in from the edge's inside
        vig = VIG_A * np.clip(1 - d / w, 0, 1)
        a = np.where(d < 0, 1.0, vig)
        a = a * mask_alpha("Mask_Circle", n)
    else:
        dx = np.minimum(x, 1 - x) - band
        dy = np.minimum(y, 1 - y) - band
        ax = VIG_A * np.clip(1 - dx / w, 0, 1)
        ay = VIG_A * np.clip(1 - dy / w, 0, 1)
        vig = 1 - (1 - ax) * (1 - ay)
        edge = (dx < 0) | (dy < 0)
        if shape == "Rounded":
            # the corners: the edge follows the mask's quarter circles (radius 48/256 of the icon)
            rad = 48 / 256.0
            cx = np.clip(x, rad, 1 - rad)
            cy = np.clip(y, rad, 1 - rad)
            dist = rad - np.hypot(x - cx, y - cy)   # distance in from the rounded outline (corners)
            edge = edge | (dist < band)
        a = np.where(edge, 1.0, vig)
        if shape == "Rounded":
            a = a * mask_alpha("Mask_Rounded", n)
    img = np.zeros((n, n, 4), dtype=np.uint8)
    img[..., 3] = np.round(np.clip(a, 0, 1) * 255).astype(np.uint8)
    im = Image.fromarray(img, "RGBA").resize((SIZE, SIZE), Image.LANCZOS)
    # premultiplied black: keep the color channels black under every alpha
    r, g, b, al = im.split()
    im = Image.merge("RGBA", (r.point(lambda v: 0), g.point(lambda v: 0), b.point(lambda v: 0), al))
    path = os.path.join(OUT, "Dark_%s_%d.tga" % (shape, k))
    im.save(path)
    return path


if __name__ == "__main__":
    for shape in ("Square", "Rounded", "Circle"):
        for k in KS:
            print(make(shape, k))
