#!/usr/bin/env python3
"""Tharok UI - genere les textures de pinceau (TGA 32 bits, sans dependance).

    python3 generate_brush.py            ecrit les .tga a cote de ce script
    python3 generate_brush.py apercu.png ecrit aussi un apercu compose

Textures :
    brush-wash        512x512  lavis brosse, repetable dans les deux sens
    brush-stroke      256x32   trait de pinceau sec (filets, accents, marques)
    brush-edge-left   32x512   bord effiloche (fins de coups de pinceau), repetable en hauteur
    brush-edge-right  32x512   le meme, en miroir
    brush-edge-top    512x32   bord superieur irregulier, repetable en largeur
    brush-bar         256x32   remplissage brosse des barres
"""

import math
import os
import random
import struct
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))


def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def lerp(a, b, t):
    return a + (b - a) * t


class Noise:
    """Bruit de valeur periodique (periodes entieres px, py)."""

    def __init__(self, px, py, seed):
        rng = random.Random(seed)
        self.px, self.py = px, py
        self.grid = [[rng.random() for _ in range(px)] for _ in range(py)]

    def __call__(self, x, y):
        x0, y0 = math.floor(x), math.floor(y)
        fx, fy = x - x0, y - y0
        fx = fx * fx * (3 - 2 * fx)
        fy = fy * fy * (3 - 2 * fy)
        g, px, py = self.grid, self.px, self.py
        r0, r1 = g[y0 % py], g[(y0 + 1) % py]
        a, b = r0[x0 % px], r0[(x0 + 1) % px]
        c, d = r1[x0 % px], r1[(x0 + 1) % px]
        return lerp(lerp(a, b, fx), lerp(c, d, fx), fy)


class Image:
    """Pixels (r, g, b, a) en flottants 0..1."""

    def __init__(self, w, h, fn):
        self.w, self.h = w, h
        self.px = [[fn(x, y) for x in range(w)] for y in range(h)]

    def mirrored(self):
        img = Image.__new__(Image)
        img.w, img.h = self.w, self.h
        img.px = [list(reversed(row)) for row in self.px]
        return img

    def write_tga(self, name):
        header = struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, self.w, self.h, 32, 0x28)
        body = bytearray()
        for row in self.px:
            for r, g, b, a in row:
                body += bytes((int(clamp(b) * 255 + 0.5), int(clamp(g) * 255 + 0.5),
                               int(clamp(r) * 255 + 0.5), int(clamp(a) * 255 + 0.5)))
        with open(os.path.join(HERE, name + ".tga"), "wb") as f:
            f.write(header + body)

    def sample(self, u, v, wrap_u=False, wrap_v=False):
        """Echantillon bilineaire, u et v en 0..1."""
        x, y = u * self.w - 0.5, v * self.h - 0.5
        x0, y0 = math.floor(x), math.floor(y)
        fx, fy = x - x0, y - y0

        def at(ix, iy):
            ix = ix % self.w if wrap_u else min(max(ix, 0), self.w - 1)
            iy = iy % self.h if wrap_v else min(max(iy, 0), self.h - 1)
            return self.px[iy][ix]

        a, b, c, d = at(x0, y0), at(x0 + 1, y0), at(x0, y0 + 1), at(x0 + 1, y0 + 1)
        return tuple(lerp(lerp(a[i], b[i], fx), lerp(c[i], d[i], fx), fy) for i in range(4))


# -----------------------------------------------------------------------------
# Lavis brosse : stries horizontales claires (blanc) et denses (noir), a poser
# en fusion normale. Le noir epaissit la peinture, le blanc accroche la lumiere.
# -----------------------------------------------------------------------------

def make_wash():
    size = 512
    warp = Noise(3, 3, 11)
    fine = Noise(4, 64, 12)
    medium = Noise(3, 22, 13)
    broad = Noise(2, 5, 14)
    patch = Noise(4, 5, 15)

    def pixel(x, y):
        u, v = x / size, y / size
        # Les coups de pinceau ondulent legerement au lieu de filer droit.
        v += (warp(u * 3, v * 3) - 0.5) * 0.05
        s = (fine(u * 4, v * 64) - 0.5) * 0.6
        s += (medium(u * 3, v * 22) - 0.5) * 1.2
        s += (broad(u * 2, v * 5) - 0.5) * 1.4
        s *= 1.7
        # Zones plus ou moins chargees en peinture.
        load = 0.45 + 0.75 * patch(u * 4, v * 5)
        strength = clamp(abs(s)) ** 1.25 * load
        if s > 0:
            return (1, 1, 1, clamp(strength * 0.11))
        return (0, 0, 0, clamp(strength))

    return Image(size, size, pixel)


# -----------------------------------------------------------------------------
# Trait de pinceau sec : attaque nette a gauche, fin qui s'effiloche a droite.
# -----------------------------------------------------------------------------

