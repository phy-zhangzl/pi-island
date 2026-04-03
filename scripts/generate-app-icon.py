#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
ICONSET = ROOT / "Resources" / "AppIcon.iconset"
ICONSET.mkdir(parents=True, exist_ok=True)

BASE_SIZE = 1024
img = Image.new("RGBA", (BASE_SIZE, BASE_SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# black capsule-like tile
margin = 96
bg = (12, 12, 14, 255)
accent = (110, 231, 183, 255)
accent_dim = (58, 158, 122, 255)
white = (242, 244, 248, 255)

draw.rounded_rectangle(
    (margin, margin, BASE_SIZE - margin, BASE_SIZE - margin),
    radius=220,
    fill=bg,
)

# island notch accent
notch_w = 330
notch_h = 120
draw.rounded_rectangle(
    ((BASE_SIZE - notch_w) / 2, 150, (BASE_SIZE + notch_w) / 2, 150 + notch_h),
    radius=60,
    fill=(24, 24, 28, 255),
)

# left cat face
face = (170, 290, 450, 570)
draw.rounded_rectangle(face, radius=110, fill=accent)
draw.polygon([(195, 325), (250, 230), (300, 330)], fill=accent)
draw.polygon([(320, 330), (370, 230), (425, 325)], fill=accent)
draw.ellipse((245, 390, 275, 420), fill=bg)
draw.ellipse((345, 390, 375, 420), fill=bg)
draw.ellipse((303, 440, 323, 458), fill=bg)
draw.line((288, 470, 313, 485, 338, 470), fill=bg, width=10)

# right PI letters
try:
    font = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", 250)
    small = ImageFont.truetype("/System/Library/Fonts/SFNSRounded.ttf", 78)
except Exception:
    font = ImageFont.load_default()
    small = ImageFont.load_default()

draw.text((535, 310), "Pi", font=font, fill=white)
draw.rounded_rectangle((545, 585, 835, 645), radius=28, fill=accent_dim)
draw.text((575, 560), "Island", font=small, fill=white)

sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes:
    resized = img.resize((size, size), Image.LANCZOS)
    if size == 1024:
        resized.save(ICONSET / "icon_512x512@2x.png")
    else:
        resized.save(ICONSET / f"icon_{size}x{size}.png")
        resized.resize((size * 2, size * 2), Image.LANCZOS).save(ICONSET / f"icon_{size}x{size}@2x.png")

print(f"Generated iconset at {ICONSET}")
