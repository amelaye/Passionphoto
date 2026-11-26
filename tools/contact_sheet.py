#!/usr/bin/env python3
"""Planche contact de PNG (Python pur, réutilise tools/pixelart.py) : comparer des rendus d'un coup d'œil.

  python3 -I tools/contact_sheet.py SORTIE.png [--cols N] [--scale K] IMAGE.png...

Les images sont rangées en grille (ordre donné, N par ligne), agrandies ×K au plus proche voisin, séparées par un
liseré sombre. Pas d'étiquettes : l'ordre des fichiers fait foi (le dire dans le compte rendu).
Sortie conseillée : .cache/previews/ (ignoré par git).
"""
import argparse
import importlib.util
import os

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("pixelart", os.path.join(HERE, "pixelart.py"))
pixelart = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pixelart)

GAP, BG = 4, (30, 30, 30, 255)


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("out")
    p.add_argument("images", nargs="+")
    p.add_argument("--cols", type=int, default=4)
    p.add_argument("--scale", type=int, default=1)
    a = p.parse_args()
    imgs = []
    for path in a.images:
        w, h, px = pixelart.png_read(path)
        if a.scale > 1:
            px = [[c for c in row for _ in range(a.scale)] for row in px for _ in range(a.scale)]
            w, h = w * a.scale, h * a.scale
        imgs.append((w, h, px))
    cw = max(i[0] for i in imgs)
    ch = max(i[1] for i in imgs)
    cols = max(1, min(a.cols, len(imgs)))
    nrows = (len(imgs) + cols - 1) // cols
    width = cols * cw + (cols + 1) * GAP
    height = nrows * ch + (nrows + 1) * GAP
    canvas = [[BG] * width for _ in range(height)]
    for k, (w, h, px) in enumerate(imgs):
        ox = GAP + (k % cols) * (cw + GAP)
        oy = GAP + (k // cols) * (ch + GAP)
        for y in range(h):
            canvas[oy + y][ox:ox + w] = px[y]
    pixelart.png_write(a.out, width, height, canvas)
    print(a.out)


if __name__ == "__main__":
    main()
