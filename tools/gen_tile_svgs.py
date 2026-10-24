"""Generates the tile artwork in assets/tiles/*.svg. Edit this script (or replace any SVG by hand) to restyle the tiles.

Every tile is 60x84. flutter_svg cannot draw <text>, so characters (1-9 万, winds, dragons, flower names) are
drawn by the app on top of: base.svg (the tile body) and the pip artwork made here (dots, bamboo, flowers).
Run:  python tools/gen_tile_svgs.py
"""
import os

OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'tiles')
os.makedirs(OUT, exist_ok=True)

RED, BLUE, GREEN, DARK = '#C62828', '#1565C0', '#2E7D32', '#263238'
W, H = 60, 84


def svg(body, name):
    with open(os.path.join(OUT, name + '.svg'), 'w', encoding='utf8') as f:
        f.write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}">{body}</svg>\n')


def tile_body():
    return ('<rect x="1.5" y="4" width="57" height="78" rx="9" fill="#C9B98A"/>'  # thickness
            '<rect x="1.5" y="1.5" width="57" height="77" rx="9" fill="#FFFDF5" stroke="#9E9171" stroke-width="1.5"/>'
            '<rect x="5" y="5" width="50" height="70" rx="6" fill="none" stroke="#EFE6C8" stroke-width="1"/>')


svg(tile_body(), 'base')
svg('<rect x="1.5" y="4" width="57" height="78" rx="9" fill="#0B4F3A"/><rect x="1.5" y="1.5" width="57" height="77" rx="9" fill="#0F7A57" stroke="#0B4F3A" stroke-width="1.5"/><rect x="8" y="8" width="44" height="64" rx="5" fill="none" stroke="#7FD1B0" stroke-width="1.5"/>', 'back')

# ---------------------------------------------------------------- dots (筒)
def dot(x, y, r, c):
    return (f'<circle cx="{x}" cy="{y}" r="{r}" fill="{c}"/><circle cx="{x}" cy="{y}" r="{r*0.62:.1f}" fill="#FFFDF5"/>'
            f'<circle cx="{x}" cy="{y}" r="{r*0.38:.1f}" fill="{c}"/>')

DOTS = {
    1: [(30, 42, 17, RED)],
    2: [(30, 24, 9, GREEN), (30, 60, 9, BLUE)],
    3: [(17, 16, 8, BLUE), (30, 42, 8, RED), (43, 68, 8, GREEN)],
    4: [(19, 24, 8, BLUE), (41, 24, 8, GREEN), (19, 60, 8, GREEN), (41, 60, 8, BLUE)],
    5: [(18, 20, 7.5, BLUE), (42, 20, 7.5, GREEN), (30, 42, 8, RED), (18, 64, 7.5, GREEN), (42, 64, 7.5, BLUE)],
    6: [(19, 20, 7.5, GREEN), (41, 20, 7.5, GREEN), (19, 42, 7.5, RED), (41, 42, 7.5, RED), (19, 64, 7.5, RED), (41, 64, 7.5, RED)],
    7: [(14, 12, 6, GREEN), (30, 20, 6, GREEN), (46, 28, 6, GREEN), (19, 50, 7, RED), (41, 50, 7, RED), (19, 69, 7, RED), (41, 69, 7, RED)],
    8: [(19, y, 6.3, BLUE) for y in (14, 31, 48, 65)] + [(41, y, 6.3, BLUE) for y in (14, 31, 48, 65)],
    9: [(x, y, 6.5, c) for x, c in ((14, GREEN), (30, RED), (46, BLUE)) for y in (18, 42, 66)],
}
for n, pips in DOTS.items():
    svg(''.join(dot(*p) for p in pips), f'p{n}')

# ---------------------------------------------------------------- bamboo (索)
def stick(x, y, h, c, w=10):
    return (f'<rect x="{x - w/2}" y="{y}" width="{w}" height="{h}" rx="3" fill="{c}"/>'
            f'<rect x="{x - w/2 - 1}" y="{y + h/2 - 1.2}" width="{w + 2}" height="2.4" rx="1.2" fill="#FFFDF5"/>'
            f'<rect x="{x - 1}" y="{y + 3}" width="2" height="{h/2 - 6}" rx="1" fill="#FFFFFF" opacity=".35"/>')

def sticks(cols, rows, c_for=lambda i, j: GREEN, h=None, top=None):
    h = h or (60 / rows - 3)
    y0 = top if top is not None else (84 - (rows * h + (rows - 1) * 4)) / 2
    return ''.join(stick(x, y0 + j * (h + 4), h, c_for(i, j)) for j in range(rows) for i, x in enumerate(cols))

BIRD = (f'<ellipse cx="30" cy="48" rx="13" ry="16" fill="{GREEN}"/><circle cx="30" cy="26" r="9" fill="{GREEN}"/>'
        f'<path d="M37 24 l11 3 -11 4z" fill="{RED}"/><circle cx="33" cy="24" r="1.8" fill="#FFFDF5"/>'
        f'<path d="M26 60 q-10 12 -16 14 q12 2 20 -6z M34 60 q10 12 16 14 q-12 2 -20 -6z" fill="{BLUE}"/>'
        f'<path d="M20 44 q10 -8 20 0 q-10 10 -20 0z" fill="{RED}" opacity=".85"/>')
svg(BIRD, 's1')
svg(sticks([30], 2), 's2')
svg(stick(30, 10, 28, GREEN) + stick(19, 46, 28, GREEN) + stick(41, 46, 28, GREEN), 's3')
svg(sticks([19, 41], 2), 's4')
svg(sticks([17, 43], 2) + stick(30, 28, 28, RED), 's5')
svg(sticks([17, 30, 43], 2), 's6')
svg(stick(30, 6, 24, RED) + sticks([17, 30, 43], 2, h=22, top=36), 's7')
svg(sticks([19, 41], 4, h=14), 's8')
svg(sticks([17, 30, 43], 3, c_for=lambda i, j: (GREEN, RED, BLUE)[i], h=17), 's9')

# ---------------------------------------------------------------- flowers & seasons (the glyph is added by the app)
FLOWER_C = ['#AD1457', '#6A1B9A', '#F9A825', '#2E7D32']
SEASON_C = ['#43A047', '#E53935', '#EF6C00', '#1E88E5']

def blossom(cx, cy, c):
    petals = ''.join(f'<ellipse cx="{cx}" cy="{cy - 11}" rx="6" ry="9" fill="{c}" opacity=".85" transform="rotate({a} {cx} {cy})"/>' for a in range(0, 360, 72))
    return petals + f'<circle cx="{cx}" cy="{cy}" r="5" fill="#FFD54F"/>'

for i, c in enumerate(FLOWER_C, 1):
    svg(blossom(30, 28, c), f'f{i}')
for i, c in enumerate(SEASON_C, 1):
    svg(f'<circle cx="30" cy="28" r="15" fill="{c}" opacity=".9"/><circle cx="30" cy="28" r="10" fill="#FFFDF5" opacity=".9"/>'
        f'<circle cx="30" cy="28" r="5" fill="{c}"/>', f'k{i}')

# ---------------------------------------------------------------- dragons (frame for 白; glyphs are drawn by the app)
svg('<rect x="13" y="14" width="34" height="56" rx="3" fill="none" stroke="#1565C0" stroke-width="4"/>'
    '<rect x="19" y="20" width="22" height="44" rx="1" fill="none" stroke="#1565C0" stroke-width="1.5"/>', 'd3')
print('wrote', len(os.listdir(OUT)), 'svg files to', os.path.abspath(OUT))
