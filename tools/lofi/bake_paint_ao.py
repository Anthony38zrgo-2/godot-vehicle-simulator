"""Bake glTF AO into paint and apply PSX-style ordered dithering after export."""

import argparse
import copy
import io
from pathlib import Path

import numpy as np
from PIL import Image

from image2lofi_glb import read_glb, write_glb


def view_data(document, data, index):
    view = document["bufferViews"][index]
    offset = view.get("byteOffset", 0)
    return data[offset:offset + view["byteLength"]]


def accessor(document, data, index):
    spec = document["accessors"][index]
    view = document["bufferViews"][spec["bufferView"]]
    dtype = np.dtype({5121: "u1", 5123: "<u2", 5125: "<u4", 5126: "<f4"}[spec["componentType"]])
    width = {"SCALAR": 1, "VEC2": 2}[spec["type"]]
    return np.ndarray(
        (spec["count"], width), dtype=dtype,
        buffer=view_data(document, data, spec["bufferView"]),
        offset=spec.get("byteOffset", 0),
        strides=(view.get("byteStride", width * dtype.itemsize), dtype.itemsize),
    )


def sample(image, uv, repeat):
    height, width = image.shape[:2]
    xy = uv * (width, height) - 0.5
    x, y = np.floor(xy).astype(int).T
    fx, fy = (xy - np.floor(xy)).T
    if image.ndim == 3:
        fx, fy = fx[:, None], fy[:, None]

    def pixels(xx, yy):
        if repeat:
            return image[yy % height, xx % width]
        return image[np.clip(yy, 0, height - 1), np.clip(xx, 0, width - 1)]

    return ((pixels(x, y) * (1 - fx) + pixels(x + 1, y) * fx) * (1 - fy)
            + (pixels(x, y + 1) * (1 - fx) + pixels(x + 1, y + 1) * fx) * fy)


def rasterize(triangles, size, use_ao_uv, paint, ao, strength):
    rgb = np.zeros((size, size, 3))
    shade = np.ones((size, size))
    covered = np.zeros((size, size), dtype=bool)
    conflicts = np.zeros_like(covered)
    for original, baked in triangles:
        target = (baked if use_ao_uv else original) * size - 0.5
        lo = np.maximum(np.floor(target.min(axis=0)).astype(int), 0)
        hi = np.minimum(np.ceil(target.max(axis=0)).astype(int), size - 1)
        if np.any(lo > hi):
            continue
        edges = (target[1:] - target[0]).T
        if abs(np.linalg.det(edges)) < 1e-8:
            continue
        yy, xx = np.mgrid[lo[1]:hi[1] + 1, lo[0]:hi[0] + 1]
        points = np.column_stack((xx.ravel(), yy.ravel()))
        tail = (points - target[0]) @ np.linalg.inv(edges).T
        weights = np.column_stack((1 - tail.sum(axis=1), tail))
        inside = np.all(weights >= -1e-7, axis=1)
        weights = weights[inside]
        x, y = points[inside].T
        values = sample(ao, weights @ baked, repeat=False)
        conflicts[y, x] |= covered[y, x] & (np.abs(shade[y, x] - values) > 0.12)
        base = sample(paint, weights @ original, repeat=True)
        rgb[y, x] = base * ((1 - strength + strength * values[:, None]) ** (1 / 2.2))
        shade[y, x] = values
        covered[y, x] = True
    return rgb, covered, conflicts


def ordered_palette(rgb, covered, colors):
    # Extend chart colors into padding to limit seams under mipmapping.
    for _ in range(4):
        padded = np.pad(rgb, ((1, 1), (1, 1), (0, 0)), mode="edge")
        mask = np.pad(covered, 1, mode="constant")
        size = len(rgb)
        for y, x in [(0, 1), (2, 1), (1, 0), (1, 2)]:
            available = mask[y:y + size, x:x + size] & ~covered
            rgb[available] = padded[y:y + size, x:x + size][available]
            covered |= available
    samples = Image.fromarray(np.uint8(np.clip(rgb[covered], 0, 255))[None])
    # Nudge RGB before mapping to the palette so the pattern is anchored to texels.
    palette = samples.quantize(colors=colors, dither=Image.Dither.NONE)
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]])
    yy, xx = np.indices(covered.shape)
    offset = ((bayer[yy % 4, xx % 4] + 0.5) / 16 - 0.5) * 26
    pixels = np.uint8(np.clip(rgb + offset[:, :, None], 0, 255))
    return Image.fromarray(pixels).quantize(palette=palette, dither=Image.Dither.NONE)


