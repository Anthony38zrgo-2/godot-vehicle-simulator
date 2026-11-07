import pathlib, sys, zlib
sys.path.insert(0, r"D:\rust-godot-vehicle-simulator\tools")
from rally_trophy.archives import KEY
data = (pathlib.Path(r"D:\rust-godot-vehicle-simulator\tmp\porsche_mod") / "Porsche356bT6Carrera.rtp").read_bytes()
for off, csize, usize in [(407184, 807, 2375), (1187565, 505, 1244), (408759, 91364, 91338)]:
    blob = data[off:off+csize]
    for align_label, align in [("zero", 0), ("off", off)]:
        x = bytes(v ^ KEY[(i+align) % 256] for i, v in enumerate(blob))
        for name, fn in [("zlib", lambda b: zlib.decompress(b))]:
            try:
                dec = fn(x)
                print(f"OK off={off} align={align_label}: {len(dec)} bytes head={dec[:100]!r}")
            except Exception as e:
                pass
    print(f"raw@{off}: {blob[:16].hex(' ')}")
