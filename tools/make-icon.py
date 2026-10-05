"""Draws the TeleCast app icon: 1024x1024 RGB PNG (no alpha), using Pillow.

Usage: python tools/make-icon.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024
SS = 4  # supersampling factor for smooth edges
BIG = SIZE * SS
OUT = Path(__file__).resolve().parent.parent / "TeleCast/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"

INDIGO = (30, 27, 75)
VIOLET = (109, 40, 217)
PINK = (219, 39, 119)
WHITE = (255, 255, 255, 255)


def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def background() -> Image.Image:
    small = 256
    img = Image.new("RGB", (small, small))
    px = img.load()
    for y in range(small):
        for x in range(small):
            t = (x + y) / (2 * (small - 1))
            px[x, y] = lerp(INDIGO, VIOLET, t / 0.55) if t < 0.55 else lerp(VIOLET, PINK, (t - 0.55) / 0.45)
    img = img.resize((BIG, BIG), Image.BICUBIC)

    glow = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(glow).ellipse((-200, -260, 700, 560), fill=48)
    glow = glow.filter(ImageFilter.GaussianBlur(160)).resize((BIG, BIG), Image.BICUBIC)
    img.paste(Image.new("RGB", (BIG, BIG), (255, 255, 255)), (0, 0), glow)
    return img


def s(v):
    return v * SS


def draw_tv(layer: Image.Image) -> None:
    d = ImageDraw.Draw(layer)
    # Screen outline
    d.rounded_rectangle((s(176), s(232), s(848), s(684)), radius=s(76), outline=WHITE, width=s(54))
    # Stand
    d.rounded_rectangle((s(478), s(684), s(546), s(770)), radius=s(10), fill=WHITE)
    d.rounded_rectangle((s(362), s(752), s(662), s(800)), radius=s(24), fill=WHITE)
    # Cast waves (bottom-left corner of the screen)
    cx, cy = s(292), s(588)
    d.ellipse((cx - s(30), cy - s(30), cx + s(30), cy + s(30)), fill=WHITE)
    for r in (110, 186, 262):
        d.arc((cx - s(r), cy - s(r), cx + s(r), cy + s(r)), start=270, end=360, fill=WHITE, width=s(42))
    # Play triangle (upper-right of the screen), slightly translucent
    tri = [(s(600), s(338)), (s(600), s(518)), (s(752), s(428))]
    d.polygon(tri, fill=(255, 255, 255, 215))


def main() -> None:
    base = background().convert("RGBA")
    shadow = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    draw_tv(shadow)
    alpha = shadow.split()[3].filter(ImageFilter.GaussianBlur(s(14)))
    dark = Image.new("RGBA", (BIG, BIG), (20, 10, 40, 0))
    dark.putalpha(alpha.point(lambda a: int(a * 0.45)))
    base = Image.alpha_composite(base, dark.transform((BIG, BIG), Image.AFFINE, (1, 0, 0, 0, 1, -s(10))))
    fg = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
    draw_tv(fg)
    base = Image.alpha_composite(base, fg)
    icon = base.convert("RGB").resize((SIZE, SIZE), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    icon.save(OUT, "PNG")
    print(f"Icon written to {OUT}")


if __name__ == "__main__":
    main()
