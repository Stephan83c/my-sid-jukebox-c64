#!/usr/bin/env python3
"""Génère src/big.inc (données) et src/big_size.inc (dimensions, importé en tête) : le logo de My SID Jukebox, dans le style exact du logo de l'appli (make_logo.py) : la police du C64 (c64/chargen_set1.bin)
agrandie, chaque point devenant un bloc de 2 x 3 pixels (lettres de 16 x 24 pixels = 2 colonnes x 3 lignes).
Cases découpées en caractères 8 x 8 (codes 128 et suivants, doublons fusionnés ; case vide = espace).

    outils/mkbig.py [--texte "SID JUKEBOX 2.0"]

Fichiers générés dans le dépôt (l'assemblage n'a pas besoin de cet outil).
"""
import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# police du C64 (jeu 1), extraite de VICE par le jukebox en ligne (c64/tools/dump_chargen.py) : non redistribuée
ROM = (Path.home() / "Projet_C64/SidJukebox_C64/jukebox/c64/chargen_set1.bin").read_bytes()


def screen_code(ch):
    return ord(ch) - 64 if "A" <= ch <= "Z" else ord(ch)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--texte", default="MY SID JUKEBOX")
    a = ap.parse_args()
    cols = 2 * len(a.texte)
    if cols > 40:
        raise SystemExit("texte trop long : %d colonnes" % cols)
    px = [[0] * (cols * 8) for _ in range(24)]          # 3 lignes de caractères
    for i, ch in enumerate(a.texte):
        g = ROM[screen_code(ch) * 8: screen_code(ch) * 8 + 8]
        for y in range(24):
            for x in range(16):
                px[y][i * 16 + x] = (g[y // 3] >> (7 - x // 2)) & 1
    chars, index, grid = [], {}, []
    for cy in range(3):
        row = []
        for cx in range(cols):
            cell = tuple(sum(px[cy * 8 + y][cx * 8 + x] << (7 - x) for x in range(8)) for y in range(8))
            if not any(cell):
                row.append(32)
                continue
            if cell not in index:
                index[cell] = 128 + len(chars)
                chars.append(cell)
            row.append(index[cell])
        grid.append(row)
    if len(chars) > 64:
        raise SystemExit("trop de caractères différents : %d (64 au plus)" % len(chars))
    head = "// généré par outils/mkbig.py (texte %r, style du logo : police du C64 agrandie 2 x 3) : ne pas modifier" % a.texte
    (ROOT / "src" / "big_size.inc").write_text("\n".join([head, ".const BIG_W = %d" % cols, ".const BIG_H = 3",
                                                         ".const BIG_N = %d" % len(chars)]) + "\n")
    out = [head, "big_chars:"]
    out += ["        .byte " + ", ".join("$%02X" % v for v in c) for c in chars]
    out.append("big_map:")
    out += ["        .byte " + ", ".join("$%02X" % v for v in row) for row in grid]
    (ROOT / "src" / "big.inc").write_text("\n".join(out) + "\n")
    print("%d colonnes, %d caractères" % (cols, len(chars)))


if __name__ == "__main__":
    main()
