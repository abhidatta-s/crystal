# Rebuilds Resources/AppIcon-1024.png from the tile render (box only: needs Pillow + numpy).
# Usage: python3 tools/make-icon.py source.jpg [out.png]
import numpy as np
from PIL import Image, ImageFilter

import sys
SRC = sys.argv[1]  # the 1280x720 tile render
CANVAS, TILE, RADIUS = 1024, 824, 185
SS = 4  # supersampling for the mask edge

# Painted tile bounds in the 1280x720 source (measured from edge profiles).
L, T, R, B = 385, 84, 893, 592
BLEED = 5  # px (at 824 scale) of the painted rim pushed outside the mask, so no grey background survives

src = Image.open(SRC).convert('RGB')
scaled = TILE + 2 * BLEED
tile = src.crop((L, T, R, B)).resize((scaled, scaled), Image.LANCZOS).crop((BLEED, BLEED, BLEED + TILE, BLEED + TILE))

# Continuous-corner (squircle-style) rounded rect: corners are superellipse
# quadrants spanning ~1.5x the nominal radius, like Apple's smoothed corners.
def continuous_mask(size, radius, ss):
    n = size * ss
    E = radius * 1.52 * ss
    p = 3.6
    yy, xx = np.mgrid[0:n, 0:n].astype(np.float64) + 0.5
    dx = np.maximum(np.maximum(E - xx, xx - (n - E)), 0) / E
    dy = np.maximum(np.maximum(E - yy, yy - (n - E)), 0) / E
    inside = (dx ** p + dy ** p) <= 1.0
    m = Image.fromarray((inside * 255).astype(np.uint8))
    return m.resize((size, size), Image.LANCZOS)

mask = continuous_mask(TILE, RADIUS, SS)

off = (CANVAS - TILE) // 2
canvas = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))

# Soft drop shadow, fully transparent background.
shadow_alpha = Image.new('L', (CANVAS, CANVAS), 0)
shadow_alpha.paste(mask, (off, off + 14))
shadow_alpha = shadow_alpha.filter(ImageFilter.GaussianBlur(18)).point(lambda a: int(a * 0.30))
shadow = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 255))
shadow.putalpha(shadow_alpha)
canvas = Image.alpha_composite(canvas, shadow)

tile_rgba = tile.convert('RGBA')
tile_rgba.putalpha(mask)
layer = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
layer.paste(tile_rgba, (off, off))
canvas = Image.alpha_composite(canvas, layer)
canvas.save(sys.argv[2] if len(sys.argv) > 2 else 'Resources/AppIcon-1024.png', optimize=True)
raise SystemExit(0)  # previews below are for development only

# Previews for checking: on dark and on light, plus a zoomed corner.
for name, color in (('dark', (30, 30, 34, 255)), ('light', (250, 250, 250, 255))):
    bg = Image.new('RGBA', (CANVAS, CANVAS), color)
    Image.alpha_composite(bg, canvas).convert('RGB').resize((512, 512), Image.LANCZOS).save(f'/tmp/preview-{name}.png')
bg = Image.new('RGBA', (CANVAS, CANVAS), (30, 30, 34, 255))
Image.alpha_composite(bg, canvas).crop((80, 80, 380, 380)).resize((600, 600), Image.NEAREST).save('/tmp/preview-corner.png')
a = np.array(canvas)[:, :, 3]
print('corner px alpha', a[0, 0], a[100, 100], 'centre', a[512, 512], 'size', canvas.size, canvas.mode)
