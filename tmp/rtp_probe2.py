import pathlib, re, zlib
for zname in ["Porsche356bT6Carrera.rtp"]:
    data = (pathlib.Path(r"D:\rust-godot-vehicle-simulator\tmp\porsche_mod") / zname).read_bytes()
    print("len", len(data))
    for pat in [b"RIFF", b"TorqueMax", b"Engine.ini", b"BMF", b"[Engine]", b"car.ini", b"Gear1Ratio", b"IdleRpm"]:
        idx = [m.start() for m in re.finditer(re.escape(pat), data)]
        print(f"{pat!r}: {idx[:12]}")
    # try zlib at guessed Engine.ini offset 407184
    for off, csize, usize in [(407184, 807, 2375), (406817, 1135, 4198444)]:
        try:
            dec = zlib.decompress(data[off:off+csize])
            print(f"zlib@{off}+{csize} -> {len(dec)} bytes, head={dec[:80]!r}")
        except Exception as e:
            print(f"zlib@{off} fail: {e}")
