"""Recolour a character's baked texture into a team kit and skin tone.

The models are generated from a reference photograph, so the jersey, shorts and
skin are painted into one atlas rather than split into materials. Swapping a
material cannot change the kit; the pixels have to be reclassified and retinted.

Classification is by saturation, and the thresholds come from the texture's own
histogram rather than taste. In the warm hues skin peaks around 0.3-0.55 and kit
colour around 0.85-1.0, with a clear trough at 0.78 between them.

Hair and beard are the same black as the jersey, so they cannot be separated by
colour at all. Instead the mesh is used: triangles above 80% of body height are
rasterised through the UVs into a mask, and those texels are left alone.

    python tools/dev/kit_texture.py model.glb --primary #1B4F9C --secondary #F2F4F8 \
        --skin #4A2E1E --out kit.png

Needs pillow and numpy, which are not required to build or run the game.
"""

import argparse
import json
import pathlib
import struct
import sys

import numpy as np
from PIL import Image

TRIM_SATURATION = 0.78
HEAD_HEIGHT = 0.80
ATLAS = 2048

COMPONENT_FORMATS = {5121: "B", 5123: "H", 5125: "I", 5126: "f"}
TYPE_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def read_glb(path):
    raw = path.read_bytes()
    offset, meta, binary = 12, None, None
    while offset < len(raw):
        length, kind = struct.unpack("<II", raw[offset:offset + 8])
        chunk = raw[offset + 8:offset + 8 + length]
        if kind == 0x4E4F534A:
            meta = json.loads(chunk.decode("utf-8"))
        elif kind == 0x004E4942:
            binary = chunk
        offset += 8 + length
    return meta, binary


def accessor(meta, binary, index):
    acc = meta["accessors"][index]
    view = meta["bufferViews"][acc["bufferView"]]
    start = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    per = TYPE_COUNTS[acc["type"]]
    fmt = COMPONENT_FORMATS[acc["componentType"]]
    values = struct.unpack_from("<%d%s" % (acc["count"] * per, fmt), binary, start)
    return np.array(values).reshape(-1, per)


def baked_texture(meta, binary):
    image = meta["images"][0]
    view = meta["bufferViews"][image["bufferView"]]
    start = view.get("byteOffset", 0)
    return binary[start:start + view["byteLength"]]


def head_mask(meta, binary, size):
    """Texels belonging to triangles near the top of the body."""
    prim = meta["meshes"][0]["primitives"][0]
    positions = accessor(meta, binary, prim["attributes"]["POSITION"])
    uvs = accessor(meta, binary, prim["attributes"]["TEXCOORD_0"]).copy()
    indices = accessor(meta, binary, prim["indices"]).reshape(-1, 3)

    low, high = positions[:, 1].min(), positions[:, 1].max()
    height = (positions[:, 1] - low) / max(high - low, 1e-6)
    uvs[:, 1] = 1.0 - uvs[:, 1]
    pixels = np.clip(uvs * size, 0, size - 1)

    mask = np.zeros((size, size), bool)
    for tri in indices[height[indices].mean(1) > HEAD_HEIGHT]:
        pts = pixels[tri]
        x0, y0 = np.floor(pts.min(0)).astype(int) - 3
        x1, y1 = np.ceil(pts.max(0)).astype(int) + 3
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, size - 1), min(y1, size - 1)
        if x1 <= x0 or y1 <= y0:
            continue
        yy, xx = np.mgrid[y0:y1 + 1, x0:x1 + 1]
        (ax, ay), (bx, by), (cx, cy) = pts
        denominator = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(denominator) < 1e-9:
            mask[y0:y1 + 1, x0:x1 + 1] = True
            continue
        w0 = ((by - cy) * (xx - cx) + (cx - bx) * (yy - cy)) / denominator
        w1 = ((cy - ay) * (xx - cx) + (ax - cx) * (yy - cy)) / denominator
        # Slack on the edges so seams between islands are covered too.
        inside = (w0 > -0.12) & (w1 > -0.12) & ((1 - w0 - w1) > -0.12)
        mask[y0:y1 + 1, x0:x1 + 1] |= inside
    return mask


def hsv(rgb):
    red, green, blue = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    high, low = rgb.max(-1), rgb.min(-1)
    span = high - low + 1e-6
    saturation = np.where(high > 0, (high - low) / np.maximum(high, 1e-6), 0)
    hue = np.zeros_like(high)
    at = high == red
    hue[at] = ((green - blue)[at] / span[at]) % 6
    at = high == green
    hue[at] = ((blue - red)[at] / span[at]) + 2
    at = high == blue
    hue[at] = ((red - green)[at] / span[at]) + 4
    return hue * 60.0, saturation, high


def to_rgb(text):
    text = text.lstrip("#")
    return np.array([int(text[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], np.float32)


def recolour(base, mask, target, gain, luma):
    """Replaces colour while keeping the shading that carries fabric and muscle."""
    reference = max(luma[mask].mean(), 0.02)
    shade = np.clip(0.35 + gain * (luma[mask] / reference), 0.0, 1.85)
    base[mask] = np.clip(target[None, :] * shade[:, None], 0.0, 1.0)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("model")
    parser.add_argument("--primary", required=True, help="jersey colour, #rrggbb")
    parser.add_argument("--secondary", required=True, help="shorts and trim")
    parser.add_argument("--skin", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args(argv)

    meta, binary = read_glb(pathlib.Path(args.model))
    if not meta.get("images"):
        print("%s has no baked texture to recolour" % args.model)
        return 1

    raw = baked_texture(meta, binary)
    scratch = pathlib.Path(args.out).with_suffix(".source.png")
    scratch.write_bytes(raw)
    pixels = np.asarray(Image.open(scratch).convert("RGB")).astype(np.float32) / 255.0
    scratch.unlink()

    head = head_mask(meta, binary, pixels.shape[0])
    hue, saturation, value = hsv(pixels)
    luma = pixels @ np.array([0.2126, 0.7152, 0.0722], np.float32)

    # Claimed most confident first; whatever dark is left over is fabric, so no
    # region is skipped and left showing the original kit.
    trim = (saturation > TRIM_SATURATION) & (value > 0.30) \
        & (hue > 8) & (hue < 50) & ~head
    skin = ~trim & ~head & (saturation > 0.12) & (saturation <= TRIM_SATURATION) \
        & (value > 0.20) & (hue > 2) & (hue < 55)
    jersey = ~trim & ~skin & ~head & (value < 0.50)

    out = pixels.copy()
    recolour(out, jersey, to_rgb(args.primary), 0.72, luma)
    recolour(out, trim, to_rgb(args.secondary), 0.62, luma)
    recolour(out, skin, to_rgb(args.skin), 0.62, luma)

    Image.fromarray((out * 255).astype(np.uint8)).save(args.out)
    print("%s: jersey %.0f%%, trim %.0f%%, skin %.0f%%, head kept %.0f%%" % (
        pathlib.Path(args.out).name, 100 * jersey.mean(), 100 * trim.mean(),
        100 * skin.mean(), 100 * head.mean()))
    return 0


if __name__ == "__main__":
    sys.exit(main())
