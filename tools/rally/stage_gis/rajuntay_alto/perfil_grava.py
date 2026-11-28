"""Apply authored CDI gravel zones to the shared road generator."""
from bisect import bisect_left, bisect_right
import json
import random

from relieve_piloto import ROAD_COLUMNS, RoadRelief, smoothstep


def envelope(station, bounds, fade_m):
    start, end = bounds
    return smoothstep(min(station - start, end - station) / fade_m)


def dome(station, bounds, skew=0.0):
    """A lobe with zero displacement, slope and curvature at both ends."""
    start, end = bounds
    t = (station - start) / (end - start)
    if not 0 < t < 1:
        return 0.0
    t += skew * t * (1 - t)
    return (4 * t * (1 - t)) ** 3


def cumulative_length(axis):
    distance = [0.0]
    for a, b in zip(axis, axis[1:]):
        distance.append(distance[-1] + (b - a).length)
    return distance


def interpolate_station(value, source, target):
    i = bisect_left(source, value)
    if i == 0:
        return target[0]
    if i == len(source):
        return target[-1]
    t = (value - source[i - 1]) / (source[i] - source[i - 1])
    return target[i - 1] + t * (target[i] - target[i - 1])


def set_pits(relief, pairs):
    ordered = sorted(pairs, key=lambda pair: pair[0][0])
    relief.pits = [pit for pit, _ in ordered]
    relief.features = [feature for _, feature in ordered]
    relief.centers = [pit[0] for pit in relief.pits]
    relief.longest = max((pit[2] for pit in relief.pits), default=0.0)


class GravelProfile:
    def __init__(self, path, reference_path):
        self.path = path
        self.config = json.loads(path.read_text(encoding="utf-8"))
        self.reference = json.loads(reference_path.read_text(encoding="utf-8"))

    def apply_grade(self, axis, gates, max_grade):
        first, last = gates
        stations = cumulative_length(axis)
        self.progress = [s - stations[first] for s in stations]
        deltas = [
            sum(patch["height_m"] * dome(s, patch["range_m"], patch.get("skew", 0.0))
                for patch in self.config["grade"])
            if first < i < last else 0.0
            for i, s in enumerate(self.progress)
        ]
        for a, b, da, db in zip(axis, axis[1:], deltas, deltas[1:]):
            if da == db:
                continue
            run = (b - a).xy.length
            if abs(db - da) > 0.015 * run or abs(b.z - a.z + db - da) > max_grade * run:
                raise ValueError(f"{self.path.name}: authored elevation exceeds grade limits")
        for point, delta in zip(axis, deltas):
            point.z += delta

    def build_relief(self, rows, stations, pk, gates):
        options = self.config
        first, last = gates
        axis_stations = stations[6:6 + len(pk)]

        def remap(bounds, target):
            return tuple(interpolate_station(s, self.progress, target) for s in bounds)

        # Recreate the legacy scatter before selecting the part retained verbatim.
        exclusions = [
            {"from_pk_m": 0, "to_pk_m": pk[first] + 15},
            {"from_pk_m": pk[last] - 10, "to_pk_m": pk[-1]},
        ]
        reference_config = dict(self.reference, seed=options.get("reference_seed", options["seed"]),
                                zones=[], manual_features=[],
                                exclusion_zones=[{"from_pk_m": 0, "to_pk_m": 65}, exclusions[1]])
        reference = None
        reference_bounds = (0.0, 0.0)
        reference_pairs = []
        if "reference_m" in options:
            reference = RoadRelief(rows, stations, pk, config=reference_config)
            reference_bounds = remap(options["reference_m"], axis_stations)
            reference_pk = remap(options["reference_m"], pk)
            exclusions.append({"from_pk_m": reference_pk[0] - 2, "to_pk_m": reference_pk[1] + 2})
            reference_pairs = [
                (pit, feature) for pit, feature in zip(reference.pits, reference.features)
                if reference_bounds[0] <= pit[0] - pit[2] and pit[0] + pit[2] <= reference_bounds[1]
            ]
            set_pits(reference, reference_pairs)

        profiles = {}
        for name, density, depth in (("good", [0, 1], [.012, .025]),
                                     ("light", [2, 4], [.023, .045]),
                                     ("worn", [5, 8], [.035, .065]),
                                     ("rough", [9, 12], [.04, .07])):
            if name == "rough" and not options.get("rough_m"):
                continue
            base = self.reference["profiles"]["desgastado" if name in ("worn", "rough") else "compactado"]
            profiles[name] = dict(base, density_per_100m=density, depth_m=depth)
        zones = [
            {"from_pk_m": a, "to_pk_m": b, "profile": name}
            for name in ("good", "worn", "rough") for interval in options.get(f"{name}_m", [])
            for a, b in [remap(interval, pk)]
        ]
        config = dict(reference_config, seed=options["seed"], zones=zones, profiles=profiles,
                      default_profile="light", corrugations=[], crests=[], settlements=[], undulation_m=.006,
                      exclusion_zones=exclusions)
        if "pit_patches" in options:
            rng = random.Random(options["seed"])
            pits = []
            for patch in options["pit_patches"]:
                start, end = patch["range_m"]
                interval = (end - start) / patch["count"]
                for i in range(patch["count"]):
                    progress = start + (i + rng.uniform(.18, .82)) * interval
                    pits.append(dict(
                        pk_m=interpolate_station(progress, self.progress, pk),
                        lateral_fraction=patch["lateral_fraction"] + rng.uniform(-.04, .04),
                        length_m=rng.uniform(.85, 1.55), width_m=rng.uniform(.55, .95),
                        depth_m=rng.uniform(*patch["depth_m"]),
                    ))
            config.update(manual_features=pits, undulation_m=0.0,
                          exclusion_zones=[*exclusions, {"from_pk_m": pk[0], "to_pk_m": pk[-1],
                                                         "procedural_only": True}])
        generated = RoadRelief(rows, stations, pk, config=config)
        if "pit_patches" in options and len(generated.pits) != len(pits):
            raise ValueError(f"{self.path.name}: one or more asphalt pits did not fit")
        # Check every 100 m window that would contain a candidate, including
        # windows spanning the transition out of the preserved opening.
        accepted = []
        occupied = sorted(pit[0] for pit, _ in reference_pairs)
        for pit, feature in zip(generated.pits, generated.features):
            s = pit[0]
            starts = occupied[bisect_left(occupied, s - 100):bisect_right(occupied, s)] + [s]
            if any(bisect_left(occupied, a + 100) - bisect_left(occupied, a)
                   >= options["maximum_pits_per_100m"] for a in starts if s < a + 100):
                continue
            occupied.insert(bisect_right(occupied, s), s)
            accepted.append((pit, feature))
        set_pits(generated, accepted)
        assert all(bisect_left(occupied, s + 100) - i <= options["maximum_pits_per_100m"]
                   for i, s in enumerate(occupied))
        return ProfiledRoad(
            reference, generated, reference_bounds, axis_stations[first], axis_stations[last],
            [remap(bounds, axis_stations) for bounds in options.get("good_m", [])],
            [(remap(p["range_m"], axis_stations), p) for p in options["crown"]],
            [(remap(p["range_m"], axis_stations), p) for p in options["settlement"]],
        )


