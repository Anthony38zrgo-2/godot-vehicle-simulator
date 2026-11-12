"""Deterministic, edge-faded surface relief for the Raura OSQP pilot."""
import math
import json
from pathlib import Path
import random
from bisect import bisect_left, bisect_right

from mathutils import Vector

SEED = 20261111
ROAD_COLUMNS = 40
ROAD_MAX_DEPTH_M = 0.13
SLOPE_MAX_RELIEF_M = 0.15
ROAD_STEP_M = 0.20


def smoothstep(x):
    t = min(1.0, max(0.0, x))
    return t * t * (3 - 2 * t)


def end_fade(station, total, length=14.0):
    return smoothstep(min(station, total - station) / length)


class RoadRelief:
    def __init__(self, rows, stations, pk, config_path=None, limit_pk=None):
        self.total = stations[-1]
        self.pits = []
        config_path = config_path or Path(__file__).with_name("desgaste_piloto.json")
        config = json.loads(config_path.read_text(encoding="utf-8-sig"))
        self.hard_impact = config.get("hard_impact", False)
        finish = min(pk[-1], limit_pk) if limit_pk is not None else pk[-1]
        self.corrugations = config.get("corrugations", [])
        self.crests = config.get("crests", [])
        self.settlements = config.get("settlements", [])
        self.start_station = stations[6]
        self.waves = config.get("undulation_m", 0.0)
        self.max_depth = config.get("max_combined_depression_m", ROAD_MAX_DEPTH_M)
        if config["schema_version"] != 1:
            raise ValueError("Unsupported wear profile schema")
        self.seed = config["seed"]
        self.features = []

        natural = config.get("natural_wear", False)
        shape_rng = random.Random(f"{self.seed}:shape")
        def add(pk_m, t, length, width, depth, profile, depth_offset_m=None, micro=False):
            if not pk[0]+12 <= pk_m <= finish-12:
                return
            if any(z["from_pk_m"] <= pk_m < z["to_pk_m"] and (profile != "manual" or not z.get("procedural_only", False)) for z in config["exclusion_zones"]):
                return
            if any(abs(pk_m - f["pk_m"]) < (0.65 if self.hard_impact else 1.2) and abs(t - f["lateral_fraction"]) < 0.35 for f in self.features):
                return
            i = bisect_left(pk, pk_m)
            fraction = (pk_m-pk[i-1]) / (pk[i]-pk[i-1])
            station = stations[i+5] + fraction * (stations[i+6]-stations[i+5])
            row = rows[i+6]
            half = (Vector(row[2 if t < 0 else 4])-Vector(row[3])).xy.length
            if abs(t)*half + width/2 > half-0.15:
                return
            asymmetry = 0.0
            if natural:
                limits = config["profiles"].get(profile, {}).get("depth_asymmetry_offset", [-.15, .15])
                offset = shape_rng.uniform(*limits) if depth_offset_m is None else depth_offset_m
                asymmetry = max(-.45, min(.45, offset / (width / 2)))
            micro_depth = min(.02, depth * .3) if micro else 0.0
            self.pits.append((station,t,length/2,width/2,depth,asymmetry,micro_depth))
            self.features.append(dict(pk_m=pk_m,lateral_fraction=t,length_m=length,width_m=width,
                                      depth_m=depth,profile=profile))
            if natural:
                self.features[-1].update(depth_offset_m=asymmetry * width / 2, micro_depth_m=micro_depth)

        for f in config["manual_features"]:
            add(f["pk_m"],f["lateral_fraction"],f["length_m"],f["width_m"],f["depth_m"],"manual",f.get("depth_offset_m"))
        zones = config["zones"]
        edges = sorted({pk[0],finish,*[v for z in zones for v in (z["from_pk_m"],z["to_pk_m"]) if pk[0]<v<finish]})
        if natural:
            self._scatter_natural(config, pk[0], finish, add)
        for a,b in ([] if natural else zip(edges,edges[1:])):
            profile = next((z["profile"] for z in zones if z["from_pk_m"] <= (a+b)/2 < z["to_pk_m"]), config["default_profile"])
            settings = config["profiles"][profile]
            rng = random.Random(f"{self.seed}:{a:.3f}:{b:.3f}:{profile}")
            size = settings.get("cluster_size", [2,2])
            chance = settings["cluster_probability"]
            expected_group = 1 + chance * (sum(size)/2 - 1) if "cluster_size" in settings else 1
            for n in range(round((b-a)*settings["density_per_100m"]/100/expected_group)):
                center = rng.uniform(a,b)
                side = rng.choice((-1,1))
                clustered = rng.random() < chance
                count = (rng.randint(*size) if self.corrugations or "cluster_size" in settings else 2) if clustered else 1
                for j in range(count):
                    pk_candidate = center + j*rng.uniform(*( (2.5,4.8) if self.corrugations or "cluster_size" in settings else (2,5) ))
                    if pk_candidate > b and "cluster_size" in settings:
                        pk_candidate = center - j*3.2
                    pit_side = side if not self.hard_impact or j % 3 != 2 else -side
                    add(min(b,max(a,pk_candidate)),pit_side*rng.uniform(.23,.59 if "cluster_size" in settings else .62),
                        rng.uniform(*settings["length_m"]),rng.uniform(*settings["width_m"]),
                        rng.uniform(*settings["depth_m"]),profile)
            if self.hard_impact:
                # Fill missing density across both wheel lines without touching
                # manually protected stretches. Bound retries in narrow sections.
                goal = round((b-a)*settings["density_per_100m"]/100)
                for wheel in (-1,1):
                    desired = (goal + int(wheel == 1)) // 2
                    for _ in range(max(1, desired * 18)):
                        existing = [f["pk_m"] for f in self.features
                                    if a <= f["pk_m"] < b and f["lateral_fraction"]*wheel > 0]
                        if len(existing) >= desired:
                            break
                        choices = [rng.uniform(a,b) for _ in range(8)]
                        center = max(choices, key=lambda x: min((abs(x-y) for y in existing), default=b-a))
                        add(center,wheel*rng.uniform(.24,.42),rng.uniform(*settings["length_m"]),
                            rng.uniform(*settings["width_m"]),rng.uniform(*settings["depth_m"]),profile)
        variants = config.get("size_variants", [])
        if variants:
            rng = random.Random(f"{self.seed}:pit-size")
            for i, (pit, feature) in enumerate(zip(self.pits, self.features)):
                if feature["profile"] == "manual":
                    continue
                choice = rng.choices(variants, weights=[v["weight"] for v in variants], k=1)[0]
                station, t, _, _, depth, asymmetry, micro_depth = pit
                length = rng.uniform(*choice["length_m"])
                width = rng.uniform(*choice["width_m"])
                row = rows[bisect_left(pk, feature["pk_m"]) + 6]
                half = (Vector(row[2 if t < 0 else 4])-Vector(row[3])).xy.length
                width = min(width, 2*(half*(1-abs(t))-.15))
                scale = choice["depth_scale"]
                depth *= rng.uniform(*scale) if isinstance(scale, list) else scale
                if natural:
                    limits = config["profiles"][feature["profile"]]["depth_m"]
                    depth = max(limits[0], min(limits[1], depth))
                    feature["depth_offset_m"] = asymmetry * width / 2
                self.pits[i] = (station,t,length/2,width/2,depth,asymmetry,micro_depth)
                feature.update(length_m=length,width_m=width,depth_m=depth,size_variant=choice["id"])

        self.rocks = []
        if self.hard_impact:
            rng = random.Random(self.seed + 17)
            for pk_m in range(18, int(finish)-18, 9):
                i = bisect_left(pk, pk_m)
                t = (pk_m-pk[i-1])/(pk[i]-pk[i-1])
                self.rocks.append((stations[i+5]+t*(stations[i+6]-stations[i+5]),
                                   rng.choice((-1,1))*rng.uniform(.20,.57), rng.uniform(.21,.34),
                                   rng.uniform(.23,.34),rng.uniform(.04,.075)))
        self.features = [feature for _, feature in sorted(zip(self.pits, self.features), key=lambda item: item[0])]
        self.pits.sort()
        self.centers = [pit[0] for pit in self.pits]
        self.longest = max((pit[2] for pit in self.pits), default=0.0)

    def _scatter_natural(self, config, start, finish, add):
        rng = random.Random(f"{self.seed}:natural")
        profiles = config["profiles"]
        default = config["default_profile"]
        maximum_density = max(p["density_per_100m"][1] for p in profiles.values())
        transition = 20.0
        # Independent random blocks vary local density without a fixed quota.
        for block in range(math.floor(start / 100), math.ceil(finish / 100)):
            a, b = max(start, block * 100), min(finish, (block + 1) * 100)
            density = {name: rng.uniform(*p["density_per_100m"]) for name, p in profiles.items()}
            center = a + rng.expovariate(maximum_density / 100)
            while center < b:
                profile = default
                for zone in config["zones"]:
                    weight = smoothstep(min(center - zone["from_pk_m"],
                                            zone["to_pk_m"] - center) / transition)
                    if weight > 0 and rng.random() < weight:
                        profile = zone["profile"]
                        break
                settings = profiles[profile]
                chance = settings["cluster_probability"]
                size = settings.get("cluster_size", [2, 2])
                expected = 1 + chance * (sum(size) / 2 - 1)
                if rng.random() < density[profile] / (maximum_density * expected):
                    count = rng.randint(*size) if rng.random() < chance else 1
                    track = rng.choice((-1, 1)) * rng.uniform(.24, .48)
                    for index in range(count):
                        jitter = rng.uniform(*settings["cluster_jitter_m"]) if index else 0
                        location = center + index * 1.65 + rng.choice((-1, 1)) * jitter
                        lateral = track + rng.uniform(-jitter, jitter) / 3
                        for patch in self.corrugations:
                            if patch["start_m"] <= location <= patch["end_m"]:
                                lateral = patch["lateral_fraction"] + rng.uniform(-.08, .08)
                                break
                        add(location, lateral, rng.uniform(*settings["length_m"]),
                            rng.uniform(*settings["width_m"]), rng.uniform(*settings["depth_m"]),
                            profile, micro=count >= 3 and rng.random() < .45)
                center += rng.expovariate(maximum_density / 100)

    def height(self, station, t, half_width):
        edge = smoothstep((1 - abs(t)) / 0.21)
        fade = end_fade(station, self.total) * edge
        if not fade:
            return 0.0
        track_offset = min(0.69, 0.78 / half_width)
        distance_to_track = (abs(t) - track_offset) * half_width
        rut = (0.013 + 0.005 * math.sin(station * 0.28) + 0.002 * math.sin(station * 0.67))
        depression = rut * math.exp(-((distance_to_track / 0.22) ** 2))
        if self.hard_impact:
            u = distance_to_track / .31
            rut_depth = .055 + .018*math.sin(station*.26+t) + .012*math.sin(station*.73)
            depression = rut_depth * (1 - 1.45*u*u)*math.exp(-u*u)
        lips = 0.0
        first = bisect_left(self.centers, station - self.longest)
        last = bisect_right(self.centers, station + self.longest)
        for pk, lateral, length, width, depth, asymmetry, micro_depth in self.pits[first:last]:
            if abs(station - pk) >= length:
                continue
            dx = station-pk
            v = (t-lateral)*half_width/width
            run = length*(.60 if self.hard_impact and dx>0 else 1.0)
            # Warp the bowl inside its footprint, keeping the rim continuous.
            shifted = (v - asymmetry) / (1 + asymmetry if v < asymmetry else 1 - asymmetry)
            r2 = (dx/run)**2+shifted*shifted
            if self.hard_impact and dx > 0:
                # Compact positive lip starts at zero, then returns to zero.
                u = (dx - .60*length)/(.39*length)
                if 0 < u < 1 and abs(v) < 1:
                    lips += .22*depth*math.sin(math.pi*u)**2*(1-v*v)**2
            if r2 < 1:
                depression += depth * (1 - r2) ** (1.35 if self.hard_impact else 2)
                if micro_depth:
                    pocket = ((dx / run - .28) / .32)**2 + ((shifted + .22) / .40)**2
                    depression += micro_depth * max(0, 1 - pocket)**2
        ripple = 0.004 * math.sin(station * 1.24 + t * 2.5) * math.sin(station * 0.53 - t * 4)
        waves = self.waves * (0.55 * math.sin(station * 0.91 + 2*t) +
                              0.30 * math.sin(station * 1.53 - 3*t) +
                              0.15 * math.sin(station * 0.66 + 4*t))
        distance = station - self.start_station
        for patch in self.settlements:
            delta = distance - patch["center_m"]
            entry = patch.get("entry_fraction", .5)
            u = delta / (patch["length_m"] * (entry if delta < 0 else 1-entry))
            v = (t-patch["lateral_fraction"])*half_width / .82
            r2 = u*u + v*v
            if r2 < 1:
                depression += patch["depth_m"] * (1-r2)**2
        for crest in self.crests:
            u = (distance-crest["center_m"]) / (crest["length_m"]/2)
            v = (t-crest["lateral_fraction"])*half_width / .75
            r2 = u*u + v*v
            if r2 < 1:
                waves += crest["height_m"] * (1-r2)**2
        for patch in self.corrugations:
            a,b = patch["start_m"],patch["end_m"]
            if a <= distance <= b:
                envelope = smoothstep(min(distance-a,b-distance)/3)
                lateral = math.exp(-(((t-patch["lateral_fraction"])*half_width)/patch.get("width_m",.86))**2)
                waves += patch["amplitude_m"] * envelope * lateral * math.sin(
                    2*math.pi*(distance-a)/patch["wavelength_m"] + t*.8)
        if self.hard_impact:
            for pk, lateral, length, width, height in self.rocks:
                if abs(station-pk) < length:
                    r2 = ((station-pk)/length)**2 + ((t-lateral)*half_width/width)**2
                    if r2 < 1:
                        lips += height*(1-r2)**2
            # Compress only large combined depressions, relative to the local surface.
            if self.max_depth <= .15:
                return fade * max(-self.max_depth, ripple + waves + lips - depression)
            if depression > .15:
                room = self.max_depth-.15
                depression = .15 + room * math.tanh((depression-.15)/room)
            return fade * (ripple+waves+lips-depression)
        return fade * max(-self.max_depth, ripple + waves - depression)

    def section(self, row, station):
        left, center, right = (Vector(row[i]) for i in (2, 3, 4))
        result = []
        for i in range(ROAD_COLUMNS + 1):
            t = 2 * i / ROAD_COLUMNS - 1
            edge = left if t < 0 else right
            v = center.lerp(edge, abs(t))
            v.z += self.height(station, t, (edge - center).xy.length)
            result.append(v)
        return result


