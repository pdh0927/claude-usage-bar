#!/usr/bin/env python3
"""Generates the 1024x1024 app icon (Dock/Finder icon, not the menu bar icon,
which is drawn programmatically in src/main.swift): neutral rounded-square
background + a white gauge ring. Run this, then `iconutil -c icns AppIcon.iconset`."""
from PIL import Image, ImageDraw
import math

SIZE = 1024
BG = (70, 90, 110)       # neutral slate -- avoids implying an official Anthropic app
RING_BG = (255, 255, 255, 70)
RING_FG = (255, 255, 255, 255)

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

radius = 220
draw.rounded_rectangle([0, 0, SIZE, SIZE], radius=radius, fill=BG)

cx, cy = SIZE // 2, SIZE // 2 + 20
r = 300
width = 70
start_angle = -220
end_angle = 40
progress_angle = start_angle + (end_angle - start_angle) * 0.72

bbox = [cx - r, cy - r, cx + r, cy + r]
draw.arc(bbox, start_angle, end_angle, fill=RING_BG, width=width)
draw.arc(bbox, start_angle, progress_angle, fill=RING_FG, width=width)

def cap(angle_deg):
    a = math.radians(angle_deg)
    x = cx + r * math.cos(a)
    y = cy + r * math.sin(a)
    rr = width / 2
    draw.ellipse([x - rr, y - rr, x + rr, y + rr], fill=RING_FG)

cap(start_angle)
cap(progress_angle)

img.save("icon_source.png")
print("saved icon_source.png")
