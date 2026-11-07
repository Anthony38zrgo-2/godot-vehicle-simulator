import re, pathlib
for zname in ["Porsche356bT6Carrera.rtp", "Porsche356bT6CoupeFTC_v30.rtp"]:
    raw = pathlib.Path(r"D:\rust-godot-vehicle-simulator\tmp\porsche_mod") / zname
    data = raw.read_bytes()
    print("=" * 20, zname, len(data))
    # find ini names
    for m in re.finditer(rb"[A-Za-z0-9_]+\.(ini|wav|tga|bmf)", data):
        s = max(0, m.start() - 14)
        print(f"@{m.start():7d} prev={data[s:m.start()].hex(' ')} name={m.group().decode()!r} next={data[m.end():m.end()+16].hex(' ')}")
        if m.start() > 900:
            break
