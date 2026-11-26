#!/usr/bin/env python3
"""Génère les PNG de test du décodeur Lua (src/lib/png.lua) : tests/unit/fixtures/png/*.png + expected.lua.

L'encodage est fait ici, indépendamment du décodeur (zlib de Python pour la compression) ; le résultat attendu est
connu par construction (pixels source convertis en RGBA 8 bits). Les cas couvrent les types de couleur 0/2/3/4/6,
les profondeurs 1/2/4/8/16, les palettes et tRNS, les 5 filtres, l'entrelacement Adam7, plusieurs blocs IDAT et les
trois types de blocs deflate (stocké, Huffman fixe, Huffman dynamique) ainsi que les copies qui se chevauchent (RLE).

  python3 -I tools/gen_png_fixtures.py      (déterministe : relancer donne les mêmes fichiers)
"""
import os
import random
import struct
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tests", "unit", "fixtures", "png")
CHANNELS = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}
ADAM7 = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]


def chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def pack_row(samples, depth):
    """samples : liste plate d'échantillons natifs d'une rangée -> octets de la rangée."""
    if depth == 8:
        return bytes(samples)
    if depth == 16:
        return b"".join(struct.pack(">H", s) for s in samples)
    out, acc, nbits = bytearray(), 0, 0
    for s in samples:
        acc = (acc << depth) | s
        nbits += depth
        if nbits == 8:
            out.append(acc)
            acc, nbits = 0, 0
    if nbits:
        out.append(acc << (8 - nbits))
    return bytes(out)


