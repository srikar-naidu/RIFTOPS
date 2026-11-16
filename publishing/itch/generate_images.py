#!/usr/bin/env python3
"""Build the itch.io cover and optimized screenshots from project-owned art."""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps


ITCH_DIR = Path(__file__).resolve().parent
ROOT = ITCH_DIR.parent.parent
OUTPUT_DIR = ITCH_DIR / "images"
SCREENSHOT_DIR = ROOT / "builds" / "screenshots"

SCREENSHOTS = {
    "screenshot-gameplay.png": "hud_buy_2340.png",
    "screenshot-buy-menu.png": "buymenu_2340.png",
    "screenshot-lobby.png": "lobby_2340.png",
    "screenshot-operator.png": "vm_operator_2340.png",
}

SCREENSHOT_SIZE = (1560, 720)
COVER_SIZE = (630, 500)


def font(name: str, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(ROOT / "assets" / "fonts" / name), size)


def save_png(image: Image.Image, destination: Path) -> None:
    image.convert("RGB").save(destination, "PNG", optimize=True, compress_level=9)


def build_screenshots() -> None:
    for output_name, source_name in SCREENSHOTS.items():
        source = Image.open(SCREENSHOT_DIR / source_name).convert("RGB")
        resized = source.resize(SCREENSHOT_SIZE, Image.Resampling.LANCZOS)
        save_png(resized, OUTPUT_DIR / output_name)


def build_cover() -> None:
    coral = "#ff5964"
    teal = "#59ffc8"
    ink = "#0b0f17"
    navy = "#111925"
    white = "#f4f7fb"
    muted = "#aeb8c7"

    canvas = Image.new("RGB", COVER_SIZE, ink)

    gameplay = Image.open(SCREENSHOT_DIR / "vm_operator_2340.png").convert("RGB")
    gameplay = ImageOps.fit(
        gameplay,
        (COVER_SIZE[0], 280),
        method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
    canvas.paste(gameplay, (0, 220))

    overlay = Image.new("RGBA", COVER_SIZE, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    overlay_draw.rectangle((0, 0, 630, 220), fill=ink)
    overlay_draw.polygon(((430, 0), (630, 0), (630, 220), (520, 220)), fill=navy)
    for y in range(220, 291):
        alpha = round(150 * (1 - (y - 220) / 71))
        overlay_draw.rectangle((0, y, 630, y), fill=(11, 15, 23, alpha))
    overlay_draw.rectangle((0, 217, 630, 221), fill=coral)
    canvas = Image.alpha_composite(canvas.convert("RGBA"), overlay)

    icon = Image.open(ROOT / "assets" / "icons" / "icon_main_192.png").convert("RGBA")
    icon = icon.resize((132, 132), Image.Resampling.LANCZOS)
    canvas.alpha_composite(icon, (34, 40))

    draw = ImageDraw.Draw(canvas)
    draw.text((188, 35), "VALU", font=font("Rajdhani-Bold.ttf", 84), fill=white)
    draw.text(
        (192, 124),
        "TACTICAL FPS",
        font=font("Rajdhani-SemiBold.ttf", 29),
        fill=muted,
    )

    pill = (190, 168, 466, 205)
    draw.rounded_rectangle(pill, radius=8, fill="#182432", outline=teal, width=2)
    draw.text(
        (208, 176),
        "ANDROID  •  LOCAL WI-FI",
        font=font("Rajdhani-SemiBold.ttf", 20),
        fill=teal,
    )

    badge = (405, 447, 610, 486)
    draw.rounded_rectangle(badge, radius=8, fill=(11, 15, 23, 220))
    draw.text(
        (424, 455),
        "FREE & OPEN SOURCE",
        font=font("Rajdhani-SemiBold.ttf", 18),
        fill=white,
    )

    save_png(canvas, OUTPUT_DIR / "cover.png")


def main() -> None:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    build_screenshots()
    build_cover()


if __name__ == "__main__":
    main()