class StartWear(RoadRelief):
    """Replace the first 700 m; blend back to the identical full-stage seed."""
    def __init__(self, rows, stations, pk, config, pothole_fraction=1.0):
        super().__init__(rows, stations, pk)
        self.start = RoadRelief(rows, stations, pk, config, limit_pk=700)
        i = bisect_left(pk,700)
        self.cutoff = stations[i+5] if pk[i] > 700 else stations[i+6]
        self.base = RoadRelief(rows, stations, pk)
        if pothole_fraction < 1.0:
            active = [(relief, i) for relief in (self.start, self.base)
                      for i, pit in enumerate(relief.pits)
                      if relief is self.start or pit[0] >= self.cutoff - 20]
            rng = random.Random(self.seed + 503)
            removed = set(rng.sample(active, len(active) - round(len(active) * pothole_fraction)))
            for relief in (self.start, self.base):
                kept = [(pit, feature) for i, (pit, feature) in enumerate(zip(relief.pits, relief.features))
                        if (relief, i) not in removed]
                relief.pits = [pit for pit, _ in kept]
                relief.features = [feature for _, feature in kept]
                relief.centers = [pit[0] for pit in relief.pits]
                relief.longest = max((pit[2] for pit in relief.pits), default=0.0)
        self.features = self.start.features + [f for f in self.base.features if f["pk_m"] >= 680]
        self.pits = sorted(self.start.pits + [p for p in self.base.pits if p[0] >= self.cutoff-20])
        self.centers = [p[0] for p in self.pits]
        self.longest = max(self.start.longest,self.base.longest)
        self.corrugations = self.start.corrugations
        self.crests = self.start.crests
        self.max_depth = self.start.max_depth

    def height(self, station, t, half_width):
        mix = smoothstep((self.cutoff-station)/20)
        if mix == 1:
            return self.start.height(station,t,half_width)
        baseline = self.base.height(station,t,half_width)
        if not mix:
            return baseline
        return baseline + mix*(self.start.height(station,t,half_width)-baseline)