class ProfiledRoad(RoadRelief):
    def __init__(self, reference, generated, reference_bounds, start, finish, good, crowns, settlements):
        self.reference = reference
        self.generated = generated
        self.reference_bounds = reference_bounds
        self.race_bounds = (start, finish)
        self.good = good
        self.crowns = crowns
        self.settlements = settlements
        self.start_station = generated.start_station
        self.seed = generated.seed
        self.max_depth = generated.max_depth
        start, end = reference_bounds
        self.corrugations = [p for p in (reference.corrugations if reference else [])
                             if start < p["end_m"] + self.start_station
                             and p["start_m"] + self.start_station < end]
        self.crests = [p for p in (reference.crests if reference else [])
                       if start < p["center_m"] + self.start_station < end]
        reference_pairs = list(zip(reference.pits, reference.features)) if reference else []
        set_pits(self, reference_pairs + list(zip(generated.pits, generated.features)))

    def height(self, station, t, half_width):
        blend = envelope(station, self.reference_bounds, 12.0)
        if blend == 1.0:
            return self.reference.height(station, t, half_width)
        good = max((envelope(station, bounds, 25.0) for bounds in self.good), default=0.0)
        race_fade = envelope(station, self.race_bounds, 15.0)
        z = race_fade * (1 - .55 * good) * self.generated.height(station, t, half_width)
        return z * (1 - blend) + blend * self.reference.height(station, t, half_width) if blend else z

    def section(self, row, station):
        points = super().section(row, station)
        active_crowns = [(envelope(station, bounds, 35.0), p) for bounds, p in self.crowns
                         if bounds[0] < station < bounds[1]]
        center = points[ROAD_COLUMNS // 2]
        left_width = (points[0] - center).xy.length
        right_width = (points[-1] - center).xy.length
        for i, point in enumerate(points):
            t = 2 * i / ROAD_COLUMNS - 1
            fraction = abs(t)
            half_width = left_width if t < 0 else right_width
            # Round the existing 2.5% centre-to-edge crown. Heights at both
            # road edges and at the centre match the shared corridor.
            for weight, patch in active_crowns:
                rounded = .025 * half_width * fraction * (1 - fraction) ** 2
                drift = patch["bias_m"] * t * (1 - t * t) ** 2
                point.z += weight * (rounded + drift)
            for bounds, patch in self.settlements:
                u = (t - patch["lateral_fraction"]) / patch["half_width_fraction"]
                if abs(u) < 1:
                    point.z += patch["height_m"] * dome(station, bounds) * (1 - u * u) ** 2
        return points
