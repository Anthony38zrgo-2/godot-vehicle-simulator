import pathlib, struct, sys, zlib
sys.path.insert(0, r"D:\rust-godot-vehicle-simulator\tools")
from rally_trophy.archives import KEY, PREFIX
def x(b):
    return bytes(v ^ KEY[i % 256] for i, v in enumerate(b))
for zname in ["Porsche356bT6Carrera.rtp", "Porsche356bT6CoupeFTC_v30.rtp"]:
    data = (pathlib.Path(r"D:\rust-godot-vehicle-simulator\tmp\porsche_mod") / zname).read_bytes()
    assert data[0] == 0x01
    dl = data[1]; d = data[2:2+dl].decode("latin1"); pos = 2+dl
    n = data[pos]; pos += 1
    print("="*10, zname, "dir=", d, "count=", n)
    entries = []
    for i in range(n):
        nl = data[pos]; pos += 1
        name = data[pos:pos+nl].decode("latin1"); pos += nl
        a, b, c = struct.unpack_from("<III", data, pos); pos += 12
        entries.append((name, a, b, c))
    print("dir_end=", pos, "file_len=", len(data))
    for name, a, b, c in entries:
        if name.lower().endswith((".ini",)):
            print(f"  {name}: off={a} X={b} Y={c}")
    # try Engine.ini both orders
    for name, a, b, c in entries:
        if name == "Engine.ini":
            for label, sl, us in [("X=csize", b, c), ("Y=csize", c, b)]:
                blob = x(data[a:a+sl])
                try:
                    dec = zlib.decompress(blob)
                    ok = dec[:60]
                except Exception as e:
                    try:
                        ok = b"RAW? " + blob[:60]
                    except Exception:
                        ok = b"fail"
                    dec = None
                print(f"  Engine.ini {label}: slice={sl} expect~={us} -> {ok!r}")
            break
