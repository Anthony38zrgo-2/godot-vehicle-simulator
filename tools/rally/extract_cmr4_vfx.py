#!/usr/bin/env python3
"""Extract the Colin McRae Rally 04 VFX sprites used by the rally simulator.

The source archive is Data/Textures/SFXNew.big. Unlike the encrypted sound
archives, every texture entry is an unencrypted DDS file (DXT1 or DXT5 with a
mip chain). This tool reads only the entries listed in TARGETS, decodes the
base mip level and writes an RGBA PNG next to the existing CMR4 assets, then
records the original names and both SHA-256 digests in manifest.json.

Usage:
    python tools/rally/extract_cmr4_vfx.py
    python tools/rally/extract_cmr4_vfx.py --verify-only
    python tools/rally/extract_cmr4_vfx.py --source-root "D:\\ASETS\\CMR4\\Colin McRae Rally 04"

The runtime never opens the BIG archive; only the committed PNG files and the
manifest are needed. A source installation is required only to rerun this tool.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import struct
import sys
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, __version__ as PIL_VERSION

REPO_ROOT = Path(__file__).resolve().parents[2]
DEST_DIR = REPO_ROOT / "game" / "assets" / "vfx" / "cmr4"
MANIFEST_PATH = DEST_DIR / "manifest.json"
SOURCE_RELATIVE = Path("Data/Textures/SFXNew.big")
MANIFEST_SOURCE = "Colin McRae Rally 04/Data/Textures/SFXNew.big"
DEFAULT_CMR4_ROOT = Path(r"D:\ASETS\CMR4\Colin McRae Rally 04")

ARCHIVE_SIGNATURE = b"BIGF"
ENTRY_TABLE_OFFSET = 0x24
ENTRY_SIZE = 0x18
NAME_LENGTH = 16
DDS_HEADER_SIZE = 128
SUPPORTED_FOURCC = ("DXT1", "DXT5")
TOOL_VERSION = 1
PNG_COMPRESS_LEVEL = 6


class VfxError(RuntimeError):
    """Raised when the archive, a DDS entry or the manifest is inconsistent."""


@dataclass(frozen=True)
class ArchiveEntry:
    index: int
    name: str
    size: int
    relative_offset: int
    absolute_offset: int


@dataclass(frozen=True)
class DdsHeader:
    width: int
    height: int
    mip_levels: int
    fourcc: str
    alpha_flag: bool


@dataclass(frozen=True)
class Target:
    entry: str
    blend: str
    roles: tuple[str, ...]


# Stable output order. The first three entries already exist in the manifest;
# keeping them first makes the manifest diff readable. blend is explicit:
# sprites without an alpha channel are drawn additively at runtime.
TARGETS: tuple[Target, ...] = (
    Target("smoke_01.dds", "alpha", ("wheel_smoke_asphalt",)),
    Target("Dust_01.dds", "alpha", ("wheel_dust_core",)),
    Target("Dust_02.dds", "alpha", ("wheel_dust_plume",)),
    Target("Water_1.dds", "alpha", ("wheel_water_core",)),
    Target("Water_2.dds", "alpha", ("wheel_water_mist",)),
    Target("Cr_splsh.dds", "alpha", ("wheel_splash_loose",)),
    Target("Rd_splsh.dds", "alpha", ("wheel_splash_paved",)),
    Target("Sprk_sml.dds", "additive", ("impact_spark_small",)),
    Target("Sprk_big.dds", "additive", ("impact_spark_large",)),
    Target("Mud_rd1.dds", "alpha", ("impact_mud", "wheel_chips_mud")),
    Target("leaf_01.dds", "alpha", ("impact_leaf", "wheel_chips_grass")),
    Target("leaf_02.dds", "alpha", ("impact_leaf", "wheel_chips_grass")),
    Target("leaf_03.dds", "alpha", ("impact_leaf", "wheel_chips_grass")),
    Target("Snw_rd0.dds", "alpha", ("wheel_snow",)),
    Target("Snw_rd1.dds", "alpha", ("wheel_snow",)),
    Target("Snw_rd2.dds", "alpha", ("wheel_snow",)),
    Target("Snw_rd3.dds", "alpha", ("wheel_snow",)),
    Target("SnwFlk_1.dds", "alpha", ("precipitation_snow",)),
    Target("raindrop.dds", "alpha", ("precipitation_rain_near",)),
    Target("R_Fall.dds", "alpha", ("precipitation_rain_far",)),
)


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def png_name(entry_name: str) -> str:
    return entry_name.rsplit(".", 1)[0].lower() + ".png"


def resolve_archive(source_root: Path | None) -> Path:
    if source_root is None:
        env_root = os.environ.get("CMR4_ROOT")
        source_root = Path(env_root) if env_root else DEFAULT_CMR4_ROOT
    root = source_root.expanduser()
    candidates = [
        root / SOURCE_RELATIVE,
        root / "SFXNew.big",
        root,
    ]
    for candidate in candidates:
        if candidate.is_file() and candidate.name.lower() == "sfxnew.big":
            return candidate
    raise VfxError(f"SFXNew.big not found under {root}")


def parse_archive(data: bytes) -> tuple[int, list[ArchiveEntry]]:
    if data[:4] != ARCHIVE_SIGNATURE:
        raise VfxError("archive signature is not BIGF")
    count, data_offset = struct.unpack_from("<II", data, 4)
    if count <= 0:
        raise VfxError(f"archive reports {count} entries")
    entries: list[ArchiveEntry] = []
    seen: set[str] = set()
    for index in range(count):
        base = ENTRY_TABLE_OFFSET + index * ENTRY_SIZE
        if base + ENTRY_SIZE > len(data):
            raise VfxError(f"entry table exceeds archive bounds at index {index}")
        raw_name = data[base:base + NAME_LENGTH]
        name = raw_name.split(b"\x00", 1)[0].decode("ascii", "strict")
        size, relative = struct.unpack_from("<II", data, base + NAME_LENGTH)
        absolute = data_offset + relative
        if absolute + size > len(data):
            raise VfxError(f"entry {name or index} exceeds archive bounds")
        if not name:
            raise VfxError(f"entry {index} has an empty name")
        if name in seen:
            raise VfxError(f"duplicate archive entry name: {name}")
        seen.add(name)
        entries.append(ArchiveEntry(index, name, size, relative, absolute))
    return data_offset, entries


def parse_dds_header(blob: bytes, name: str) -> DdsHeader:
    if len(blob) < DDS_HEADER_SIZE or blob[:4] != b"DDS ":
        raise VfxError(f"{name}: missing DDS header")
    height, width = struct.unpack_from("<II", blob, 12)
    mip_levels = struct.unpack_from("<I", blob, 28)[0] or 1
    pixel_flags = struct.unpack_from("<I", blob, 80)[0]
    fourcc = blob[84:88].decode("ascii", "replace")
    if fourcc not in SUPPORTED_FOURCC:
        raise VfxError(f"{name}: unsupported DDS format {fourcc!r}")
    if width <= 0 or height <= 0:
        raise VfxError(f"{name}: invalid dimensions {width}x{height}")
    return DdsHeader(width, height, mip_levels, fourcc, bool(pixel_flags & 0x1))


def expected_payload_size(header: DdsHeader) -> int:
    block_bytes = 8 if header.fourcc == "DXT1" else 16
    width, height = header.width, header.height
    total = 0
    for _ in range(header.mip_levels):
        blocks = max(1, (width + 3) // 4) * max(1, (height + 3) // 4)
        total += blocks * block_bytes
        width = max(1, width // 2)
        height = max(1, height // 2)
    return total


def decode_dds(blob: bytes, name: str) -> tuple[DdsHeader, Image.Image]:
    header = parse_dds_header(blob, name)
    expected = DDS_HEADER_SIZE + expected_payload_size(header)
    if len(blob) != expected:
        raise VfxError(
            f"{name}: DDS payload is {len(blob)} bytes, expected {expected} "
            f"for {header.width}x{header.height} {header.fourcc} with {header.mip_levels} mips"
        )
    try:
        image = Image.open(io.BytesIO(blob))
    except Exception as exc:  # Pillow raises several image-specific errors.
        raise VfxError(f"{name}: Pillow cannot decode DDS: {exc}") from exc
    if image.size != (header.width, header.height):
        raise VfxError(f"{name}: decoded size {image.size} does not match the header")
    return header, image.convert("RGBA")


def alpha_stats(image: Image.Image) -> dict:
    alpha = image.getchannel("A")
    histogram = alpha.histogram()
    total = image.width * image.height
    nonzero = total - histogram[0]
    return {
        "present": any(histogram[:255]),
        "min": min(i for i, value in enumerate(histogram) if value),
        "max": max(i for i, value in enumerate(histogram) if value),
        "coverage": round(nonzero / total, 3),
        "opaque": histogram[255] == total,
    }


def encode_png(image: Image.Image) -> bytes:
    buffer = io.BytesIO()
    image.save(buffer, format="PNG", optimize=False, compress_level=PNG_COMPRESS_LEVEL)
    return buffer.getvalue()


def read_png_rgba(path: Path) -> Image.Image:
    try:
        with Image.open(path) as image:
            return image.convert("RGBA")
    except OSError as exc:
        raise VfxError(f"{path}: cannot read existing PNG: {exc}") from exc


def extract(
    archive_path: Path,
    force: bool,
    verify_only: bool,
    verbose: bool,
) -> dict:
    archive = archive_path.read_bytes()
    data_offset, entries = parse_archive(archive)
    by_name = {entry.name: entry for entry in entries}
    missing = [target.entry for target in TARGETS if target.entry not in by_name]
    if missing:
        raise VfxError(f"archive is missing required entries: {', '.join(missing)}")

    DEST_DIR.mkdir(parents=True, exist_ok=True)
    assets: dict[str, dict] = {}
    sprite_roles: dict[str, list[str]] = {}
    rows: list[tuple[str, str, str, str, str, str]] = []
    opaque_entries: list[str] = []
    alpha_without_flag: list[str] = []

    for target in TARGETS:
        entry = by_name[target.entry]
        blob = archive[entry.absolute_offset:entry.absolute_offset + entry.size]
        header, image = decode_dds(blob, entry.name)
        stats = alpha_stats(image)
        if stats["opaque"] and target.blend != "additive":
            raise VfxError(
                f"{entry.name}: fully opaque sprite without additive blending; "
                "either mark it additive or verify the decode"
            )
        if not stats["opaque"] and target.blend == "additive":
            raise VfxError(f"{entry.name}: additive sprite unexpectedly has transparency")
        if stats["opaque"]:
            opaque_entries.append(entry.name)
        elif not header.alpha_flag:
            alpha_without_flag.append(entry.name)
        path = DEST_DIR / png_name(entry.name)
        if path.exists():
            existing = read_png_rgba(path)
            if existing.size != image.size:
                raise VfxError(
                    f"{path}: existing PNG is {existing.size}, expected {image.size}"
                )
            if existing.tobytes() != image.tobytes():
                if verify_only:
                    raise VfxError(f"{path}: pixels do not match the DDS base mip level")
                path.write_bytes(encode_png(image))
            elif force and not verify_only:
                path.write_bytes(encode_png(image))
        else:
            if verify_only:
                raise VfxError(f"{path}: missing PNG")
            path.write_bytes(encode_png(image))

        png_bytes = path.read_bytes()
        # Re-read the final file: the manifest must describe what is on disk.
        final_image = read_png_rgba(path)
        if final_image.tobytes() != image.tobytes():
            raise VfxError(f"{path}: PNG round trip changed the pixels")

        asset = {
            "entry": entry.name,
            "entry_index": entry.index,
            "dds_size_bytes": entry.size,
            "dds_sha256": sha256_bytes(blob),
            "dds_format": header.fourcc,
            "dds_alpha_flag": header.alpha_flag,
            "width": header.width,
            "height": header.height,
            "mip_levels": header.mip_levels,
            "blend": target.blend,
            "alpha": stats,
            "png_size_bytes": len(png_bytes),
            "png_sha256": sha256_bytes(png_bytes),
        }
        assets[png_name(entry.name)] = asset
        sprite_roles[png_name(entry.name)] = list(target.roles)
        rows.append((
            entry.name,
            str(entry.index),
            header.fourcc,
            f"{header.width}x{header.height}",
            f"{stats['min']}-{stats['max']}",
            png_name(entry.name),
        ))

    hash_owners: dict[str, list[str]] = {}
    for filename, asset in assets.items():
        hash_owners.setdefault(str(asset["dds_sha256"]), []).append(str(asset["entry"]))
    duplicate_notes = []
    for owners in hash_owners.values():
        if len(owners) > 1:
            duplicate_notes.append(
                " y ".join(owners) + " son idénticos byte a byte en el archivo; "
                "se conservan todos los nombres."
            )

    notes = [
        f"El archivo contiene {len(entries)} entradas; el manifiesto registra las "
        f"{len(TARGETS)} que usa el VFX.",
        "Solo se guarda el nivel 0 de mip como PNG RGBA; la cadena de mips se valida "
        "en el DDS de origen.",
    ]
    notes.extend(duplicate_notes)
    notes.append(
        "Los sprites con alfa 255 en todo el mapa se dibujan con mezcla aditiva en el "
        "runtime: " + ", ".join(opaque_entries) + "."
    )
    if alpha_without_flag:
        notes.append(
            "El flag DDPF_ALPHAPIXELS no está activo en "
            + ", ".join(alpha_without_flag)
            + "; el PNG conserva el alfa decodificado del bloque DXT5."
        )

    manifest = {
        "source": MANIFEST_SOURCE,
        "archive_sha256": sha256_bytes(archive),
        "archive_format": {
            "signature": ARCHIVE_SIGNATURE.decode("ascii"),
            "entry_count": len(entries),
            "entry_table_offset": ENTRY_TABLE_OFFSET,
            "entry_size_bytes": ENTRY_SIZE,
            "data_offset": data_offset,
            "dds_formats": sorted({str(asset["dds_format"]) for asset in assets.values()}),
        },
        "generator": {
            "tool": "tools/rally/extract_cmr4_vfx.py",
            "version": TOOL_VERSION,
            "decoder": f"Pillow {PIL_VERSION}",
            "png_mode": "RGBA",
            "mip_level": 0,
            "deterministic": True,
        },
        "assets": assets,
        "sprite_roles": sprite_roles,
        "notes": notes,
    }

    if verbose:
        print(f"entry                    index  fmt   size      alpha     png")
        for row in rows:
            print(f"{row[0]:24s} {row[1]:>5s}  {row[2]:4s}  {row[3]:8s}  {row[4]:8s}  {row[5]}")

    if not verify_only:
        serialized = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
        MANIFEST_PATH.write_bytes(serialized.encode("utf-8"))
        print(f"MANIFEST_WRITTEN {MANIFEST_PATH} assets={len(assets)}")
    return manifest


def verify_manifest(expected: dict) -> None:
    if not MANIFEST_PATH.exists():
        raise VfxError(f"manifest not found: {MANIFEST_PATH}")
    try:
        actual = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise VfxError(f"{MANIFEST_PATH}: invalid JSON: {exc}") from exc
    # The generator block records the toolchain that produced the files; a
    # different Pillow build can be legitimate when the pixel contract holds.
    expected_contract = {key: value for key, value in expected.items() if key != "generator"}
    actual_contract = {key: value for key, value in actual.items() if key != "generator"}
    if actual_contract != expected_contract:
        differences = []
        for key in sorted(set(expected_contract) | set(actual_contract)):
            if expected_contract.get(key) != actual_contract.get(key):
                differences.append(key)
        raise VfxError(
            "manifest is out of date (different: " + ", ".join(differences) + ")"
        )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Extract the CMR4 rally VFX sprites and update manifest.json.",
    )
    parser.add_argument(
        "--source-root",
        type=Path,
        default=None,
        help="CMR4 installation root (default: %%CMR4_ROOT%% or %s)" % DEFAULT_CMR4_ROOT,
    )
    parser.add_argument(
        "--verify-only",
        action="store_true",
        help="Compare the existing PNGs and manifest without writing anything.",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Re-encode every PNG even when its pixels already match.",
    )
    parser.add_argument("--quiet", action="store_true", help="Only print the result.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        archive_path = resolve_archive(args.source_root)
        print(f"SOURCE {archive_path}")
        manifest = extract(
            archive_path,
            force=args.force,
            verify_only=args.verify_only,
            verbose=not args.quiet,
        )
        if args.verify_only:
            verify_manifest(manifest)
            print(
                f"VERIFY_OK assets={len(manifest['assets'])} "
                f"archive_sha256={manifest['archive_sha256']}"
            )
        else:
            print(
                f"EXTRACT_OK assets={len(manifest['assets'])} "
                f"archive_sha256={manifest['archive_sha256']}"
            )
        return 0
    except VfxError as exc:
        print(f"ERROR {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
