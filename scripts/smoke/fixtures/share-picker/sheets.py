#!/usr/bin/env python3
"""Label guarded raw screenshots for the owner's visual approval."""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont
root = Path(sys.argv[1])
font = ImageFont.truetype("/usr/share/fonts/TTF/DejaVuSans.ttf", 22)
for mode in ("dark", "light"):
    names = [("before", "Before: hyprland-share-picker"),
             ("screens", "After: Screens, Remember, Cancel"),
             ("windows", "After: Windows, Remember, Cancel"),
             ("area", "After: Area, Remember, Cancel"),
             ("area-controls", "After: Area controls, Remember, Cancel"),
             ("keyboard-focus", "After: keyboard focus after Tab and Shift+Tab")]
    images = [(Image.open(root / f"{mode}-{name}.png").convert("RGB"), label) for name, label in names]
    width = max(image.width for image, _ in images)
    height = max(image.height for image, _ in images)
    caption_height = 90
    sheet = Image.new("RGB", (width * 2, (height + caption_height) * ((len(images) + 1) // 2)), "#242426" if mode == "dark" else "#f5f5f0")
    draw = ImageDraw.Draw(sheet)
    for index, (image, label) in enumerate(images):
        x, y = index % 2 * width, index // 2 * (height + caption_height)
        draw.text((x + 18, y + 14), mode.capitalize() + " " + label, font=font,
                  fill="white" if mode == "dark" else "black")
        if index > 0:
            draw.text((x + 18, y + 48), "focus ring at open: fixed by the shared item", font=font,
                      fill="white" if mode == "dark" else "black")
        sheet.paste(image, (x, y + caption_height))
    sheet.save(root / f"{mode}-before-after.png")
