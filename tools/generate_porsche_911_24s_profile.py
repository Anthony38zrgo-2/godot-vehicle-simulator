#!/usr/bin/env python3
"""
Generate the historical 1972-1973 Porsche 911 2.4 S (Type 911/53, F-Series LWB)
physics profile under game/data/vehicles/porsche-911-24s/ and its exact SHA-256 provenance.

Coordinate contract: -Z forward, +X right, +Y up, SI units.
Collision hulls are synced from game/assets/rally/porsche_911_24s/porsche_911_24s_collision.json.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROFILE_DIR = REPO / "game" / "data" / "vehicles" / "porsche-911-24s"
ASSET_DIR = REPO / "game" / "assets" / "rally" / "porsche_911_24s"


def write_json(path: Path, payload: dict) -> str:
    text = json.dumps(payload, indent=2, ensure_ascii=False) + "\n"
    path.write_text(text, encoding="utf-8")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def diag_inertia(ix: float, iy: float, iz: float) -> dict:
    return {"entries_kilogram_square_metres": [[ix, 0.0, 0.0], [0.0, iy, 0.0], [0.0, 0.0, iz]]}


def make_component(
    name: str,
    perimeter: str,
    budget: str,
    kind: str,
    mass_kg: float,
    com: tuple[float, float, float],
    inertia: tuple[float, float, float],
    source: str,
    wheel: str | None = None,
    rotating: bool = False,
    uncertainty_pct: float = 0.15,
) -> dict:
    att = {"kind": kind}
    if wheel is not None:
        att["wheel"] = wheel
    return {
        "budget": budget,
        "component_perimeter": perimeter,
        "properties": {
            "name": name,
            "mass_kilograms": mass_kg,
            "attachment": att,
            "center_of_mass_in_attachment_metres": {"x": com[0], "y": com[1], "z": com[2]},
            "inertia_about_center_of_mass": diag_inertia(*inertia),
            "provenance": {
                "mass_origin": "estimated",
                "center_of_mass_origin": "estimated",
                "inertia_origin": "estimated",
                "source": source,
                "center_of_mass_basis": "Local ground-plane / attachment coordinates; 1972-73 911 2.4 S packaging",
            },
        },
        "rotating_wheel": wheel if rotating else None,
        "uncertainty": {
            "lower_mass_kilograms": round(mass_kg * (1.0 - uncertainty_pct), 2),
            "upper_mass_kilograms": round(mass_kg * (1.0 + uncertainty_pct), 2),
            "center_uncertainty_metres": 0.10,
            "inertia_relative_uncertainty": 0.20,
            "rationale": "Historic 911 2.4 S component mass reconstruction",
        },
    }


def main() -> None:
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    coll_doc = json.loads((ASSET_DIR / "porsche_911_24s_collision.json").read_text(encoding="utf-8"))

    hashes: dict[str, str] = {}

    # 1. vehicle.json
    hashes["vehicle.json"] = write_json(
        PROFILE_DIR / "vehicle.json",
        {
            "schema_version": 1,
            "vehicle_identifier": "porsche_911_24s",
            "profile_name": "Porsche 911 2.4 S (1972-1973 F-Series, Type 911/53)",
            "units": "SI",
            "coordinate_contract": {
                "forward": "-Z",
                "right": "+X",
                "up": "+Y",
            },
            "domains": {
                "aerodynamics": "aerodynamics.json",
                "brakes": "brakes.json",
                "chassis": "chassis.json",
                "coupled_world": "coupled_world.json",
                "damage": "damage.json",
                "driving_assistance": "driving_assistance.json",
                "fuel": "fuel.json",
                "powertrain": "powertrain.json",
                "steering": "steering.json",
                "suspension": "suspension.json",
                "suspension_filters": "suspension_filters.json",
                "tires": "tires.json",
                "underfloor_contact": "underfloor_contact.json",
            },
        },
    )

    # 2. chassis.json (1050 kg DIN curb weight - 70 kg 4x wheels + 150 kg crew = 1130.0 kg non-wheel budget)
    components = [
        make_component(
            "bodywork_and_rollcage",
            "unitary 2+2 steel coupe shell, doors, glazing, 911 S front spoiler and trim",
            "vehicle_and_driver",
            "body",
            498.0,
            (0.0, 0.50, -0.05),
            (285.0, 345.0, 105.0),
            "Porsche 911 F-Series LWB unitary steel coupe body shell",
        ),
        make_component(
            "engine_type_911_53_2400",
            "2341 cc air-cooled flat-6 SOHC engine, Bosch MFI, dry-sump and cooling fan",
            "vehicle_and_driver",
            "body",
            195.0,
            (0.0, 0.41, 1.38),
            (18.0, 14.0, 15.0),
            "Porsche Type 911/53 2.4L air-cooled flat-6 rear-mounted behind rear axle",
        ),
        make_component(
            "transaxle_915_02_5spd_lsd",
            "magnesium-cased Type 915/02 5-speed transaxle, ZF LSD and halfshafts",
            "vehicle_and_driver",
            "body",
            56.0,
            (0.0, 0.34, 0.88),
            (4.0, 4.5, 2.8),
            "Porsche Type 915/02 5-speed manual transaxle",
        ),
        make_component(
            "driver",
            "crew driver",
            "vehicle_and_driver",
            "body",
            75.0,
            (-0.34, 0.43, 0.14),
            (7.5, 7.0, 3.5),
            "Crew allocation (driver)",
            uncertainty_pct=0.05,
        ),
        make_component(
            "co_driver",
            "crew co-driver",
            "vehicle_and_driver",
            "body",
            75.0,
            (0.34, 0.43, 0.16),
            (7.5, 7.0, 3.5),
            "Crew allocation (co-driver)",
            uncertainty_pct=0.05,
        ),
        make_component(
            "fuel_system_and_fluid",
            "62 L front fuel tank (partial load), pumps and lines",
            "vehicle_and_driver",
            "body",
            32.0,
            (0.0, 0.34, -1.25),
            (1.6, 2.2, 2.0),
            "Front-mounted 62L fuel tank and MFI lines",
        ),
        make_component(
            "oil_tank_and_cooler",
            "1972 forward-mounted dry-sump oil tank and front fender oil cooler",
            "vehicle_and_driver",
            "body",
            14.0,
            (0.48, 0.34, 0.72),
            (0.8, 0.9, 0.8),
            "1972-73 relocated dry-sump oil tank ahead of right rear wheel",
        ),
        make_component(
            "exhaust_and_heat_exchangers",
            "stainless/steel flat-6 dual heat exchangers and rear silencer",
            "vehicle_and_driver",
            "body",
            22.0,
            (-0.15, 0.25, 1.56),
            (1.0, 1.6, 1.4),
            "Porsche 911 2.4 S twin heat-exchanger exhaust system",
        ),
        make_component(
            "front_torsion_subframe",
            "front crossmember, MacPherson struts, 19 mm torsion bars and ZF rack",
            "vehicle_and_driver",
            "body",
            48.0,
            (0.0, 0.28, -1.1355),
            (2.0, 7.0, 6.0),
            "Front MacPherson + longitudinal 19 mm torsion-bar suspension crossmember",
        ),
        make_component(
            "rear_semi_trailing_subframe",
            "rear torsion tube, semi-trailing arms, 23 mm torsion bars and shocks",
            "vehicle_and_driver",
            "body",
            46.0,
            (0.0, 0.29, 1.1355),
            (2.0, 6.8, 5.5),
            "Rear semi-trailing arm + transverse 23 mm torsion-bar suspension",
        ),
        make_component(
            "sump_and_underbody_protection",
            "rear engine crankcase skid guard",
            "vehicle_and_driver",
            "body",
            20.0,
            (0.0, 0.19, 1.15),
            (1.4, 2.0, 1.0),
            "Rear crankcase skid plate",
        ),
        make_component(
            "spare_wheels_and_tools",
            "front luggage compartment spare wheel and jack/tools",
            "vehicle_and_driver",
            "body",
            25.0,
            (0.0, 0.38, -1.35),
            (1.0, 1.0, 1.6),
            "Front boot spare 15-inch wheel/tire (17.5 kg) + tools (7.5 kg)",
        ),
    ]
    # Fixed sum: 498+195+56+75+75+32+14+22+48+46+20+25 = 1106.0 kg
    # + 4 * 6.0 kg uprights (24.0 kg) = 1130.0 kg exact!
    for corner in ("FrontLeft", "FrontRight", "RearLeft", "RearRight"):
        components.append(
            make_component(
                f"upright_{corner.lower()}",
                f"upright assembly {corner}",
                "vehicle_and_driver",
                "upright",
                6.0,
                (0.0, 0.0, 0.0),
                (0.10, 0.10, 0.10),
                "Forged strut/trailing-arm upright, alloy caliper and vented disc hub",
                wheel=corner,
                rotating=False,
            )
        )
    for corner in ("FrontLeft", "FrontRight", "RearLeft", "RearRight"):
        components.append(
            make_component(
                f"wheel_{corner.lower()}",
                f"wheel_assembly_{corner.lower()}",
                "rim_and_tire",
                "wheel_rotor",
                17.5,
                (0.0, 0.0, 0.0),
                (0.95, 0.55, 0.55),
                "6Jx15 Fuchs forged alloy rim + 185/70 VR 15 tire",
                wheel=corner,
                rotating=True,
                uncertainty_pct=0.10,
            )
        )

    hashes["chassis.json"] = write_json(
        PROFILE_DIR / "chassis.json",
        {
            "chassis": {
                "vehicle_name": "Porsche 911 2.4 S (1972-1973)",
                "vehicle_mass": 1130.0,
                "vehicle_mass_excludes_wheel_assemblies": True,
                "front_weight_distribution": 0.415,
                "center_of_gravity_height_offset": -0.145,
                "inertia_multipliers": {"x": 1.0, "y": 1.0, "z": 1.0},
                "target_cg_z_m": 0.455,
            },
            "geometry": {
                "wheelbase": 2.271,
                "front_track": 1.372,
                "rear_track": 1.354,
                "front_axle_z": -1.1355,
                "rear_axle_z": 1.1355,
            },
            "physical_mass_inventory": {
                "schema_version": 2,
                "base_budget_kilograms": 1130.0,
                "rim_and_tire_mass_kilograms": [17.5, 17.5, 17.5, 17.5],
                "coordinate_contract": {"forward": "-Z", "right": "+X", "up": "+Y"},
                "spare_policy": {
                    "mass_component_name": "spare_wheels_and_tools",
                    "tools_mass_kg": 7.5,
                    "wheel_mass_kg": 17.5,
                },
                "components": components,
            },
        },
    )

    # 3. powertrain.json (Type 911/53 2341 cc MFI flat-6: 190 CV @ 6500 rpm, 216 Nm @ 5200 rpm; Type 915/02 5-speed RR)
    hashes["powertrain.json"] = write_json(
        PROFILE_DIR / "powertrain.json",
        {
            "powertrain": {
                "automatic_shift": {
                    "downshift_coast_normalized_rpm": 0.28,
                    "downshift_normalized_rpm_full_throttle": 0.64,
                    "downshift_normalized_rpm_low_throttle": 0.44,
                    "downshift_target_rpm_margin_high": 0.88,
                    "downshift_throttle_aggression_factor": 0.4,
                    "kickdown_delay_factor": 0.7,
                    "parked_resume_speed_ms": 1.0,
                    "reverse_max_speed_ms": 10.0,
                    "road_spin_weight": 0.4,
                    "upshift_coast_normalized_rpm": 0.44,
                    "upshift_normalized_rpm_full_throttle": 0.94,
                    "upshift_normalized_rpm_low_throttle": 0.66,
                    "upshift_target_rpm_margin_high": 0.94,
                    "wheel_road_spin_blend_threshold_rads": 8.0,
                    "wheel_spin_weight": 0.6,
                },
                "automatic_transmission": False,
                "clutch_release_seconds": 0.04,
                "clutch_reengage_seconds": 0.12,
                "synchronizer_capacity_nm": 36.0,
                "synchronizer_tolerance_rad_s": 0.13,
                "clutch_out_rpm_offset": 300.0,
                "constant_brake_ratio": 0.012,
                "differential": {
                    "type": "clutch_lsd",
                    "preset_id": "porsche_915_zf_40",
                    "clutch_friction_coefficient": 0.10,
                    "clutches": 4.0,
                    "coast_ramp_angle_deg": 55.0,
                    "power_ramp_angle_deg": 45.0,
                    "preload_nm": 45.0,
                    "slip_transition_threshold_rad_s": 4.0,
                    "lock_pct_power": 40.0,
                    "lock_pct_coast": 40.0,
                    "coast_friction_coefficient": 0.08,
                },
                "downshift_blip_torque_fraction": 0.82,
                "downshift_blip_response_seconds": 0.038,
                "downshift_blip_tolerance_rpm": 25.0,
                "downshift_clutch_reengagement_seconds": 0.11,
                "downshift_maximum_target_revolutions_per_minute_fraction": 0.93,
                "downshift_minimum_interval_seconds": 0.20,
                "downshift_rev_matching_enabled": False,
                "driveline_compliance": {
                    "enabled": True,
                    "output_inertia_kg_m2": 0.20,
                    "stiffness_nm_per_rad": 9200.0,
                    "damping_nms_per_rad": 135.0,
                },
                "final_drive": 4.429,
                "final_drive_gravel": 4.429,
                "final_drive_tarmac": 4.429,
                "final_drive_preset": "gravel",
                "front_torque_split": 0.0,
                "gear_inertia": 0.024,
                "gear_ratios": [3.182, 1.833, 1.261, 0.960, 0.759],
                "handbrake_torque_fraction": 1.0,
                "idle_disengagement_hysteresis_rpm": 120.0,
                "idle_rpm": 900.0,
                "max_clutch_torque_ratio": 1.45,
                "max_rpm": 7200.0,
                "max_torque": 216.0,
                "motor_moment": 0.125,
                "reverse_ratio": 3.325,
                "shift_time": 0.14,
                "thermal": {
                    "engine_block_heat_capacity_joules_per_kelvin": 72000.0,
                    "engine_block_heat_fraction": 0.1,
                    "engine_to_oil_conductance_watts_per_kelvin": 420.0,
                    "engine_to_water_conductance_watts_per_kelvin": 880.0,
                    "exhaust_heat_fraction": 0.6,
                    "heat_generation_per_mechanical_power": 1.48,
                    "idle_heat_generation_watts": 12500.0,
                    "initial_engine_block_temperature_celsius": 88.0,
                    "initial_oil_temperature_celsius": 90.0,
                    "initial_water_temperature_celsius": 85.0,
                    "minimum_hot_engine_torque_fraction": 0.85,
                    "oil_critical_temperature_celsius": 140.0,
                    "oil_heat_capacity_joules_per_kelvin": 22000.0,
                    "oil_heat_fraction": 0.12,
                    "oil_hot_derating_temperature_celsius": 128.0,
                    "oil_minimum_cold_engine_torque_fraction": 0.88,
                    "oil_optimal_maximum_temperature_celsius": 115.0,
                    "oil_optimal_minimum_temperature_celsius": 80.0,
                    "oil_pressure": {
                        "bar_per_rpm": 0.0012,
                        "hot_viscosity_factor": 0.64,
                        "low_ratio": 0.75,
                        "pressure_response_seconds": 0.22,
                        "relief_valve_bar": 5.2,
                        "viscosity_hot_celsius": 135.0,
                        "viscosity_reference_celsius": 90.0,
                        "warning_ratio": 0.5,
                        "warning_pressure_bar": 0.9,
                    },
                    "oil_sump_cooling_conductance_watts_per_kelvin": 18.0,
                    "oil_to_water_conductance_watts_per_kelvin": 260.0,
                    "water_cooling_duct": {
                        "air_specific_heat_joules_per_kilogram_kelvin": 1005.0,
                        "area_response_exponent": 1.0,
                        "base_cooling_conductance_watts_per_kelvin": 85.0,
                        "discharge_coefficient": 0.72,
                        "drag_coefficient": 0.5,
                        "heat_exchanger_conductance_watts_per_kelvin": 4200.0,
                        "maximum_inlet_area_square_meters": 0.22,
                        "opening": 0.12,
                        "pressure_recovery": 0.75,
                    },
                    "water_critical_temperature_celsius": 120.0,
                    "water_heat_capacity_joules_per_kelvin": 28000.0,
                    "water_heat_fraction": 0.18,
                    "water_hot_derating_temperature_celsius": 110.0,
                    "water_minimum_cold_engine_torque_fraction": 0.95,
                    "water_optimal_maximum_temperature_celsius": 98.0,
                    "water_optimal_minimum_temperature_celsius": 75.0,
                },
                "torque_attack_rate_nm_s": 2400.0,
                # Peak torque 216 Nm @ 5200 rpm (0.7222 * 7200); peak power 190 CV (139.7 kW) @ 6500 rpm (0.9028 * 7200)
                "torque_curve": [
                    [0.06, 0.0],
                    [0.1389, 0.52],
                    [0.2778, 0.68],
                    [0.4167, 0.80],
                    [0.5556, 0.90],
                    [0.6500, 0.97],
                    [0.7222, 1.00],
                    [0.8333, 0.98],
                    [0.9028, 0.9505],
                    [0.9722, 0.86],
                    [1.0000, 0.76],
                ],
                "variable_drag_ratio": 0.036,
            }
        },
    )

    # 4. suspension.json (MacPherson + 19mm torsion bars front, semi-trailing arm + 23mm torsion bars rear)
    hashes["suspension.json"] = write_json(
        PROFILE_DIR / "suspension.json",
        {
            "suspension": {
                "contact_shape_count": 1,
                "contact_query_type": "ShapeCast3D",
                "front": {
                    "spring_architecture": "torsion_bar",
                    "spring_can_unseat": True,
                    "arb_ratio": 0.18,
                    "bump_damp_multiplier": 1.0,
                    "bump_stop_multiplier": 1.0,
                    "camber": -0.01745,
                    "camber_gain_rad_per_m": -0.018,
                    "damping_ratio": 0.46,
                    "rebound_damp_multiplier": 1.35,
                    "resting_ratio": 0.35,
                    "spring_length": 0.30,
                    "toe": 0.001745,
                    "toe_gain_rad_per_m": 0.006,
                    "ride_frequency_hz": 1.55,
                },
                "rear": {
                    "spring_architecture": "torsion_bar",
                    "spring_can_unseat": True,
                    "arb_ratio": 0.14,
                    "bump_damp_multiplier": 1.0,
                    "bump_stop_multiplier": 1.0,
                    "camber": -0.02618,
                    "camber_gain_rad_per_m": -0.014,
                    "damping_ratio": 0.48,
                    "rebound_damp_multiplier": 1.35,
                    "resting_ratio": 0.35,
                    "spring_length": 0.30,
                    "toe": 0.002618,
                    "toe_gain_rad_per_m": 0.004,
                    "ride_frequency_hz": 1.65,
                },
                "geometry_physical": {
                    "version": 1,
                    "front": {
                        "arb_damper_Ns_per_m": 110.0,
                        "bump_stop_damper_Ns_per_m": 580.0,
                        "bump_stop_law": "cubic",
                        "bump_stop_mult": 1.0,
                        "bump_stop_travel_m": 0.025,
                        "damper_bump_Ns_per_m": 1850.0,
                        "damper_fast_factor": 0.55,
                        "damper_knee_blend_m_per_s": 0.02,
                        "damper_knee_m_per_s": 0.15,
                        "damper_max_m": 0.46,
                        "damper_min_m": 0.14,
                        "damper_rebound_Ns_per_m": 2450.0,
                        "hard_stop_compliance_m": 0.001,
                        "hard_stop_damper_Ns_per_m": 2500.0,
                        "hard_stop_overtravel_m": 0.005,
                        "hard_stop_stiffness_N_per_m": 8000000.0,
                        "spring_free_length_m": 0.30,
                        "spring_installed_length_m": 0.25,
                        "spring_rate_N_per_m": 22500.0,
                        "wheel_bump_m": 0.14,
                        "wheel_droop_m": 0.12,
                    },
                    "front_arb": {"mode": "legacy_ratio", "ratio": 0.18},
                    "rear": {
                        "arb_damper_Ns_per_m": 95.0,
                        "bump_stop_damper_Ns_per_m": 600.0,
                        "bump_stop_law": "cubic",
                        "bump_stop_mult": 1.0,
                        "bump_stop_travel_m": 0.025,
                        "damper_bump_Ns_per_m": 2400.0,
                        "damper_fast_factor": 0.60,
                        "damper_knee_blend_m_per_s": 0.02,
                        "damper_knee_m_per_s": 0.15,
                        "damper_max_m": 0.48,
                        "damper_min_m": 0.12,
                        "damper_rebound_Ns_per_m": 3200.0,
                        "hard_stop_compliance_m": 0.001,
                        "hard_stop_damper_Ns_per_m": 2500.0,
                        "hard_stop_overtravel_m": 0.005,
                        "hard_stop_stiffness_N_per_m": 8000000.0,
                        "spring_free_length_m": 0.30,
                        "spring_installed_length_m": 0.25,
                        "spring_rate_N_per_m": 31500.0,
                        "wheel_bump_m": 0.14,
                        "wheel_droop_m": 0.12,
                    },
                    "rear_arb": {"mode": "legacy_ratio", "ratio": 0.14},
                },
                "model": "geometric",
                "model_version": 1,
                "tri_ray_spacing_ratio": 0.35,
                "use_authored_wheel_centers": True,
                "virtual_unsprung_mass_multiplier": 1.15,
            }
        },
    )

    # 5. suspension_filters.json
    hashes["suspension_filters.json"] = write_json(
        PROFILE_DIR / "suspension_filters.json",
        {
            "suspension_filters": {
                "front": {"arb_travel_filter_tau_s": 0.001, "damper_velocity_filter_tau_s": 0.001},
                "rear": {"arb_travel_filter_tau_s": 0.001, "damper_velocity_filter_tau_s": 0.001},
                "road_height_filter_tau_s": 0.004,
                "road_height_max_rate_m_s": 15.0,
            }
        },
    )

    # 6. brakes.json (282.5 mm vented front / 290 mm vented rear discs, unassisted)
    hashes["brakes.json"] = write_json(
        PROFILE_DIR / "brakes.json",
        {
            "brakes": {
                "abs_pulse_time": 0.03,
                "abs_spin_diff_threshold": 10.0,
                "enable_abs": False,
                "front_brake_bias": 0.56,
                "max_brake_torque": 5200.0,
                "wheel_lock_blend_spin_rad_s": 6.0,
                "wheel_lock_stick_tau_s": 0.03,
                "servo_assist": {"enabled": False, "gain": 1.0},
                "thermal": {
                    "braking_heat_fraction": 0.95,
                    "cold_efficiency": 0.85,
                    "critical_temperature_c": 780.0,
                    "fade_start_temperature_c": 580.0,
                    "initial_temperature_c": 25.0,
                    "minimum_fade_efficiency": 0.54,
                    "optimal_max_temperature_c": 480.0,
                    "optimal_min_temperature_c": 140.0,
                    "front": {
                        "cooling_profile": "open_wheel_external_faces",
                        "installation_airflow_scale": 0.94,
                        "model": "scaled_two_node_v1",
                        "rim_base_air_w_k": 8.5,
                        "rim_heat_capacity_j_k": 3400.0,
                        "rim_to_tire_carcass_w_k": 35.0,
                        "rim_to_tire_gas_w_k": 25.0,
                        "rotor_inner_diameter_m": 0.165,
                        "rotor_mass_kg": 5.4,
                        "rotor_material": "cast_iron",
                        "rotor_outer_diameter_m": 0.2825,
                        "rotor_radiation_ambient_view_factor": 0.50,
                        "rotor_radiation_emissivity": 0.70,
                        "rotor_solar_soak_k": 0.02,
                        "rotor_to_rim_w_k": 12.0,
                        "rotor_ventilation": "vented",
                        "thermal_mass_scale": 1.0,
                    },
                    "front_duct": {
                        "air_specific_heat_j_kg_k": 1005.0,
                        "area_response_exponent": 1.0,
                        "cooling_flow_exponent": 0.75,
                        "cooling_reference_speed_ms": 35.0,
                        "discharge_coefficient": 0.65,
                        "drag_coefficient": 0.15,
                        "heat_exchanger_ua_w_k": 280.0,
                        "max_inlet_area_m2_per_wheel": 0.009,
                        "minimum_cooling_flow_ratio": 0.15,
                        "opening": 0.22,
                        "pressure_recovery": 0.62,
                        "rotor_cooling_fraction": 0.85,
                    },
                    "rear": {
                        "cooling_profile": "open_wheel_external_faces",
                        "installation_airflow_scale": 0.90,
                        "model": "scaled_two_node_v1",
                        "rim_base_air_w_k": 7.5,
                        "rim_heat_capacity_j_k": 3400.0,
                        "rim_to_tire_carcass_w_k": 25.0,
                        "rim_to_tire_gas_w_k": 18.0,
                        "rotor_inner_diameter_m": 0.170,
                        "rotor_mass_kg": 5.2,
                        "rotor_material": "cast_iron",
                        "rotor_outer_diameter_m": 0.290,
                        "rotor_radiation_ambient_view_factor": 0.42,
                        "rotor_radiation_emissivity": 0.70,
                        "rotor_solar_soak_k": 0.02,
                        "rotor_to_rim_w_k": 10.0,
                        "rotor_ventilation": "vented",
                        "thermal_mass_scale": 1.0,
                    },
                    "rear_duct": {
                        "air_specific_heat_j_kg_k": 1005.0,
                        "area_response_exponent": 1.0,
                        "cooling_flow_exponent": 0.75,
                        "cooling_reference_speed_ms": 35.0,
                        "discharge_coefficient": 0.65,
                        "drag_coefficient": 0.10,
                        "heat_exchanger_ua_w_k": 240.0,
                        "max_inlet_area_m2_per_wheel": 0.007,
                        "minimum_cooling_flow_ratio": 0.15,
                        "opening": 0.18,
                        "pressure_recovery": 0.58,
                        "rotor_cooling_fraction": 0.85,
                    },
                },
            }
        },
    )

    # 7. steering.json
    hashes["steering.json"] = write_json(
        PROFILE_DIR / "steering.json",
        {
            "steering": {
                "ackermann": 0.18,
                "countersteer_assist": 0.0,
                "front_steering_ratio": 1.0,
                "max_steering_angle": 0.56,
                "rear_steering_ratio": 0.0,
                "steering_exponent": 1.1,
                "steering_slip_assist": 0.0,
                "steering_speed": 5.2,
                "steering_speed_decay": 0.05,
                "speed_filter_start_kph": 20.0,
                "speed_filter_reference_kph": 65.0,
                "speed_filter_minimum_gain": 0.2,
                "turns_lock_to_lock": 3.1,
                "ratio_to_one": 17.78,
            }
        },
    )

    # 8. tires.json (185/70 VR 15 on 6Jx15 Fuchs -> R=0.320 m, W=0.195 m)
    hashes["tires.json"] = write_json(
        PROFILE_DIR / "tires.json",
        {
            "tires": {
                "front": {
                    "contact_patch": 0.195,
                    "radius": 0.320,
                    "rim_diameter_inches": 15.0,
                    "wheel_mass": 17.5,
                    "width": 0.195,
                    "nominal_section_width_m": 0.185,
                    "rolling_radius_m": 0.320,
                    "pressure_kpa": 180.0,
                    "compound": "gravel_normal",
                },
                "rear": {
                    "contact_patch": 0.195,
                    "radius": 0.320,
                    "rim_diameter_inches": 15.0,
                    "wheel_mass": 17.5,
                    "width": 0.195,
                    "nominal_section_width_m": 0.185,
                    "rolling_radius_m": 0.320,
                    "pressure_kpa": 190.0,
                    "compound": "gravel_normal",
                },
                "default_compound": "gravel_normal",
                "pressure": {
                    "cold_kpa_gauge": {"FL": 180.0, "FR": 180.0, "RL": 190.0, "RR": 190.0},
                    "reference_temperature_c": 25.0,
                },
            }
        },
    )

    # 9. aerodynamics.json (Cd 0.395, frontal area 1.80 m^2, 1972 911 S front chin spoiler)
    hashes["aerodynamics.json"] = write_json(
        PROFILE_DIR / "aerodynamics.json",
        {
            "aero": {
                "air_density": 1.225,
                "blend_full_speed_mps": 35.0,
                "blend_min_speed_mps": 5.0,
                "drag_coefficient": 0.395,
                "frontal_area": 1.80,
                "lag_tau_s": 0.04,
                "model": {
                    "body": {"drag_coefficient_scope": "whole_vehicle_reference", "wheel_reference_drag_area_m2": 0.08},
                    "front_wing": {
                        "area_m2": 0.12,
                        "incidence_deg": 3.0,
                        "max_angle_deg": 8.0,
                        "min_angle_deg": 0.0,
                        "polar": [
                            {"angle_deg": 0.0, "cd": 0.012, "cl": 0.03},
                            {"angle_deg": 4.0, "cd": 0.025, "cl": 0.09},
                            {"angle_deg": 8.0, "cd": 0.045, "cl": 0.15},
                        ],
                        "position_m": [0.0, -0.22, -1.90],
                        "yaw_decay_exponent": 1.0,
                    },
                    "limits": {
                        "hard_max_downforce_n": 380.0,
                        "hard_max_load_ratio": 1.06,
                        "profile": "saloon_rally",
                        "soft_max_load_ratio": 1.02,
                    },
                    "rear_wing": {
                        "area_m2": 0.08,
                        "incidence_deg": 1.5,
                        "max_angle_deg": 6.0,
                        "min_angle_deg": 0.0,
                        "polar": [
                            {"angle_deg": 0.0, "cd": 0.01, "cl": 0.02},
                            {"angle_deg": 3.0, "cd": 0.02, "cl": 0.05},
                            {"angle_deg": 6.0, "cd": 0.035, "cl": 0.09},
                        ],
                        "position_m": [0.0, 0.50, 1.85],
                        "yaw_decay_exponent": 1.0,
                    },
                    "underfloor": {
                        "bottoming_factor": 0.1,
                        "choke_height_m": 0.03,
                        "floor_clearance_front_m": 0.155,
                        "floor_clearance_rear_m": 0.165,
                        "high_height_m": 0.36,
                        "induced_drag_ratio": 0.05,
                        "lift_area_m2": 0.0,
                        "optimal_height_m": 0.16,
                        "optimal_rake_deg": 0.5,
                        "position_m": [0.0, -0.15, 0.0],
                        "rake_window_deg": 5.0,
                        "seal_asymmetry_m": 0.1,
                        "seal_roll_rad": 0.2,
                        "stall_attack_tau_s": 0.08,
                        "stall_recovery_tau_s": 0.12,
                        "throat_probe_offset_m": 0.0,
                        "yaw_decay_exponent": 1.0,
                    },
                    "wheels": {"front_drag_coefficient": 0.04, "rear_drag_coefficient": 0.04},
                },
            }
        },
    )

    # 10. fuel.json (62 L front tank @ 0.74 kg/L = 45.9 kg)
    hashes["fuel.json"] = write_json(
        PROFILE_DIR / "fuel.json",
        {
            "fuel": {
                "brake_specific_consumption_kg_per_kwh": 0.33,
                "capacity_kg": 45.9,
                "density_kg_per_litre": 0.74,
                "estimated_lap_consumption_kg": 2.4,
                "idle_consumption_kg_per_hour": 2.1,
                "initial_kg": 22.0,
                "reference_lap_time_s": 180.0,
                "tank_position_local_m": {"x": 0.0, "y": 0.34, "z": -1.25},
            }
        },
    )

    # 11. damage.json
    hashes["damage.json"] = write_json(
        PROFILE_DIR / "damage.json",
        {
            "schema_version": 1,
            "collision": {
                "minimum_speed_m_s": 4.0,
                "full_severity_speed_m_s": 23.0,
                "maximum_radiator_damage": 0.35,
                "maximum_engine_damage": 0.28,
                "maximum_transmission_damage": 0.3,
                "severity_exponent": 1.2,
                "min_impulse_speed_m_s": 1.5,
                "zone_weights": {
                    "nose": {"radiator": 0.35, "engine": 0.12},
                    "front_underbody": {"radiator": 0.35, "engine": 0.15},
                    "side": {"radiator": 0.25, "engine": 0.25},
                    "rear": {"radiator": 0.85, "engine": 1.0},
                },
            },
            "visual": {
                "headlight": 0.2,
                "windshield": 0.34,
                "windshield_frontal": 0.55,
                "hood": 0.42,
                "trunk": 0.42,
                "body": 0.8,
            },
            "wheel_collision": {
                "lateral_reach_m": 0.38,
                "radial_reach_margin_m": 0.14,
                "minimum_impulse_ns": 240.0,
                "puncture_speed_m_s": 5.25,
                "cut_speed_m_s": 13.0,
                "brake_damage_speed_m_s": 10.0,
                "full_brake_damage_speed_m_s": 22.0,
                "slow_leak_per_second": 0.045,
                "fast_leak_per_second": 2.0,
                "maximum_brake_loss_per_impact": 0.55,
                "minimum_brake_factor": 0.25,
                "rim_start_speed_m_s": 7.0,
                "rim_full_speed_m_s": 21.0,
                "alignment_start_speed_m_s": 10.0,
                "alignment_full_speed_m_s": 24.0,
                "maximum_toe_offset_deg": 6.0,
            },
            "landing": {
                "minimum_speed_m_s": 2.5,
                "full_severity_speed_m_s": 9.0,
                "maximum_radiator_damage": 0.08,
                "maximum_engine_damage": 0.10,
                "severity_exponent": 1.0,
                "zone_weights": {
                    "nose": {"radiator": 0.3, "engine": 0.15},
                    "front_underbody": {"radiator": 0.3, "engine": 0.2},
                    "front_wheels": {"radiator": 0.2, "engine": 0.15},
                    "rear_wheels": {"radiator": 0.3, "engine": 0.45},
                    "rear": {"radiator": 0.8, "engine": 1.0},
                },
            },
            "thermal": {
                "minimum_cooling_factor": 0.45,
                "minimum_torque_factor": 0.6,
                "oil_pressure_loss_at_full_engine_damage": 0.35,
                "permanent_minimum_torque_factor": 0.7,
                "damage_start_c": 115.0,
                "full_rate_temperature_c": 125.0,
                "grace_seconds": 6.0,
                "maximum_damage_per_second": 0.015,
                "recovery_rate_per_second": 2.0,
            },
            "steam": {
                "start_damage": 0.25,
                "continuous_damage": 0.5,
                "heavy_damage": 0.75,
                "local_position": [0.0, 0.55, 1.45],
                "max_intensity": 1.0,
                "bonnet_attenuation": 0.35,
                "cold_temperature_c": 75.0,
                "hot_temperature_c": 95.0,
            },
        },
    )

    # 12. driving_assistance.json
    hashes["driving_assistance.json"] = write_json(
        PROFILE_DIR / "driving_assistance.json",
        {
            "aids": {
                "abs_available": False,
                "abs_default_enabled": False,
                "abs_player_selectable": False,
                "auto_clutch_available": True,
                "auto_clutch_default_enabled": True,
                "auto_clutch_player_selectable": True,
                "brake_assist_available": False,
                "brake_assist_default_enabled": False,
                "brake_assist_force_multiplier": 1.0,
                "brake_assist_player_selectable": False,
                "countersteer_default_enabled": False,
                "handbrake_abs_interlock": False,
                "handbrake_clutch_coupling": True,
                "handbrake_rear_only": True,
                "input_smoothing_brake_rate": 16.0,
                "input_smoothing_enabled": True,
                "input_smoothing_steering_rate": 8.0,
                "input_smoothing_throttle_rate": 6.0,
                "launch_control_available": False,
                "launch_control_clutch_release_rate_per_s": 2.0,
                "launch_control_default_enabled": False,
                "launch_control_player_selectable": False,
                "launch_control_target_rpm": 0.0,
                "launch_control_throttle_limit": 1.0,
                "stability_available": False,
                "stability_default_enabled": False,
                "stability_grounded_multiplier": 1.0,
                "stability_player_selectable": False,
                "stability_reference_lateral_accel_m_s2": 15.0,
                "stability_upright_damping": 0.0,
                "stability_upright_spring": 0.0,
                "stability_yaw_engage_angle_rad": 0.1,
                "stability_yaw_strength": 0.0,
                "steering_assist_player_selectable": False,
                "steering_slip_assist_default_enabled": False,
                "traction_control_actuator": "engine_torque",
                "traction_control_attack_rate": 30.0,
                "traction_control_available": False,
                "traction_control_cut_gain": 1.0,
                "traction_control_default_enabled": False,
                "traction_control_gear_authority": [0.0, 0.0, 0.0, 0.0],
                "traction_control_gear_max_cut": [0.0, 0.0, 0.0, 0.0],
                "traction_control_gear_slip_target": [0.0, 0.0, 0.0, 0.0],
                "traction_control_player_selectable": False,
                "traction_control_release_rate": 15.0,
                "traction_control_slip_threshold": 0.15,
            }
        },
    )

    # 13. underfloor_contact.json
    hashes["underfloor_contact.json"] = write_json(
        PROFILE_DIR / "underfloor_contact.json",
        {
            "underfloor_contact": {
                "activation_clearance_m": 0.05,
                "approach_clearance_m": 0.08,
                "clearance_filter_seconds": 0.015,
                "contact_hold_seconds": 0.06,
                "damping_n_s_m": 3200.0,
                "enabled": True,
                "linear_rate_n_m": 420000.0,
                "max_force_per_probe_n": 14000.0,
                "normal_min_y": 0.5,
                "progressive_rate_n_m2": 5500000.0,
                "release_clearance_m": 0.12,
                "rigid_contact_spring_scale": 0.3,
                "rigid_hold_seconds": 0.08,
                "rigid_maximum_local_height_metres": 0.14,
                "rigid_minimum_impulse_newton_seconds": 12.0,
            }
        },
    )

    # 14. coupled_world.json
    collision_parts = [
        {
            "identifier": h["identifier"],
            "kind": "hull",
            "vertices_local_metres": h["points"],
            "center_local_metres": {"x": 0.0, "y": 0.0, "z": 0.0},
            "half_extents_metres": {"x": 0.0, "y": 0.0, "z": 0.0},
            "surface": "metal",
            "damage_scale": 1.0,
        }
        for h in coll_doc.get("hulls", [])
    ]
    collision_parts.append(
        {
            "identifier": "sump_guard",
            "kind": "box",
            "vertices_local_metres": [],
            "center_local_metres": {"x": 0.0, "y": 0.20, "z": 1.15},
            "half_extents_metres": {"x": 0.48, "y": 0.05, "z": 0.45},
            "surface": "metal",
            "damage_scale": 0.8,
        }
    )
    hashes["coupled_world.json"] = write_json(
        PROFILE_DIR / "coupled_world.json",
        {
            "coupled_world": {
                "schema_version": 1,
                "integration_owner": "rust_world_candidate",
                "physical_frequency_hertz": 120,
                "maximum_initial_overlap_metres": 0.1,
                "road_query_extension_metres": 0.15,
                "aerodynamic_probe_length_metres": 1.0,
                "steering_rack_travel_metres": 0.04,
                "aerodynamic_probe_positions_local_metres": [
                    {"x": -0.44, "y": 0.24, "z": -1.14},
                    {"x": 0.44, "y": 0.24, "z": -1.14},
                    {"x": 0.0, "y": 0.24, "z": 0.0},
                    {"x": -0.44, "y": 0.24, "z": 1.14},
                    {"x": 0.44, "y": 0.24, "z": 1.14},
                ],
                "body_collision_boxes": [
                    {"identifier": "front_clip", "center_local_metres": {"x": 0.0, "y": 0.52, "z": -1.25}, "half_extents_metres": {"x": 0.78, "y": 0.30, "z": 0.68}},
                    {"identifier": "cabin_tub", "center_local_metres": {"x": 0.0, "y": 0.76, "z": 0.02}, "half_extents_metres": {"x": 0.79, "y": 0.56, "z": 0.72}},
                    {"identifier": "rear_clip", "center_local_metres": {"x": 0.0, "y": 0.54, "z": 1.38}, "half_extents_metres": {"x": 0.78, "y": 0.32, "z": 0.64}},
                    {"identifier": "sump_guard", "center_local_metres": {"x": 0.0, "y": 0.20, "z": 1.15}, "half_extents_metres": {"x": 0.48, "y": 0.05, "z": 0.45}},
                ],
                "contacts": {
                    "impact_friction_coefficient": 0.55,
                    "maximum_events_per_step": 128,
                    "maximum_iterations": 100,
                    "maximum_position_correction_metres": 0.002,
                    "maximum_supported_angular_speed_radians_per_second": 12,
                    "maximum_supported_speed_metres_per_second": 80,
                    "prediction_distance_metres": 0.002,
                    "restitution": 0.2,
                    "restitution_minimum_speed_metres_per_second": 1,
                    "velocity_tolerance_metres_per_second": 1e-05,
                },
                "suspension": {
                    "differentiation_step_metres": 0.0001,
                    "gravity_world_metres_per_second_squared": {"x": 0.0, "y": -9.80665, "z": 0.0},
                    "substeps_per_tick": 1,
                    "substep_frequency_hz": 120,
                    "tire_vertical_damping_newton_seconds_per_metre": [1050.0, 1050.0, 1050.0, 1050.0],
                    "tire_vertical_stiffness_newtons_per_metre": [175000.0, 175000.0, 175000.0, 175000.0],
                    "travel_stop_damping_newton_seconds_per_metre": [750.0, 750.0, 750.0, 750.0],
                    "travel_stop_engagement_fraction": [0.85, 0.85, 0.85, 0.85],
                    "travel_stop_stiffness_newtons_per_cubic_metre": [75000000.0, 75000000.0, 75000000.0, 75000000.0],
                },
                "collision_parts": collision_parts,
            }
        },
    )

    # 15. HISTORICAL_PROVENANCE.json
    write_json(
        PROFILE_DIR / "HISTORICAL_PROVENANCE.json",
        {
            "vehicle": "Porsche 911 2.4 S (1972-1973 F-Series LWB, Type 911/53)",
            "sources": [
                {
                    "id": "Porsche AG Factory Specifications — 911 2.4 S (1972-1973)",
                    "facts": [
                        "2,341 cc Type 911/53 air-cooled flat-6 (84.0 x 70.4 mm, 8.5:1 CR, Bosch MFI): 190 CV (140 kW) @ 6,500 rpm, 216 Nm @ 5,200 rpm",
                        "Type 915/02 5-speed rear transaxle [3.182, 1.833, 1.261, 0.960, 0.759] with 7:31 (4.429) final drive and RR layout",
                        "F-Series LWB dimensions: wheelbase 2,271 mm, length 4,163 mm, width 1,610 mm, height 1,320 mm, tracks 1,372 / 1,354 mm",
                        "1,050 kg DIN curb weight (~41.5/58.5 F/R distribution with 1972 forward oil tank), 19/23 mm torsion bars, 282.5/290 mm vented discs, 185/70 VR 15 tires on 6Jx15 Fuchs",
                    ],
                }
            ],
            "estimated": [
                "Non-wheel vehicle_mass budget set to 1,130.0 kg (1,050 kg curb - 70 kg 4x wheels + 150 kg crew)",
                "Component inertias, damper curves, tire thermal/cooling coefficients, and Cd 0.395 / 1.80 m^2 aerodynamics are engineering estimates",
                "Visual exterior derived from Re-Volt 90120 PRM mesh & car.bmp texture scaled to exact 1972-73 911 2.4 S dimensions",
            ],
            "shared_calibration": [
                "coupled_world",
                "damage",
                "driving_assistance",
                "steering",
                "suspension_filters",
                "underfloor_contact",
            ],
            "profile_json_sha256": {k: hashes[k] for k in sorted(hashes)},
            "audio_source": "Dedicated GT3 flat-6 bank gt3-bank/porsche-911-24s built from engine (6 layers 900-6000 rpm) + exhaust (900 rpm idle + 7 layers 1400-6928 rpm) of bank 22803 (911(996) GT3) + shared res://sounds/banks/commons/ audio.",
        },
    )
    print(f"PORSCHE_911_24S_PROFILE_GENERATED_OK: {PROFILE_DIR}")


if __name__ == "__main__":
    main()
