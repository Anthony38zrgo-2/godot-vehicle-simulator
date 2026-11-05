"""Compile game-derived profiles; engineering assumptions remain explicit."""
from __future__ import annotations

import copy
import math
from pathlib import Path

from .common import PACKAGE, read_json, write_json, sha


def deep_merge(target, patch):
    for key, value in patch.items():
        if isinstance(value, dict) and isinstance(target.get(key), dict):
            deep_merge(target[key], value)
        else:
            target[key] = copy.deepcopy(value)


def component(name, mass, position, inertia, attachment=None, wheel=None):
    return {"budget": "vehicle_and_driver", "component_perimeter": name,
            "properties": {"name": name, "mass_kilograms": mass,
                "attachment": attachment or {"kind": "body"},
                "center_of_mass_in_attachment_metres": dict(zip("xyz", position)),
                "inertia_about_center_of_mass": {"entries_kilogram_square_metres": [[inertia[0], 0, 0], [0, inertia[1], 0], [0, 0, inertia[2]]]},
                "provenance": {"source": "Explicit generated mass-budget estimate, not measured component masses",
                               "mass_origin": "estimated", "center_of_mass_origin": "estimated", "inertia_origin": "estimated"}},
            "rotating_wheel": wheel}


def compile_profile(recipe, configs, assets, history, destination):
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)
    documents = {p.name: read_json(p) for p in (PACKAGE / "templates/physics").glob("*.json")}
    info, car, engine = [configs[n]["values"] for n in ["info.ini", "car.ini", "Engine.ini"]]
    geometry = assets["geometry"]
    wheelbase = float(geometry["wheelbase"])
    radius = float(assets["wheel_pivots"]["front_left"]["radius_metres"])
    layout = recipe["engine_layout"]
    front_fraction = float(recipe.get("estimated_front_weight_fraction", 0.61 if car.get("FrontTraction", 0) else (0.40 if layout in ["rear", "mid"] else 0.52)))
    # Game Weight is kept as vehicle-only, dry budget; crew and equipment explicit.
    dry = float(info["Weight"])
    crew = float(recipe.get("crew_mass_kg", 150))
    tools = float(recipe.get("tools_mass_kg", 7))
    wheel_mass = float(recipe.get("wheel_mass_kg", car.get("TireMass", 20)))
    upright_mass = float(recipe.get("upright_mass_kg", 5))
    engine_mass = float(recipe.get("engine_mass_kg", 105 if info.get("EngineCyl", 4) == 4 else 150))
    body_mass = dry - engine_mass - 4 * (wheel_mass + upright_mass) - wheel_mass
    if body_mass <= 100:
        raise ValueError("Invalid generated mass budget")
    front_z, rear_z = geometry["front_axle_z"], geometry["rear_axle_z"]
    target_cg_z = rear_z - front_fraction * wheelbase
    engine_z = front_z * 0.8 if layout == "front" else rear_z * (1.15 if layout == "rear" else 0.45)
    parts = [component("body_and_systems", body_mass, (0, 0.48, target_cg_z),
                       (body_mass * 0.28, body_mass * 0.55, body_mass * 0.15)),
             component("engine_and_transaxle", engine_mass, (0, 0.40, engine_z), (12, 15, 10)),
             component("driver_and_seat", crew / 2, (-0.3, 0.60, 0), (8, 6, 5)),
             component("codriver_and_seat", crew / 2, (0.3, 0.60, 0), (8, 6, 5)),
             component("spare_wheels_and_tools", wheel_mass + tools, (0, 0.4, rear_z * 0.8), (3, 5, 3))]
    wheel_names = ["FrontLeft", "FrontRight", "RearLeft", "RearRight"]
    for name in wheel_names:
        parts.append(component(name + "_upright", upright_mass, (0, 0, 0), (0.1, 0.1, 0.1), {"kind": "upright", "wheel": name}))
        spin = max(0.55 * wheel_mass * radius * radius, 0.35)
        parts.append(component("wheel_" + name, wheel_mass, (0, 0, 0), (spin, spin * 0.6, spin * 0.6), {"kind": "wheel_rotor", "wheel": name}, name))
    # Shift the body estimate so the complete dry sprung inventory matches CG target.
    non_rotating = [p for p in parts if not p["rotating_wheel"]]
    sprung = [p for p in parts if p["properties"]["attachment"]["kind"] == "body"]
    mass_sum = sum(p["properties"]["mass_kilograms"] for p in sprung)
    weighted = sum(p["properties"]["mass_kilograms"] * p["properties"]["center_of_mass_in_attachment_metres"]["z"] for p in sprung)
    parts[0]["properties"]["center_of_mass_in_attachment_metres"]["z"] += (target_cg_z * mass_sum - weighted) / body_mass
    budget = sum(p["properties"]["mass_kilograms"] for p in non_rotating)
    documents["chassis.json"] = {"chassis": {"vehicle_name": recipe["display_name"], "vehicle_mass": budget,
        "vehicle_mass_excludes_wheel_assemblies": True, "front_weight_distribution": front_fraction,
        "inertia_multipliers": {"x": 1, "y": 1, "z": 1}}, "geometry": geometry,
        "physical_mass_inventory": {"schema_version": 2, "base_budget_kilograms": budget, "components": parts,
            "rim_and_tire_mass_kilograms": [wheel_mass] * 4,
            "spare_policy": {"mass_component_name": "spare_wheels_and_tools", "tools_mass_kg": tools, "wheel_mass_kg": wheel_mass}}}
    power = documents["powertrain.json"]["powertrain"]
    count = int(engine["NumGears"])
    power["gear_ratios"] = [float(engine[f"Gear{i}Ratio"][1]) for i in range(1, count + 1)]
    power["reverse_ratio"] = abs(float(engine["GearRRatio"][1]))
    power["final_drive"] = float(engine["EndRatio"])
    power["front_torque_split"] = float(car.get("FrontTraction", 0))
    power["max_torque"] = float(engine["TorqueMax"])
    power["idle_rpm"] = float(engine["IdleRpm"])
    torque = sorted((int(k[6:]), v) for k, v in engine.items() if k.startswith("Torque") and k[6:].isdigit())
    positive = [v[0] for _, v in torque if v[1] > 0]
    maximum = float(recipe.get("maximum_rpm", max(positive)))
    power["max_rpm"] = maximum
    power["torque_curve"] = [[float(v[0]) / maximum, float(v[1])] for _, v in torque]
    power["motor_moment"] = float(engine.get("InertiaEngine", 0.12))
    power["shift_time"] = float(engine.get("GearShiftTime", 0.15))
    power["clutch_release_seconds"] = float(engine.get("ClutchReleaseTime", 0.15))
    power["clutch_reengage_seconds"] = float(engine.get("ClutchEngageTime", 0.15))
    suspension = documents["suspension.json"]["suspension"]
    for axle in ["front", "rear"]:
        tune = suspension[axle]
        tune["spring_architecture"] = recipe.get("suspension", {}).get(axle, "equivalent_unverified")
        tune["spring_can_unseat"] = "leaf" not in tune["spring_architecture"]
        tune["ride_frequency_hz"] = float(recipe.get("ride_frequency_hz", {}).get(axle, 1.7 if axle == "front" else 1.8))
        tune["damping_ratio"] = 0.50
        tires = documents["tires.json"]["tires"][axle]
        pivot = assets["wheel_pivots"][axle + "_left"]
        tires.update(radius=pivot["radius_metres"], width=pivot["width_metres"], wheel_mass=wheel_mass)
    brakes = documents["brakes.json"]["brakes"]
    bias = car.get("BrakeBalance", [0.6, 0.55, 0.45])
    brakes["front_brake_bias"] = float(bias[1])
    brakes["max_brake_torque"] = float(car.get("BrakeTorque", 4300))
    fuel = documents["fuel.json"]["fuel"]
    # Unknown fuel tank size remains an explicit estimate, never a historical claim.
    fuel["capacity_kg"] = float(recipe.get("fuel_capacity_l", 40)) * 0.74
    fuel["initial_kg"] = min(fuel["capacity_kg"], 20)
    fuel["tank_position_local_m"] = {"x": 0, "y": 0.4, "z": front_z * 0.65 if layout == "rear" else rear_z * 0.7}
    documents["coupled_world.json"]["coupled_world"]["minimum_physics_ticks_per_second"] = 120
    if layout in ["rear", "mid"]:
        damage = documents["damage.json"]
        for section in ["collision", "landing"]:
            weights = damage.get(section, {}).get("zone_weights", {})
            if "nose" in weights and "rear" in weights:
                weights["nose"]["engine"], weights["rear"]["engine"] = weights["rear"].get("engine", 0.1), weights["nose"].get("engine", 1.0)
        damage["steam"]["local_position"] = [0, 0.5, engine_z]
    manifest = documents["vehicle.json"]
    manifest.update(vehicle_identifier=recipe["id"], profile_name=recipe["display_name"] + " — game-derived engineering profile")
    for name, patch in recipe.get("physics_overrides", {}).items():
        if name not in documents:
            raise ValueError(f"Unknown physics override document: {name}")
        deep_merge(documents[name], patch)
    for name, document in documents.items():
        write_json(destination / name, document)
    provenance = {"schema_version": 1, "vehicle_id": recipe["id"], "policy": recipe["physics_policy"],
        "source": "Rally Trophy Car.ini/Engine.ini + measured asset geometry; not a certified historic tune",
        "historical_reference": history, "engineering_estimates": [
            "Mass decomposition, crew, CG and inertia tensor", "Equivalent suspension rates and damping; no measured linkage reconstruction",
            "Fuel capacity unless explicitly overridden", "Aero, thermal, damage, tire force and filter template calibration"],
        "game_derived_fields": ["vehicle dry mass", "gear ratios", "final drive", "torque curve", "idle RPM", "front/rear drive", "brake settings"],
        "profile_json_sha256": {p.name: sha(p) for p in destination.glob("*.json") if p.name != "HISTORICAL_PROVENANCE.json"}}
    write_json(destination / "HISTORICAL_PROVENANCE.json", provenance)
    return provenance