def filter_rows(rows, bpp, ftypes):
    out, prev = bytearray(), bytes(len(rows[0])) if rows else b""
    for i, row in enumerate(rows):
        ft = ftypes[i % len(ftypes)]
        out.append(ft)
        for x in range(len(row)):
            a = row[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            pred = (0, a, b, (a + b) >> 1, paeth(a, b, c))[ft]
            out.append((row[x] - pred) & 255)
        prev = row
    return bytes(out)


def to8(v, depth):
    if depth == 16:
        return v >> 8
    if depth < 8:
        return v * 255 // ((1 << depth) - 1)
    return v


def expected_rgba(px, ctype, depth, plte, trns):
    if ctype == 0:
        g = to8(px[0], depth)
        return (g, g, g, 0 if trns is not None and px[0] == trns else 255)
    if ctype == 2:
        return tuple(to8(v, depth) for v in px) + (0 if trns is not None and tuple(px) == trns else 255,)
    if ctype == 3:
        r, g, b = plte[px[0]]
        a = trns[px[0]] if trns is not None and px[0] < len(trns) else 255
        return (r, g, b, a)
    if ctype == 4:
        g = to8(px[0], depth)
        return (g, g, g, to8(px[1], depth))
    return tuple(to8(v, depth) for v in px)


def make(name, w, h, ctype, depth, rng, ftypes=(0, 1, 2, 3, 4), interlace=0, level=9, strategy=None,
         split=None, plte_size=None, trns=False, smooth=False):
    ch = CHANNELS[ctype]
    maxv = (1 << depth) - 1
    plte, trns_val = None, None
    if ctype == 3:
        n = plte_size or (1 << depth)
        plte = [(rng.randrange(256), rng.randrange(256), rng.randrange(256)) for _ in range(n)]
        maxv = n - 1
    pixels = []
    for y in range(h):
        row = []
        for x in range(w):
            if smooth:  # dégradé + bruit léger : donne du Huffman dynamique avec de vraies répétitions
                base = [(x * 4 + y * 2 + k * 40) % (maxv + 1) for k in range(ch)]
                row.append([min(maxv, max(0, v + rng.randrange(-2, 3))) for v in base])
            else:
                row.append([rng.randrange(maxv + 1) for _ in range(ch)])
        pixels.append(row)
    if trns:
        if ctype == 0:
            trns_val = pixels[0][0][0]
        elif ctype == 2:
            trns_val = tuple(pixels[0][0])
        elif ctype == 3:
            trns_val = bytes(rng.randrange(256) for _ in range(max(1, len(plte) // 2)))
    bpp = max(1, ch * depth // 8)
    if interlace:
        raw = b""
        for x0, y0, dx, dy in ADAM7:
            pw, ph = (w - x0 + dx - 1) // dx, (h - y0 + dy - 1) // dy
            if pw <= 0 or ph <= 0:
                continue
            rows = [pack_row([s for x in range(x0, w, dx) for s in pixels[y][x]], depth) for y in range(y0, h, dy)]
            raw += filter_rows(rows, bpp, ftypes)
    else:
        rows = [pack_row([s for px in r for s in px], depth) for r in pixels]
        raw = filter_rows(rows, bpp, ftypes)
    if strategy is not None:
        co = zlib.compressobj(level, zlib.DEFLATED, 15, 9, strategy)
        comp = co.compress(raw) + co.flush()
    else:
        comp = zlib.compress(raw, level)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, depth, ctype, 0, 0, interlace))
    if plte:
        data += chunk(b"PLTE", b"".join(bytes(c) for c in plte))
    if trns_val is not None:
        if ctype == 0:
            data += chunk(b"tRNS", struct.pack(">H", trns_val))
        elif ctype == 2:
            data += chunk(b"tRNS", struct.pack(">HHH", *trns_val))
        else:
            data += chunk(b"tRNS", trns_val)
    pieces = [comp[i:i + split] for i in range(0, len(comp), split)] if split else [comp]
    for p in pieces:
        data += chunk(b"IDAT", p)
    data += chunk(b"IEND", b"")
    with open(os.path.join(OUT, name + ".png"), "wb") as f:
        f.write(data)
    rgba = bytearray()
    for r in pixels:
        for px in r:
            rgba += bytes(expected_rgba(px, ctype, depth, plte, trns_val))
    return {"file": name + ".png", "w": w, "h": h, "rgba": rgba.hex()}


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = random.Random(20261126)
    cases = [
        make("rgba8_filtres", 13, 7, 6, 8, rng),
        make("rgb8_trns", 9, 6, 2, 8, rng, ftypes=(4, 1), trns=True),
        make("rgb16", 5, 4, 2, 16, rng),
        make("gris8", 8, 8, 0, 8, rng, ftypes=(2, 3)),
        make("gris16_trns", 5, 5, 0, 16, rng, trns=True),
        make("gris1_trns", 13, 3, 0, 1, rng, trns=True),
        make("gris2", 7, 4, 0, 2, rng),
        make("gris4", 9, 5, 0, 4, rng),
        make("pal1", 11, 3, 3, 1, rng),
        make("pal2", 7, 5, 3, 2, rng, trns=True),
        make("pal4", 9, 7, 3, 4, rng, plte_size=11),
        make("pal8_trns", 9, 7, 3, 8, rng, plte_size=40, trns=True),
        make("gris_alpha8", 6, 6, 4, 8, rng),
        make("gris_alpha16", 4, 4, 4, 16, rng),
        make("rgba16", 5, 3, 6, 16, rng),
        make("rgba8_adam7", 11, 9, 6, 8, rng, interlace=1),
        make("pal4_adam7", 7, 5, 3, 4, rng, interlace=1, trns=True),
        make("gris1_adam7", 3, 2, 0, 1, rng, interlace=1),
        make("rgba8_stocke", 6, 5, 6, 8, rng, level=0),
        make("rgb8_fixe", 12, 8, 2, 8, rng, strategy=zlib.Z_FIXED),
        make("rgb8_rle", 16, 16, 2, 8, rng, strategy=zlib.Z_RLE, smooth=True),
        make("rgb8_dynamique_multi_idat", 64, 48, 2, 8, rng, level=6, split=500, smooth=True),
        make("rgba8_1x1", 1, 1, 6, 8, rng),
    ]
    lines = ["-- Généré par tools/gen_png_fixtures.py — ne pas modifier à la main.", "return {"]
    for c in cases:
        lines.append(f'\t{{ file = "{c["file"]}", w = {c["w"]}, h = {c["h"]}, rgba = "{c["rgba"]}" }},')
    lines.append("}")
    with open(os.path.join(OUT, "expected.lua"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"{len(cases)} PNG de test écrits dans {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
