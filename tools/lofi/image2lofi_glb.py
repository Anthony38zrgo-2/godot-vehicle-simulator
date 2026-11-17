"""Apply the Image2Lofi reduction and adaptive palette to embedded GLB textures."""

import argparse
import io
import json
from pathlib import Path
import struct

from PIL import Image, ImageEnhance


def read_glb(path):
    raw = path.read_bytes()
    magic, version, size, json_size, kind = struct.unpack_from("<4sIII4s", raw)
    if (magic, version, size, kind) != (b"glTF", 2, len(raw), b"JSON"):
        raise ValueError(f"Expected a glTF 2 GLB: {path}")
    end = 20 + json_size
    bin_size, kind = struct.unpack_from("<I4s", raw, end)
    if kind != b"BIN\0" or end + 8 + bin_size != len(raw):
        raise ValueError("Expected one embedded BIN chunk")
    return json.loads(raw[20:end]), raw[end + 8:]


def write_glb(path, document, data):
    document["buffers"][0]["byteLength"] = len(data)
    data += bytes(-len(data) % 4)
    metadata = json.dumps(document, separators=(",", ":")).encode()
    metadata += b" " * (-len(metadata) % 4)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(
        struct.pack("<4sIII4s", b"glTF", 2, 28 + len(metadata) + len(data), len(metadata), b"JSON")
        + metadata + struct.pack("<I4s", len(data), b"BIN\0") + data
    )


def convert_image(raw, limit, colors, dither, is_ao):
    with Image.open(io.BytesIO(raw)) as image:
        rgba = image.convert("RGBA")
        rgba.thumbnail((limit, limit), Image.Resampling.LANCZOS)
        alpha = rgba.getchannel("A")
        if is_ao:
            result = rgba.convert("L")
        else:
            rgb = ImageEnhance.Color(rgba.convert("RGB")).enhance(1.1)
            palette = rgb.quantize(colors=colors)
            if dither:
                palette = rgb.quantize(palette=palette, dither=Image.Dither.FLOYDSTEINBERG)
            result = palette
            if alpha.getextrema() != (255, 255):
                result = palette.convert("RGB")
                result.putalpha(alpha)
        output = io.BytesIO()
        result.save(output, format="PNG", optimize=True)
        return output.getvalue(), result.size


def convert_glb(source, destination, args):
    document, data = read_glb(source)
    textures = document["textures"]
    images = document["images"]
    views = document["bufferViews"]
    base = set()
    ao = set()
    other = set()
    for material in document["materials"]:
        pbr = material.get("pbrMetallicRoughness", {})
        if "baseColorTexture" in pbr:
            base.add(pbr["baseColorTexture"]["index"])
        if "occlusionTexture" in material:
            ao.add(material["occlusionTexture"]["index"])
        for block in [pbr, material, *material.get("extensions", {}).values()]:
            other.update(value["index"] for key, value in block.items()
                         if key.endswith("Texture") and key not in {"baseColorTexture", "occlusionTexture"})
    protected = {textures[index]["source"] for index in other}
    replacements = {}
    samplers = document.setdefault("samplers", [])
    for index in sorted(base | (ao if args.ao_size else set())):
        texture = textures[index]
        image_index = texture["source"]
        image = images[image_index]
        if image_index in protected or "bufferView" not in image:
            continue
        view_index = image["bufferView"]
        view = views[view_index]
        if view_index not in replacements:
            start = view.get("byteOffset", 0)
            is_ao = index in ao and index not in base
            wheel = "_wheel_" in source.stem
            limit = args.ao_size if is_ao else (64 if wheel else args.size)
            payload, dimensions = convert_image(
                data[start:start + view["byteLength"]], limit, args.colors, args.dither, is_ao
            )
            replacements[view_index] = payload
            image["mimeType"] = "image/png"
            print(f"  {image.get('name', image_index)} {dimensions[0]}x{dimensions[1]} "
                  f"{view['byteLength']:,} -> {len(payload):,} bytes")
        if index in base:
            previous = samplers[texture["sampler"]] if "sampler" in texture else {}
            nearest = {**previous, "magFilter": 9728, "minFilter": 9984}
            if nearest not in samplers:
                samplers.append(nearest)
            texture["sampler"] = samplers.index(nearest)
    for material in document["materials"]:
        if material.get("name") == args.matte_material:
            material["pbrMetallicRoughness"]["roughnessFactor"] = 0.48
            coat = material.get("extensions", {}).get("KHR_materials_clearcoat")
            if coat is not None:
                coat.update(clearcoatFactor=0.18, clearcoatRoughnessFactor=0.32)
    buffer = bytearray()
    for index, view in enumerate(views):
        start = view.get("byteOffset", 0)
        payload = replacements.get(index, data[start:start + view["byteLength"]])
        buffer.extend(bytes(-len(buffer) % 4))
        view["byteOffset"] = len(buffer)
        view["byteLength"] = len(payload)
        buffer.extend(payload)
    write_glb(destination, document, bytes(buffer))
    print(f"{source.name}: {source.stat().st_size:,} -> {destination.stat().st_size:,} bytes")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("inputs", nargs="+", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--size", type=int, default=256)
    parser.add_argument("--colors", type=int, choices=range(2, 257), default=128, metavar="2–256")
    parser.add_argument("--dither", action="store_true")
    parser.add_argument("--ao-size", type=int, default=0, help="Optional AO limit. Zero preserves AO.")
    parser.add_argument("--matte-material", help="Name of the paint material to soften for comparison.")
    args = parser.parse_args()
    if args.size < 1 or args.ao_size < 0:
        parser.error("Texture sizes must be positive, or zero for unchanged AO")
    for source in args.inputs:
        destination = args.output / source.name
        if destination.resolve() == source.resolve():
            parser.error("Use a different output directory")
        convert_glb(source, destination, args)


if __name__ == "__main__":
    main()


