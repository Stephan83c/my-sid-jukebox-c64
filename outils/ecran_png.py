# Reconstitue l'écran de My SID Jukebox (écran $CC00, couleurs $D800) en PNG, avec la police du programme
# (police du C64 minuscules + logo + barre de progression, refaits ici depuis big.inc) : python3 ecran_png.py sortie.png
import sys, re, urllib.request
from pathlib import Path
from PIL import Image
U = 'http://192.168.1.27/v1/machine:readmem?address=%04X&length=%d'
def mem(a, n): return urllib.request.urlopen(U % (a, n), timeout=10).read()
scr, col = mem(0xCC00, 1000), mem(0xD800, 1000)
rom = (Path.home() / '.local/share/vice/C64/chargen-901225-01.bin').read_bytes()[0x800:0x1000]
font = bytearray(rom)
src = Path(__file__).resolve().parent.parent / 'src'
big = [int(v, 16) for v in re.findall(r'\$([0-9A-F]{2})', (src / 'big.inc').read_text().split('big_map:')[0])]
n = len(big) // 8
font[128 * 8:128 * 8 + len(big)] = bytes(big)
for g in range(9):            # barre de progression (même formule que bar_chars)
    for r in range(8):
        font[(128 + n + g) * 8 + r] = (((0xFF00 >> g) & 0xFF) if 1 <= r <= 6 else 0) | (0xFF if r in (3, 4) else 0)
pal = [(0,0,0),(255,255,255),(136,57,50),(103,182,189),(139,63,150),(85,160,73),(64,49,141),(191,206,114),
       (139,84,41),(87,66,0),(184,105,98),(80,80,80),(120,120,120),(148,224,137),(120,105,196),(159,159,159)]
vic = mem(0xD020, 2)
im = Image.new('RGB', (384, 272), pal[vic[0] & 15])
px = im.load()
for y in range(200):
    for x in range(320): px[32 + x, 36 + y] = pal[vic[1] & 15]
for i in range(1000):
    cx, cy, c = i % 40, i // 40, scr[i]
    fg = pal[col[i] & 15]
    for y in range(8):
        b = font[c * 8 + y]
        for x in range(8):
            if b & (0x80 >> x): px[32 + cx * 8 + x, 36 + cy * 8 + y] = fg
im.resize((768, 544), Image.NEAREST).save(sys.argv[1])
