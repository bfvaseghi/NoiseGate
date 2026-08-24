#!/usr/bin/env python3
"""Render the source icon into the exact opaque PNG sizes Xcode expects."""

import cairo
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "iOS/App/Assets.xcassets/AppIcon.appiconset"
MAC = ROOT / "macOS/App/Assets.xcassets/AppIcon.appiconset"


def rounded_rectangle(ctx, x, y, width, height, radius):
    ctx.new_sub_path()
    ctx.arc(x + width - radius, y + radius, radius, -1.5708, 0)
    ctx.arc(x + width - radius, y + height - radius, radius, 0, 1.5708)
    ctx.arc(x + radius, y + height - radius, radius, 1.5708, 3.14159)
    ctx.arc(x + radius, y + radius, radius, 3.14159, 4.71239)
    ctx.close_path()


def render(path, size):
    surface = cairo.ImageSurface(cairo.FORMAT_RGB24, size, size)
    ctx = cairo.Context(surface)
    ctx.scale(size / 1024, size / 1024)

    ground = cairo.LinearGradient(0, 0, 1024, 1024)
    ground.add_color_stop_rgb(0, 0x2B / 255, 0x11 / 255, 0x15 / 255)
    ground.add_color_stop_rgb(1, 0x12 / 255, 0x07 / 255, 0x09 / 255)
    ctx.rectangle(0, 0, 1024, 1024)
    ctx.set_source(ground)
    ctx.fill()

    ctx.move_to(102, 512)
    ctx.curve_to(170, 512, 170, 332, 238, 332)
    ctx.curve_to(306, 332, 306, 692, 374, 692)
    ctx.curve_to(442, 692, 442, 410, 510, 410)
    ctx.set_source_rgb(0xF5 / 255, 0x9A / 255, 0x2E / 255)
    ctx.set_line_width(78)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.stroke()

    gate = cairo.LinearGradient(0, 182, 0, 842)
    gate.add_color_stop_rgb(0, 0xF0 / 255, 0x44 / 255, 0x3B / 255)
    gate.add_color_stop_rgb(1, 0xC5 / 255, 0x16 / 255, 0x12 / 255)
    rounded_rectangle(ctx, 468, 182, 116, 660, 58)
    ctx.set_source(gate)
    ctx.fill()

    ctx.arc(526, 512, 26, 0, 6.28319)
    ctx.set_source_rgb(0xFA / 255, 0xF6 / 255, 0xF3 / 255)
    ctx.fill()

    ctx.move_to(584, 512)
    ctx.line_to(922, 512)
    ctx.set_source_rgb(0x2B / 255, 0xB3 / 255, 0xA9 / 255)
    ctx.set_line_width(78)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.stroke()

    surface.write_to_png(path)


for target in (IOS, MAC):
    target.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((target / "Contents.json").read_text())
    for image in manifest["images"]:
        logical_size = float(image["size"].split("x", 1)[0])
        scale = int(image["scale"].removesuffix("x"))
        render(target / image["filename"], round(logical_size * scale))