def make_stroke():
    w, h = 256, 32
    rng = random.Random(21)
    rows = []
    for y in range(h):
        t = abs((y - (h - 1) / 2) / (h / 2))
        rows.append({
            "start": 3 + 16 * t * rng.random() + 5 * rng.random(),
            "end": w - (5 + 70 * rng.random() * (0.25 + t)),
            "gain": 0.6 + 0.4 * rng.random(),
        })
    width = Noise(6, 1, 22)
    wobble = Noise(4, 1, 25)
    streak = Noise(4, 64, 23)
    dry = Noise(14, 64, 24)

    def pixel(x, y):
        row = rows[y]
        # La ligne mediane ondule et la pression retombe vers la fin du geste.
        center = (h - 1) / 2 + (wobble(x * 4 / w, 0) - 0.5) * 7
        t = abs((y - center) / (h / 2))
        half = (0.60 - 0.22 * x / w) + 0.30 * (width(x * 6 / w, 0) - 0.5)
        across = clamp((half - t) / 0.16)
        attack = clamp((x - row["start"]) / 5)
        tail = clamp((row["end"] - x) / 46)
        # En fin de course le pinceau se vide : les poils laissent des manques.
        gaps = clamp(tail * 2.2 + (dry(x * 14 / w, y * 1.4) - 0.5) * 1.5)
        body = 0.72 + 0.28 * streak(x * 4 / w, y * 0.9)
        alpha = across * attack * clamp(tail * 3) * gaps * body * row["gain"]
        return (1, 1, 1, clamp(alpha * 1.25))

    return Image(w, h, pixel)


# -----------------------------------------------------------------------------
# Bords : la peinture du panneau deborde et s'effiloche.
# -----------------------------------------------------------------------------

def make_edge_left():
    """Plein a droite, fins de coups de pinceau vers la gauche."""
    w, h = 32, 512
    low = Noise(1, 7, 31)
    mid = Noise(1, 26, 32)
    high = Noise(1, 96, 33)
    hair = Noise(1, 200, 35)
    dry = Noise(3, 128, 34)

    def pixel(x, y):
        v = y / h
        # Touffes de poils : quelques meches partent nettement plus loin.
        reach = 0.10 + 0.26 * low(0, v * 7) + 0.22 * mid(0, v * 26)
        reach += 0.55 * high(0, v * 96) ** 2.4 + 0.30 * hair(0, v * 200) ** 3
        tip = w * (1 - clamp(reach, 0.08, 0.97))
        d = x + 0.5 - tip
        alpha = clamp(d / 2.5)
        # Pointes seches : la matiere se troue pres de l'extremite.
        hole = clamp((dry(x * 3 / w, v * 128) - 0.5) * 4)
        alpha *= 1 - hole * clamp(1 - d / 13)
        # La derniere colonne rejoint le fond du panneau sans couture.
        alpha = max(alpha, clamp((x - (w - 4)) / 2))
        return (1, 1, 1, alpha)

    return Image(w, h, pixel)


def make_edge_top():
    """Plein en bas, flanc de coup de pinceau irregulier en haut."""
    w, h = 512, 32
    low = Noise(5, 1, 41)
    mid = Noise(19, 1, 42)
    high = Noise(70, 1, 43)
    streak = Noise(7, 64, 44)
    gap = Noise(9, 64, 45)

    def pixel(x, y):
        u = x / w
        reach = 0.22 + 0.30 * low(u * 5, 0) + 0.14 * mid(u * 19, 0) + 0.06 * high(u * 70, 0)
        tip = h * (1 - clamp(reach, 0.1, 0.9))
        d = y + 0.5 - tip
        alpha = clamp(d / 2.2)
        # Manques allonges juste sous le bord.
        hole = clamp((gap(u * 9, y * 0.8) - 0.56) * 6)
        alpha *= 1 - hole * clamp(1 - d / 9) * 0.85
        # Poils isoles qui tracent des filets au-dessus du bord.
        hair = clamp((streak(u * 7, y * 0.9 + 3) - 0.60) * 7) * clamp(1 + d / 10) * clamp(-d / 2 + 1.5)
        alpha = max(alpha, hair * 0.75)
        alpha = max(alpha, clamp((y - (h - 4)) / 2))
        return (1, 1, 1, alpha)

    return Image(w, h, pixel)


# -----------------------------------------------------------------------------
# Remplissage des barres : aplat legerement strie, a teinter.
# -----------------------------------------------------------------------------

def make_bar():
    w, h = 256, 32
    fine = Noise(4, 40, 51)
    broad = Noise(3, 6, 52)

    def pixel(x, y):
        s = 0.6 * fine(x * 4 / w, y * 1.25) + 0.4 * broad(x * 3 / w, y * 6 / h)
        lum = 0.88 + 0.12 * clamp((s - 0.2) / 0.6)
        return (lum, lum, lum, 1)

    return Image(w, h, pixel)


# -----------------------------------------------------------------------------
# Apercu : compose les textures comme le fera le jeu (verification a l'oeil).
# -----------------------------------------------------------------------------

