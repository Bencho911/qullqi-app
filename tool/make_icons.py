"""Genera los íconos de la app (iOS y Android) con el símbolo de Inti.

Uso:  python tool/make_icons.py   (requiere Pillow)

Mismo dibujo que `IntiMark` en lib/core/widgets/inti_logo.dart: disco con
ocho rayos sobre verde profundo.
"""
import json
import math
import pathlib

from PIL import Image, ImageDraw

BG = (0x0B, 0x2A, 0x1F)
RAY = (0x3C, 0xC5, 0x94)
DISC = (0x7F, 0xE3, 0xB8)
ROOT = pathlib.Path(__file__).resolve().parent.parent
SS = 4  # supersampling


def render(px: int, rounded: bool) -> Image.Image:
    n = px * SS
    img = Image.new('RGBA', (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if rounded:
        d.rounded_rectangle([0, 0, n - 1, n - 1], radius=n * 0.3, fill=BG)
    else:
        d.rectangle([0, 0, n, n], fill=BG)
    c = n / 2
    w = n * 0.075
    for i in range(8):
        a = i * math.pi / 4
        x0, y0 = c + math.cos(a) * n * 0.29, c + math.sin(a) * n * 0.29
        x1, y1 = c + math.cos(a) * n * 0.39, c + math.sin(a) * n * 0.39
        d.line([(x0, y0), (x1, y1)], fill=RAY, width=round(w))
        for x, y in ((x0, y0), (x1, y1)):
            d.ellipse([x - w / 2, y - w / 2, x + w / 2, y + w / 2], fill=RAY)
    r = n * 0.19
    d.ellipse([c - r, c - r, c + r, c + r], fill=DISC)
    out = img.resize((px, px), Image.LANCZOS)
    if not rounded:
        out = out.convert('RGB')  # iOS exige ícono opaco y sin esquinas
    return out


def main() -> None:
    ios = ROOT / 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
    contents = json.loads((ios / 'Contents.json').read_text(encoding='utf-8'))
    done = set()
    for item in contents['images']:
        name = item.get('filename')
        if not name or name in done:
            continue
        size = float(item['size'].split('x')[0])
        scale = int(item['scale'].rstrip('x'))
        render(round(size * scale), rounded=False).save(ios / name)
        done.add(name)
    sizes = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
    for dens, px in sizes.items():
        target = ROOT / f'android/app/src/main/res/mipmap-{dens}/ic_launcher.png'
        render(px, rounded=True).save(target)
    print(f'iOS: {len(done)} íconos; Android: {len(sizes)} íconos')


if __name__ == '__main__':
    main()
