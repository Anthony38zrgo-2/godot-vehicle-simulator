from __future__ import annotations

import hashlib
import re
from pathlib import Path

from .archives import find_data, read_bzf, get
from .config_parser import parse_config


def inventory(source):
    data = find_data(source)
    cars = []
    for archive in sorted((data / "Cars").glob("car_*.bzf"), key=lambda p: int(re.search(r"\d+", p.stem)[0])):
        files = read_bzf(archive)
        configs = {name: parse_config(get(files, name) or b"") for name in ["info.ini", "car.ini", "Engine.ini", "Sounds.ini", "Tires.ini"]}
        info = configs["info.ini"]["values"]
        car = configs["car.ini"]["values"]
        engine = configs["Engine.ini"]["values"]
        cars.append({"archive": archive.name, "archive_sha256": hashlib.sha256(archive.read_bytes()).hexdigest(),
            "display_name": info.get("FullName"), "game_year": info.get("Year"),
            "game_info": info, "driver_type": car.get("DriverType"),
            "gear_count": engine.get("NumGears"),
            "drive": {"front": car.get("FrontTraction"), "rear": car.get("RearTraction")},
            "files": [{"name": name, "size": len(blob), "sha256": hashlib.sha256(blob).hexdigest()} for name, blob in files.items()],
            "configs": configs,
            "warnings": ["info.ini Transmission is an opaque game enum, not the number of gears.",
                         "Game Power/Weight are not verified historical racing measurements."]})
    return {"schema_version": 1, "source_data": str(data), "archive_count": len(cars), "cars": cars}