def densify(rows, stations, relief):
    sections, dense_stations, originals = [], [], []
    for i, (a, b) in enumerate(zip(rows, rows[1:])):
        originals.append(len(sections))
        start, end = stations[i:i + 2]
        in_start = hasattr(relief,"cutoff") and start < relief.cutoff
        lookup = relief.base if hasattr(relief,"base") and not in_start else relief
        near_pit = bisect_left(lookup.centers, start - lookup.longest) < bisect_right(lookup.centers, end + lookup.longest)
        rough_patch = any(start <= p["end_m"] + relief.start_station and
                          end >= p["start_m"] + relief.start_station for p in relief.corrugations)
        crest_patch = any(start <= p["center_m"] + relief.start_station + p["length_m"]/2 and
                          end >= p["center_m"] + relief.start_station - p["length_m"]/2 for p in relief.crests)
        step = 0.12 if rough_patch or crest_patch or (in_start and near_pit) else 0.30 if in_start else ROAD_STEP_M if near_pit else 0.80
        count = max(1, math.ceil((end - start) / step))
        for j in range(count):
            t = j / count
            row = [Vector(x).lerp(Vector(y), t) for x, y in zip(a, b)]
            station = start + (end - start) * t
            sections.append(relief.section(row, station))
            dense_stations.append(station)
    originals.append(len(sections))
    sections.append(relief.section(rows[-1], stations[-1]))
    dense_stations.append(stations[-1])
    return sections, dense_stations, originals


