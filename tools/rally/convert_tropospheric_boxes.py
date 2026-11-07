"""Convert Tropospheric Boxes 1.2 to Godot cubemap strips (requires Pillow)."""
import argparse
import hashlib
from io import BytesIO
import json
from pathlib import Path
import re
import struct
from zipfile import ZipFile

from PIL import Image


def read_vtf(data):
    if data[:12] != b"VTF\0" + struct.pack("<II", 7, 2):
        raise ValueError("Expected VTF 7.2")
    header_size, width, height = struct.unpack_from("<IHH", data, 12)
    fmt = struct.unpack_from("<I", data, 52)[0]
    thumb_fmt, thumb_w, thumb_h, depth = struct.unpack_from("<IBBH", data, 57)
    frames = struct.unpack_from("<H", data, 24)[0]
    if frames != 1 or depth != 1 or thumb_fmt not in (13, 15):
        raise ValueError("Unsupported VTF layout")
    fourcc, block_size = {13: (b"DXT1", 8), 15: (b"DXT5", 16)}[fmt]
    size = ((width + 3) // 4) * ((height + 3) // 4) * block_size
    if len(data) - header_size < size:
        raise ValueError("Truncated VTF")
    # VTF stores the largest mip last. Wrap its BC blocks in a DDS header for Pillow.
    dds = b"DDS " + struct.pack("<7I", 124, 0x81007, height, width, size, 0, 0)
    dds += bytes(44) + struct.pack("<2I4s5I", 32, 4, fourcc, 0, 0, 0, 0, 0)
    dds += struct.pack("<5I", 0x1000, 0, 0, 0, 0)
    with Image.open(BytesIO(dds + data[-size:])) as image:
        return image.convert("RGB")


def read_face(archive, name, suffix, size):
    material = archive.read(f"skybox/{name}{suffix}.vmt").decode("ascii")
    texture = re.search(r'\$basetexture\s+"(skybox/\w+)"', material)[1]
    image = read_vtf(archive.read(texture + ".vtf"))
    if image.width == 2 * image.height:
        if "center 0.5 0 scale 1 2 rotate 0 translate 0 0" not in material:
            raise ValueError(f"Unexpected Source UV transform: {name}{suffix}")
        # Source maps the half-height texture onto the upper half of the face.
        upper = image.resize((size, size // 2), Image.Resampling.LANCZOS)
        image = Image.new("RGB", (size, size))
        image.paste(upper, (0, 0))
        image.paste(upper.crop((0, size // 2 - 1, size, size // 2)).resize(
            (size, size // 2)), (0, size // 2))
        return image
    return image.resize((size, size), Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("--output", type=Path, default=Path("game/assets/weather/tropospheric"))
    parser.add_argument("--size", type=int, choices=(256, 512, 1024, 2048), default=512)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    with ZipFile(args.archive) as archive:
        # night_1 has only a zenith texture; its four horizon faces are blank.
        names = sorted(Path(path).stem[:-2] for path in archive.namelist() if path.endswith("ft.vtf"))
        if len(names) != 25:
            raise ValueError("Expected 25 skies")
        hashes = {}
        for name in names:
            faces = {face: read_face(archive, name, face, args.size)
                     for face in ("ft", "rt", "bk", "lf", "up", "dn")}
            # Rotate the Source zenith to match the four Godot side edges.
            faces["up"] = faces["up"].transpose(Image.Transpose.ROTATE_90)
            # Godot's strip order is +X, -X, +Y, -Y, +Z, -Z.
            strip = Image.new("RGB", (6 * args.size, args.size))
            for index, face in enumerate(("rt", "lf", "up", "dn", "bk", "ft")):
                strip.paste(faces[face], (index * args.size, 0))
            path = args.output / f"{name}.png"
            strip.save(path)
            settings = path.with_suffix(".png.import")
            if not settings.exists():
                settings.write_text(
                    '[remap]\nimporter="cubemap_texture"\ntype="CompressedCubemap"\n'
                    '[params]\ncompress/mode=0\ncompress/high_quality=true\n'
                    'mipmaps/generate=true\nslices/arrangement=3\n',
                    encoding="utf-8",
                )
            hashes[path.name] = hashlib.sha256(path.read_bytes()).hexdigest()
        (args.output / "LICENSE.txt").write_bytes(archive.read("license.txt"))
    provenance = {
        "author": "Hsyenoh05",
        "source": args.archive.name,
        "source_sha256": hashlib.sha256(args.archive.read_bytes()).hexdigest(),
        "face_size": args.size,
        "texture_sha256": hashes,
    }
    (args.output / "PROVENANCE.json").write_text(json.dumps(provenance, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()