def write_png(path, w, h, pixels):
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        for r, g, b in pixels[y]:
            raw += bytes((int(clamp(r) * 255), int(clamp(g) * 255), int(clamp(b) * 255)))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(bytes(raw), 6)))
        f.write(chunk(b"IEND", b""))


def preview(path, tex):
    W, H = 960, 600
    world = Noise(6, 5, 91)
    detail = Noise(40, 30, 92)
    canvas = []
    for y in range(H):
        row = []
        for x in range(W):
            n = world(x * 6 / W, y * 5 / H)
            k = 0.75 + 0.5 * detail(x * 40 / W, y * 30 / H)
            row.append([(0.16 + 0.25 * n) * k, (0.26 + 0.18 * (1 - n)) * k, (0.15 + 0.2 * n * n) * k])
        canvas.append(row)

    def blend(x, y, color, alpha):
        if 0 <= x < W and 0 <= y < H and alpha > 0:
            p = canvas[y][x]
            for i in range(3):
                p[i] = lerp(p[i], color[i], clamp(alpha))

    BG = (0.05, 0.05, 0.06)

    def rect(x0, y0, x1, y1, fn):
        for y in range(max(0, y0), min(H, y1)):
            for x in range(max(0, x0), min(W, x1)):
                color, alpha = fn(x, y, (x - x0 + 0.5) / (x1 - x0), (y - y0 + 0.5) / (y1 - y0))
                blend(x, y, color, alpha)

    def surface(x0, y0, x1, y1, alpha, frame=1.0):
        rect(x0, y0, x1, y1, lambda x, y, u, v: (BG, alpha * frame))
        rect(x0, y0, x1, y1, lambda x, y, u, v: ((1, 1, 1), 0.02 * (1 - v) * frame))

        def wash(x, y, u, v):
            p = tex["wash"].sample((x - x0) / 512, (y - y0) / 512, True, True)
            return p[:3], p[3] * 0.32 * frame

        rect(x0, y0, x1, y1, wash)

    def edge_left(x0, y0, y1, width, alpha, right=False):
        img = tex["edge-right" if right else "edge-left"]

        def fn(x, y, u, v):
            return BG, img.sample(u, (y - y0) / 512, False, True)[3] * alpha

        if right:
            rect(x0, y0, x0 + width, y1, fn)
        else:
            rect(x0 - width, y0, x0, y1, fn)

    def edge_top(x0, x1, y0, height, alpha):
        rect(x0, y0 - height, x1, y0,
             lambda x, y, u, v: (BG, tex["edge-top"].sample((x - x0) / 512, v, True, False)[3] * alpha))

    def stroke(x0, y0, x1, y1, color, alpha, vertical=False):
        def fn(x, y, u, v):
            p = tex["stroke"].sample(v, u) if vertical else tex["stroke"].sample(u, v)
            return color, p[3] * alpha

        rect(x0, y0, x1, y1, fn)

    accent = (0.78, 0.61, 0.43)
    frame = 0.75
    # Tiroir de droite.
    surface(770, 0, W, H, 0.85, frame)
    edge_left(770, 0, H, 18, 0.85 * frame)
    stroke(763, 0, 777, H, accent, 0.9 * frame, True)
    for y in (150, 330):
        stroke(778, y - 4, W - 8, y + 4, (1, 1, 1), 0.08)
    # Barres brossees.
    for i, (color, fill) in enumerate((((0.27, 0.78, 0.32), 0.8), ((0.30, 0.55, 1.0), 0.55))):
        y0 = 20 + i * 22
        rect(790, y0, 790 + int(150 * fill), y0 + 14,
             lambda x, y, u, v, c=color: (tuple(ch * tex["bar"].sample(u, v)[0] for ch in c), 1))
    # Poignee.
    stroke(752, 270, 768, 340, BG, 0.92, True)
    stroke(757, 280, 763, 330, accent, 0.9, True)
    # Tiroir du bas.
    surface(0, 470, 770, H, 0.85, frame)
    edge_top(0, 770, 470, 16, 0.85 * frame)
    stroke(0, 463, 770, 477, accent, 0.9 * frame)
    # Fenetre.
    surface(180, 90, 620, 390, 0.95)
    edge_left(180, 90, 390, 16, 0.95)
    edge_left(620, 90, 390, 16, 0.95, True)
    stroke(180, 83, 620, 97, accent, 0.9)
    stroke(192, 150, 322, 174, accent, 0.32)
    stroke(350, 156, 608, 168, accent, 0.9)
    write_png(path, W, H, canvas)


def main():
    tex = {
        "wash": make_wash(),
        "stroke": make_stroke(),
        "edge-left": make_edge_left(),
        "edge-top": make_edge_top(),
        "bar": make_bar(),
    }
    tex["edge-right"] = tex["edge-left"].mirrored()
    for name, image in tex.items():
        image.write_tga("brush-" + name)
    if len(sys.argv) > 1:
        preview(sys.argv[1], tex)


if __name__ == "__main__":
    main()
