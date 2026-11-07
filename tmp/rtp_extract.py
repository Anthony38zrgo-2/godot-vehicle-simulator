import pathlib, struct, sys, zlib
sys.path.insert(0, r"D:\rust-godot-vehicle-simulator\tools")
from rally_trophy.archives import KEY, PREFIX
def x(b):
    return bytes(v ^ KEY[i % 256] for i, v in enumerate(b))
OUT = pathlib.Path(r"D:\rust-godot-vehicle-simulator\tmp\porsche_mod\extracted")
for zname in ["Porsche356bT6Carrera.rtp", "Porsche356bT6CoupeFTC_v30.rtp"]:
    data = (pathlib.Path(r"D:\rust-godot-vehicle-simulator\tmp\porsche_mod") / zname).read_bytes()
    dl = data[1]; pos = 2 + dl
    n = data[pos]; pos += 1
    variant = "std" if "T6Carrera" in zname and "FTC" not in zname else "ftc"
    dest = OUT / variant
    dest.mkdir(parents=True, exist_ok=True)
    ok = 0
    for i in range(n):
        nl = data[pos]; pos += 1
        name = data[pos:pos+nl].decode("latin1"); pos += nl
        a, b, c = struct.unpack_from("<III", data, pos); pos += 12
        got = None
        for ln in dict.fromkeys([b, c]):
            if a + ln > len(data) or ln <= 0 or ln > 30_000_000:
                continue
            blob = x(data[a:a+ln])
            cand = None
            if blob[:2] in (b"\x78\x01", b"\x78\x9c", b"\x78\xda"):
                try:
                    cand = zlib.decompress(blob)
                except Exception:
                    cand = None
            else:
                cand = blob
            if cand is not None:
                if cand.startswith(PREFIX):
                    cand = cand[len(PREFIX):]
                got = cand
                break
        if got is None:
            print(f"  FAIL {variant}/{name} off={a} B={b} C={c}")
            continue
        (dest / name).write_bytes(got)
        ok += 1
    print(zname, "->", ok, "files in", dest)