def slope_section(shoulder, outer, station, total, side):
    """Round only the available slope width, leaving both tie lines exact."""
    reach = (outer - shoulder).xy.length
    fade = end_fade(station, total)
    # Keep the central slope planar. Round the first and last fraction by
    # integrating a slope that ramps up, holds steady, then ramps down.
    rounded = min(0.26, 0.5 / max(reach, 0.01))
    relief_scale = fade * smoothstep((reach - 0.35) / 0.95)
    wave = (0.09 * math.sin(0.44 * station + side) +
            0.04 * math.sin(1.03 * station - 2.1 * side) +
            0.02 * math.sin(1.71 * station + 4.6 * side))
    result = []
    for i in range(1, 8):
        t = i / 8
        if t < rounded:
            eased = t * t / (2 * rounded * (1 - rounded))
        elif t > 1 - rounded:
            eased = 1 - (1 - t) ** 2 / (2 * rounded * (1 - rounded))
        else:
            eased = (t - rounded / 2) / (1 - rounded)
        point = shoulder.lerp(outer, t)
        point.z += (outer.z - shoulder.z) * (eased - t) * fade
        point.z += relief_scale * wave * math.sin(math.pi * t) ** 2
        if outer.z > shoulder.z:
            depth = min(0.20, reach * 0.14)
            point.z -= depth * fade * math.sin(math.pi*t)**2 * (1-t)
        result.append(point)
    return result

def bank_sections(rows, stations):
    """Apply gradual signed crossfall without moving the center or tie lines."""
    headings = []
    for i in range(len(rows)):
        d = Vector(rows[min(i+1,len(rows)-1)][3])-Vector(rows[max(0,i-1)][3])
        headings.append(math.atan2(d.y,d.x))
    raw = []
    for i in range(len(rows)):
        a,b=max(0,i-4),min(len(rows)-1,i+4)
        angle=math.remainder(headings[b]-headings[a],2*math.pi)
        raw.append(max(-0.04,min(0.04,angle*0.9/max(1,stations[b]-stations[a]))))
    result=[]
    for i,row in enumerate(rows):
        nearby=[raw[j] for j in range(max(0,i-15),min(len(rows),i+16))
                if abs(stations[j]-stations[i]) <= 26]
        crossfall=sum(nearby)/len(nearby)*end_fade(stations[i],stations[-1],25)
        section=[list(p) for p in row]
        for k in range(1,6):
            offset=(Vector(row[k])-Vector(row[3])).xy.length
            section[k][2] += (-1 if k<3 else 1)*offset*crossfall
        result.append(section)
    return result