def bake(args):
    document, data = read_glb(args.source)
    # Preserve the previously processed non-paint maps and materials.
    output, buffer = read_glb(args.variant)
    assert document["meshes"] == output["meshes"]
    material_index = next(i for i, m in enumerate(document["materials"]) if m["name"] == args.material)
    material = document["materials"][material_index]
    base = material["pbrMetallicRoughness"]["baseColorTexture"]
    occlusion = material["occlusionTexture"]
    assert base.get("texCoord", 0) == 0 and occlusion["texCoord"] == 1

    def image(info, mode):
        index = document["textures"][info["index"]]["source"]
        payload = view_data(document, data, document["images"][index]["bufferView"])
        with Image.open(io.BytesIO(payload)) as source:
            if mode == "RGB" and source.convert("RGBA").getchannel("A").getextrema() != (255, 255):
                raise ValueError("AO compositing is limited to opaque paint")
            return np.asarray(source.convert(mode))

    paint, ao = image(base, "RGB"), image(occlusion, "L") / 255.0
    triangles = []
    primitives = [p for mesh in output["meshes"] for p in mesh["primitives"] if p["material"] == material_index]
    for primitive in primitives:
        uv = primitive["attributes"]
        indices = accessor(document, data, primitive["indices"]).reshape(-1, 3)
        triangles.extend(zip(accessor(document, data, uv["TEXCOORD_0"])[indices],
                             accessor(document, data, uv["TEXCOORD_1"])[indices]))
    rgb, covered, conflicts = rasterize(triangles, args.size, False, paint, ao, 0.7)
    out_of_range = any(np.any((uv < 0) | (uv > 1)) for uv, _ in triangles)
    print(f"UV0: {covered.sum()} covered texels, {conflicts.sum()} incompatible AO overlaps, tiled={out_of_range}")
    if out_of_range or conflicts.any():
        rgb, covered, conflicts = rasterize(triangles, args.size, True, paint, ao, 0.7)
        print(f"AO atlas: {covered.sum()} covered texels, {conflicts.sum()} incompatible overlaps")
        if conflicts.any():
            raise ValueError("AO atlas contains conflicting charts")
        for primitive in primitives:
            uv = primitive["attributes"]
            uv["TEXCOORD_0"] = uv["TEXCOORD_1"]
    if not covered.any():
        raise ValueError("No paint was rasterized")
    result = ordered_palette(rgb, covered, args.colors)
    assert len(result.getcolors()) <= args.colors
    payload = io.BytesIO()
    result.save(payload, format="PNG", optimize=True)
    buffer += bytes(-len(buffer) % 4)
    output["bufferViews"].append({"buffer": 0, "byteOffset": len(buffer), "byteLength": payload.tell()})
    output["images"].append({
        "name": f"Mustang_Paint_AO_Bayer4_{args.colors}", "bufferView": len(output["bufferViews"]) - 1,
        "mimeType": "image/png",
    })
    target = output["materials"][material_index]
    base_texture = copy.copy(output["textures"][base["index"]])
    base_texture["source"] = len(output["images"]) - 1
    output["textures"].append(base_texture)
    target["pbrMetallicRoughness"]["baseColorTexture"]["index"] = len(output["textures"]) - 1
    target["occlusionTexture"]["strength"] = 0.25
    write_glb(args.output, output, buffer + payload.getvalue())
    result.save(args.output.with_name("paint_bayer4.png"))
    print(f"{len(result.getcolors())} colors; {payload.tell()} bytes; {args.output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("variant", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--material", default="PalominoSpecial67_Bodymat")
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument("--colors", type=int, choices=(32, 64), default=32)
    bake(parser.parse_args())

