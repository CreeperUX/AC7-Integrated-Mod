"""Draw app/AC7.ico (Start menu and Apps & features icon of the installed app) from the CreeperUX tokens and the bundled
Chakra Petch font, like AC8.ico. Deterministic; run again after a token change. --check compares with the committed file.
Not shipped to players (tools/ goes into the source repository only)."""
from pathlib import Path
import argparse, io, json
from PIL import Image, ImageDraw, ImageFont

PKG = Path(__file__).resolve().parents[1]
OUT = PKG / 'app' / 'AC7.ico'


def draw(size):
    tokens = json.loads((PKG / 'ui/creeperux/tokens.json').read_text(encoding='utf-8'))['color']
    bg, text, accent = tokens['bg']['dark'], tokens['text']['dark'], tokens['accent']['dark']
    scale = 4; s = size * scale
    img = Image.new('RGBA', (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(img)
    d.rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * .18), fill=bg)
    d.rectangle((int(s * .14), int(s * .22), int(s * .14) + max(scale, int(s * .07)), int(s * .78)), fill=accent)
    font = ImageFont.truetype(str(PKG / 'ui/creeperux/fonts/chakra-petch-600-latin.ttf'), int(s * .40))
    box = d.textbbox((0, 0), 'AC7', font=font); w, h = box[2] - box[0], box[3] - box[1]
    x = int(s * .27) + (int(s * .66) - w) // 2 - box[0]; y = (s - h) // 2 - box[1]
    d.text((x, y), 'AC7', font=font, fill=text)
    return img.resize((size, size), Image.LANCZOS)


def build():
    sizes = [16, 24, 32, 48, 64, 128, 256]
    big = draw(256); buffer = io.BytesIO()
    big.save(buffer, format='ICO', sizes=[(n, n) for n in sizes], append_images=[draw(n) for n in sizes[:-1]])
    return buffer.getvalue()


if __name__ == '__main__':
    p = argparse.ArgumentParser(); p.add_argument('--check', action='store_true'); a = p.parse_args()
    data = build()
    if a.check:
        if not OUT.is_file() or OUT.read_bytes() != data: raise SystemExit('AC7.ico is out of date; run tools/build-app-icon.py')
        print('PASS app icon up to date')
    else:
        OUT.write_bytes(data); print(f'{OUT.relative_to(PKG)}: {len(data)} bytes')
