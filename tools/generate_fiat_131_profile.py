#!/usr/bin/env python3
"""
Generate the historical FIA Group 4 Fiat 131 Abarth Rally physics profile
under game/data/vehicles/fiat-131-abarth/ and its exact SHA-256 provenance.

Every file follows the repository coordinate contract (-Z forward, +X right, +Y up, SI).
Collision hulls for coupled_world.json are synced directly from
game/assets/rally/fiat_131_abarth/fiat_131_abarth_collision.json.
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PROFILE_DIR = REPO / "game" / "data" / "vehicles" / "fiat-131-abarth"
ASSET_DIR = REPO / "game" / "assets" / "rally" / "fiat_131_abarth"


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
                "center_of_mass_basis": "Local ground-plane / attachment coordinates; Gr.4 rally packaging estimate",
            },
        },
        "rotating_wheel": wheel if rotating else None,
        "uncertainty": {
            "lower_mass_kilograms": round(mass_kg * (1.0 - uncertainty_pct), 2),
            "upper_mass_kilograms": round(mass_kg * (1.0 + uncertainty_pct), 2),
            "center_uncertainty_metres": 0.10,
            "inertia_relative_uncertainty": 0.20,
            "rationale": "Historic Group 4 component mass reconstruction",
        },
    }


def main() -> None:
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    coll_doc = json.loads((ASSET_DIR / "fiat_131_abarth_collision.json").read_text(encoding="utf-8"))

    hashes: dict[str, str] = {}

    # 1. vehicle.json
    hashes["vehicle.json"] = write_json(
        PROFILE_DIR / "vehicle.json",
        {
            "schema_version": 1,
            "vehicle_identifier": "fiat_131_abarth",
            "profile_name": "Fiat Abarth 131 Rally (FIA Group 4, Homologation No. 647)",
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

    # 2. chassis.json (1035.0 kg non-wheel budget incl. 150 kg crew + 80 kg 4x wheel_rotor -> ~965 kg vehicle uncrewed)
    components = [
        make_component(
            "bodywork_and_rollcage",
            "body shell, cage, fiberglass flares/hood/trunk, alloy doors, plexiglass",
            "vehicle_and_driver",
            "body",
            415.0,
            (0.0, 0.56, 0.02),
            (265.0, 325.0, 96.0),
            "FIA Group 4 reinforced 2-door shell with Bertone flares & aluminum/fiberglass panels",
        ),
        make_component(
            "engine_lampredi_2000_16v",
            "engine assembly and Kugelfischer slide-throttle injection",
            "vehicle_and_driver",
            "body",
            145.0,
            (0.0, 0.44, -0.92),
            (17.5, 14.0, 11.5),
            "Lampredi 1995cc 16V DOHC Tipo 232CIG engine with dry-sump ancillaries",
        ),
        make_component(
            "gearbox_cima_5spd_propshaft",
            "5-speed dog-box and propshaft",
            "vehicle_and_driver",
            "body",
            36.0,
            (0.0, 0.30, -0.32),
            (3.4, 3.4, 1.7),
            "CIMA 5-speed straight-cut dog-engagement gearbox and forward propshaft",
        ),
        make_component(
            "rear_diff_zf_irs_carrier",
            "chassis-mounted ZF differential carrier and halfshafts",
            "vehicle_and_driver",
            "body",
            45.0,
            (0.0, 0.30, 1.22),
            (2.8, 3.6, 4.2),
            "Chassis-mounted ZF clutch LSD and rear IRS carrier assembly",
        ),
        make_component(
            "driver",
            "crew driver",
            "vehicle_and_driver",
            "body",
            75.0,
            (-0.35, 0.47, 0.18),
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
            (0.35, 0.47, 0.22),
            (7.5, 7.0, 3.5),
            "Crew allocation (co-driver)",
            uncertainty_pct=0.05,
        ),
        make_component(
            "cooling_and_dry_sump_tank",
            "radiator, oil cooler, dry-sump tank and lines",
            "vehicle_and_driver",
            "body",
            30.0,
            (0.0, 0.43, -1.45),
            (2.2, 3.0, 2.2),
            "Group 4 front cooling package and dry-sump oil reservoir",
        ),
        make_component(
            "exhaust_and_ancillaries",
            "competition exhaust system and pedal box",
            "vehicle_and_driver",
            "body",
            24.0,
            (0.0, 0.24, 0.20),
            (6.0, 6.0, 1.2),
            "Lateral rally exhaust and dual master-cylinder pedal assembly",
        ),
        make_component(
            "electrical_and_battery",
            "rear-mounted competition battery and loom",
            "vehicle_and_driver",
            "body",
            16.0,
            (0.0, 0.36, 1.35),
            (0.6, 0.8, 0.6),
            "Rear-relocated battery for ~52:48 competition weight distribution",
        ),
        make_component(
            "skid_plate_and_underbody_protection",
            "duralumin sump guard and gravel armor",
            "vehicle_and_driver",
            "body",
            22.0,
            (0.0, 0.19, -0.95),
            (1.6, 2.4, 1.2),
            "Group 4 front duralumin sump/crossmember protection",
        ),
        make_component(
            "front_subframe_and_steering",
            "front crossmember, wishbones and quick rack",
            "vehicle_and_driver",
            "body",
            55.0,
            (0.0, 0.28, -1.24),
            (2.4, 8.5, 7.2),
            "Front MacPherson subframe, TCA arms and 2.85-turn steering rack",
        ),
        make_component(
            "rear_suspension_crossmember",
            "rear independent suspension subframe and arms",
            "vehicle_and_driver",
            "body",
            45.0,
            (0.0, 0.31, 1.24),
            (2.2, 7.8, 6.5),
            "Group 4 independent rear semi-trailing arm and Chapman strut subframe",
        ),
        make_component(
            "spare_wheels_and_tools",
            "trunk spare wheel and competition tools",
            "vehicle_and_driver",
            "body",
            27.0,
            (0.0, 0.40, 1.48),
            (1.2, 1.2, 1.8),
            "Full-size spare Cromodora 15-inch wheel/tire (20 kg) + jack/tools (7 kg)",
        ),
    ]
    for corner in ("FrontLeft", "FrontRight", "RearLeft", "RearRight"):
        components.append(
            make_component(
                f"upright_{corner.lower()}",
                f"upright assembly {corner}",
                "vehicle_and_driver",
                "upright",
                6.25,
                (0.0, 0.0, 0.0),
                (0.10, 0.10, 0.10),
                "Group 4 upright, alloy AP/Brembo caliper and vented brake rotor",
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
                20.0,
                (0.0, 0.0, 0.0),
                (1.13, 0.65, 0.65),
                "Cromodora 7x15 magnesium rim + 185/70 R15 reinforced gravel tire",
                wheel=corner,
                rotating=True,
                uncertainty_pct=0.10,
            )
        )

    hashes["chassis.json"] = write_json(
        PROFILE_DIR / "chassis.json",
        {
            "chassis": {
                "vehicle_name": "Fiat Abarth 131 Rally (Group 4 FIA 647)",
                "vehicle_mass": 1035.0,
                "vehicle_mass_excludes_wheel_assemblies": True,
                "front_weight_distribution": 0.52,
                "center_of_gravity_height_offset": -0.165,
                "inertia_multipliers": {"x": 1.0, "y": 1.0, "z": 1.0},
                "target_cg_z_m": 0.485,
            },
            "geometry": {
                "wheelbase": 2.49,
                "front_track": 1.461,
                "rear_track": 1.46,
                "front_axle_z": -1.245,
                "rear_axle_z": 1.245,
            },
            "physical_mass_inventory": {
                "schema_version": 2,
                "base_budget_kilograms": 1035.0,
                "rim_and_tire_mass_kilograms": [20.0, 20.0, 20.0, 20.0],
                "coordinate_contract": {"forward": "-Z", "right": "+X", "up": "+Y"},
                "spare_policy": {
                    "mass_component_name": "spare_wheels_and_tools",
                    "tools_mass_kg": 7.0,
                    "wheel_mass_kg": 20.0,
                },
                "components": components,
            },
        },
    )

    # 3. powertrain.json (Lampredi 1995cc 16V Kugelfischer, 236 CV @ 7500 rpm, 230 Nm @ 5600 rpm, CIMA 5-spd)
    hashes["powertrain.json"] = write_json(
        PROFILE_DIR / "powertrain.json",
        {
            "powertrain": {
                "automatic_shift": {
                    "downshift_coast_normalized_rpm": 0.28,
                    "downshift_normalized_rpm_full_throttle": 0.65,
                    "downshift_normalized_rpm_low_throttle": 0.45,
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
                "clutch_reengage_seconds": 0.11,
                "synchronizer_capacity_nm": 40.0,
                "synchronizer_tolerance_rad_s": 0.14,
                "clutch_out_rpm_offset": 350.0,
                "constant_brake_ratio": 0.012,
                "differential": {
                    "type": "clutch_lsd",
                    "preset_id": "fiat131_tierra",
                    "clutch_friction_coefficient": 0.12,
                    "clutches": 4.0,
                    "coast_ramp_angle_deg": 60.0,
                    "power_ramp_angle_deg": 35.0,
                    "preload_nm": 70.0,
                    "slip_transition_threshold_rad_s": 4.0,
                    "lock_pct_power": 65.0,
                    "lock_pct_coast": 30.0,
                    "coast_friction_coefficient": 0.09,
                },
                "downshift_blip_torque_fraction": 0.82,
                "downshift_blip_response_seconds": 0.035,
                "downshift_blip_tolerance_rpm": 25.0,
                "downshift_clutch_reengagement_seconds": 0.11,
                "downshift_maximum_target_revolutions_per_minute_fraction": 0.93,
                "downshift_minimum_interval_seconds": 0.2,
                "downshift_rev_matching_enabled": False,
                "driveline_compliance": {
                    "enabled": True,
                    "output_inertia_kg_m2": 0.22,
                    "stiffness_nm_per_rad": 9000.0,
                    "damping_nms_per_rad": 140.0,
                },
                "final_drive": 5.125,
                "final_drive_gravel": 5.125,
                "final_drive_tarmac": 4.3,
                "final_drive_preset": "gravel",
                "front_torque_split": 0.0,
                "gear_inertia": 0.022,
                "gear_ratios": [3.612, 2.045, 1.357, 1.0, 0.87],
                "handbrake_torque_fraction": 1.0,
                "idle_disengagement_hysteresis_rpm": 120.0,
                "idle_rpm": 1100.0,
                "max_clutch_torque_ratio": 1.5,
                "max_rpm": 8000.0,
                "max_torque": 230.0,
                "motor_moment": 0.115,
                "reverse_ratio": 3.244,
                "shift_time": 0.13,
                "thermal": {
                    "engine_block_heat_capacity_joules_per_kelvin": 68000.0,
                    "engine_block_heat_fraction": 0.1,
                    "engine_to_oil_conductance_watts_per_kelvin": 400.0,
                    "engine_to_water_conductance_watts_per_kelvin": 900.0,
                    "exhaust_heat_fraction": 0.6,
                    "heat_generation_per_mechanical_power": 1.45,
                    "idle_heat_generation_watts": 12500.0,
                    "initial_engine_block_temperature_celsius": 85.0,
                    "initial_oil_temperature_celsius": 85.0,
                    "initial_water_temperature_celsius": 82.0,
                    "minimum_hot_engine_torque_fraction": 0.85,
                    "oil_critical_temperature_celsius": 135.0,
                    "oil_heat_capacity_joules_per_kelvin": 18000.0,
                    "oil_heat_fraction": 0.09,
                    "oil_hot_derating_temperature_celsius": 122.0,
                    "oil_minimum_cold_engine_torque_fraction": 0.88,
                    "oil_optimal_maximum_temperature_celsius": 112.0,
                    "oil_optimal_minimum_temperature_celsius": 80.0,
                    "oil_pressure": {
                        "bar_per_rpm": 0.0012,
                        "hot_viscosity_factor": 0.62,
                        "low_ratio": 0.75,
                        "pressure_response_seconds": 0.22,
                        "relief_valve_bar": 5.0,
                        "viscosity_hot_celsius": 130.0,
                        "viscosity_reference_celsius": 90.0,
                        "warning_ratio": 0.5,
                        "warning_pressure_bar": 1.0,
                    },
                    "oil_sump_cooling_conductance_watts_per_kelvin": 16.0,
                    "oil_to_water_conductance_watts_per_kelvin": 270.0,
                    "water_cooling_duct": {
                        "air_specific_heat_joules_per_kilogram_kelvin": 1005.0,
                        "area_response_exponent": 1.0,
                        "base_cooling_conductance_watts_per_kelvin": 80.0,
                        "discharge_coefficient": 0.72,
                        "drag_coefficient": 0.5,
                        "heat_exchanger_conductance_watts_per_kelvin": 4300.0,
                        "maximum_inlet_area_square_meters": 0.22,
                        "opening": 0.12,
                        "pressure_recovery": 0.75,
                    },
                    "water_critical_temperature_celsius": 115.0,
                    "water_heat_capacity_joules_per_kelvin": 30000.0,
                    "water_heat_fraction": 0.2,
                    "water_hot_derating_temperature_celsius": 105.0,
                    "water_minimum_cold_engine_torque_fraction": 0.95,
                    "water_optimal_maximum_temperature_celsius": 95.0,
                    "water_optimal_minimum_temperature_celsius": 75.0,
                },
                "torque_attack_rate_nm_s": 2400.0,
                "torque_curve": [
                    [0.06, 0.0],
                    [0.1375, 0.42],
                    [0.25, 0.58],
                    [0.375, 0.72],
                    [0.5, 0.86],
                    [0.625, 0.96],
                    [0.7, 1.0],
                    [0.75, 0.995],
                    [0.8125, 0.985],
                    [0.875, 0.975],
                    [0.9375, 0.96],
                    [1.0, 0.82],
                ],
                "variable_drag_ratio": 0.036,
            }
        },
    )

    # 4. suspension.json (IRS on BOTH front & rear via macpherson_coil! solid_axle = false)
    hashes["suspension.json"] = write_json(
        PROFILE_DIR / "suspension.json",
        {
            "suspension": {
                "contact_shape_count": 1,
                "contact_query_type": "ShapeCast3D",
                "front": {
                    "spring_architecture": "macpherson_coil",
                    "spring_can_unseat": True,
                    "arb_ratio": 0.24,
                    "bump_damp_multiplier": 1.0,
                    "bump_stop_multiplier": 1.0,
                    "camber": -0.02618,
                    "camber_gain_rad_per_m": -0.02,
                    "damping_ratio": 0.42,
                    "rebound_damp_multiplier": 1.35,
                    "resting_ratio": 0.35,
                    "spring_length": 0.34,
                    "toe": -0.001745,
                    "toe_gain_rad_per_m": 0.008,
                    "ride_frequency_hz": 1.6,
                },
                "rear": {
                    "spring_architecture": "macpherson_coil",
                    "spring_can_unseat": True,
                    "arb_ratio": 0.06,
                    "bump_damp_multiplier": 1.0,
                    "bump_stop_multiplier": 1.0,
                    "camber": -0.01745,
                    "camber_gain_rad_per_m": -0.015,
                    "damping_ratio": 0.44,
                    "rebound_damp_multiplier": 1.35,
                    "resting_ratio": 0.35,
                    "spring_length": 0.32,
                    "toe": 0.001745,
                    "toe_gain_rad_per_m": 0.005,
                    "ride_frequency_hz": 1.48,
                },
                "geometry_physical": {
                    "version": 1,
                    "front": {
                        "arb_damper_Ns_per_m": 120.0,
                        "bump_stop_damper_Ns_per_m": 600.0,
                        "bump_stop_law": "cubic",
                        "bump_stop_mult": 1.0,
                        "bump_stop_travel_m": 0.03,
                        "damper_bump_Ns_per_m": 1900.0,
                        "damper_fast_factor": 0.55,
                        "damper_knee_blend_m_per_s": 0.02,
                        "damper_knee_m_per_s": 0.15,
                        "damper_max_m": 0.48,
                        "damper_min_m": 0.14,
                        "damper_rebound_Ns_per_m": 2550.0,
                        "hard_stop_compliance_m": 0.001,
                        "hard_stop_damper_Ns_per_m": 2500.0,
                        "hard_stop_overtravel_m": 0.005,
                        "hard_stop_stiffness_N_per_m": 8000000.0,
                        "spring_free_length_m": 0.34,
                        "spring_installed_length_m": 0.28,
                        "spring_rate_N_per_m": 27200.0,
                        "wheel_bump_m": 0.14,
                        "wheel_droop_m": 0.12,
                    },
                    "front_arb": {"mode": "legacy_ratio", "ratio": 0.24},
                    "rear": {
                        "arb_damper_Ns_per_m": 70.0,
                        "bump_stop_damper_Ns_per_m": 600.0,
                        "bump_stop_law": "cubic",
                        "bump_stop_mult": 1.0,
                        "bump_stop_travel_m": 0.03,
                        "damper_bump_Ns_per_m": 2200.0,
                        "damper_fast_factor": 0.65,
                        "damper_knee_blend_m_per_s": 0.02,
                        "damper_knee_m_per_s": 0.15,
                        "damper_max_m": 0.52,
                        "damper_min_m": 0.12,
                        "damper_rebound_Ns_per_m": 3000.0,
                        "hard_stop_compliance_m": 0.001,
                        "hard_stop_damper_Ns_per_m": 2500.0,
                        "hard_stop_overtravel_m": 0.005,
                        "hard_stop_stiffness_N_per_m": 8000000.0,
                        "spring_free_length_m": 0.32,
                        "spring_installed_length_m": 0.26,
                        "spring_rate_N_per_m": 21500.0,
                        "wheel_bump_m": 0.13,
                        "wheel_droop_m": 0.11,
                    },
                    "rear_arb": {"mode": "legacy_ratio", "ratio": 0.06},
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

    # 6. brakes.json (300mm front / 254mm rear vented alloy calipers, unassisted)
    hashes["brakes.json"] = write_json(
        PROFILE_DIR / "brakes.json",
        {
            "brakes": {
                "abs_pulse_time": 0.03,
                "abs_spin_diff_threshold": 10.0,
                "enable_abs": False,
                "front_brake_bias": 0.59,
                "max_brake_torque": 5800.0,
                "wheel_lock_blend_spin_rad_s": 6.0,
                "wheel_lock_stick_tau_s": 0.03,
                "servo_assist": {"enabled": False, "gain": 0.9},
                "thermal": {
                    "braking_heat_fraction": 0.95,
                    "cold_efficiency": 0.84,
                    "critical_temperature_c": 780.0,
                    "fade_start_temperature_c": 580.0,
                    "initial_temperature_c": 25.0,
                    "minimum_fade_efficiency": 0.52,
                    "optimal_max_temperature_c": 480.0,
                    "optimal_min_temperature_c": 150.0,
                    "front": {
                        "cooling_profile": "open_wheel_external_faces",
                        "installation_airflow_scale": 0.92,
                        "model": "scaled_two_node_v1",
                        "rim_base_air_w_k": 8.5,
                        "rim_heat_capacity_j_k": 3400.0,
                        "rim_to_tire_carcass_w_k": 35.0,
                        "rim_to_tire_gas_w_k": 25.0,
                        "rotor_inner_diameter_m": 0.165,
                        "rotor_mass_kg": 6.2,
                        "rotor_material": "cast_iron",
                        "rotor_outer_diameter_m": 0.30,
                        "rotor_radiation_ambient_view_factor": 0.55,
                        "rotor_radiation_emissivity": 0.7,
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
                        "max_inlet_area_m2_per_wheel": 0.01,
                        "minimum_cooling_flow_ratio": 0.15,
                        "opening": 0.25,
                        "pressure_recovery": 0.65,
                        "rotor_cooling_fraction": 0.85,
                    },
                    "rear": {
                        "cooling_profile": "open_wheel_external_faces",
                        "installation_airflow_scale": 0.9,
                        "model": "scaled_two_node_v1",
                        "rim_base_air_w_k": 7.5,
                        "rim_heat_capacity_j_k": 3400.0,
                        "rim_to_tire_carcass_w_k": 25.0,
                        "rim_to_tire_gas_w_k": 18.0,
                        "rotor_inner_diameter_m": 0.145,
                        "rotor_mass_kg": 4.3,
                        "rotor_material": "cast_iron",
                        "rotor_outer_diameter_m": 0.254,
                        "rotor_radiation_ambient_view_factor": 0.45,
                        "rotor_radiation_emissivity": 0.7,
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
                        "drag_coefficient": 0.1,
                        "heat_exchanger_ua_w_k": 210.0,
                        "max_inlet_area_m2_per_wheel": 0.007,
                        "minimum_cooling_flow_ratio": 0.15,
                        "opening": 0.2,
                        "pressure_recovery": 0.6,
                        "rotor_cooling_fraction": 0.85,
                    },
                },
            }
        },
    )

    # 7. steering.json (2.85 turns lock-to-lock documented FIA 647 quick rack)
    hashes["steering.json"] = write_json(
        PROFILE_DIR / "steering.json",
        {
            "steering": {
                "ackermann": 0.18,
                "countersteer_assist": 0.0,
                "front_steering_ratio": 1.0,
                "max_steering_angle": 0.576,
                "rear_steering_ratio": 0.0,
                "steering_exponent": 1.1,
                "steering_slip_assist": 0.0,
                "steering_speed": 5.2,
                "steering_speed_decay": 0.05,
                "speed_filter_start_kph": 20.0,
                "speed_filter_reference_kph": 65.0,
                "speed_filter_minimum_gain": 0.2,
                "turns_lock_to_lock": 2.85,
                "ratio_to_one": 15.5,
            }
        },
    )

    # 8. tires.json (15" Cromodora + 185/70 R15 gravel -> R=0.320 m, W=0.200 m)
    hashes["tires.json"] = write_json(
        PROFILE_DIR / "tires.json",
        {
            "tires": {
                "front": {
                    "contact_patch": 0.2,
                    "radius": 0.32,
                    "rim_diameter_inches": 15.0,
                    "wheel_mass": 20.0,
                    "width": 0.2,
                    "nominal_section_width_m": 0.185,
                    "rolling_radius_m": 0.32,
                    "pressure_kpa": 180.0,
                    "compound": "gravel_normal",
                },
                "rear": {
                    "contact_patch": 0.2,
                    "radius": 0.32,
                    "rim_diameter_inches": 15.0,
                    "wheel_mass": 20.0,
                    "width": 0.2,
                    "nominal_section_width_m": 0.185,
                    "rolling_radius_m": 0.32,
                    "pressure_kpa": 180.0,
                    "compound": "gravel_normal",
                },
                "default_compound": "gravel_normal",
                "pressure": {
                    "cold_kpa_gauge": {"FL": 180.0, "FR": 180.0, "RL": 180.0, "RR": 180.0},
                    "reference_temperature_c": 25.0,
                },
            }
        },
    )

    # 9. aerodynamics.json (Cd 0.46, area 2.22 m^2, chin air dam + roof/decklid spoilers)
    hashes["aerodynamics.json"] = write_json(
        PROFILE_DIR / "aerodynamics.json",
        {
            "aero": {
                "air_density": 1.225,
                "blend_full_speed_mps": 35.0,
                "blend_min_speed_mps": 5.0,
                "drag_coefficient": 0.46,
                "frontal_area": 2.22,
                "lag_tau_s": 0.04,
                "model": {
                    "body": {"drag_coefficient_scope": "whole_vehicle_reference", "wheel_reference_drag_area_m2": 0.09},
                    "front_wing": {
                        "area_m2": 0.18,
                        "incidence_deg": 4.0,
                        "max_angle_deg": 10.0,
                        "min_angle_deg": 0.0,
                        "polar": [
                            {"angle_deg": 0.0, "cd": 0.015, "cl": 0.04},
                            {"angle_deg": 5.0, "cd": 0.03, "cl": 0.12},
                            {"angle_deg": 10.0, "cd": 0.055, "cl": 0.20},
                        ],
                        "position_m": [0.0, -0.25, -1.85],
                        "yaw_decay_exponent": 1.0,
                    },
                    "limits": {
                        "hard_max_downforce_n": 650.0,
                        "hard_max_load_ratio": 1.08,
                        "profile": "saloon_rally",
                        "soft_max_load_ratio": 1.03,
                    },
                    "rear_wing": {
                        "area_m2": 0.28,
                        "incidence_deg": 6.0,
                        "max_angle_deg": 12.0,
                        "min_angle_deg": 0.0,
                        "polar": [
                            {"angle_deg": 0.0, "cd": 0.02, "cl": 0.05},
                            {"angle_deg": 6.0, "cd": 0.04, "cl": 0.16},
                            {"angle_deg": 12.0, "cd": 0.075, "cl": 0.26},
                        ],
                        "position_m": [0.0, 0.45, 2.05],
                        "yaw_decay_exponent": 1.0,
                    },
                    "underfloor": {
                        "bottoming_factor": 0.1,
                        "choke_height_m": 0.03,
                        "floor_clearance_front_m": 0.17,
                        "floor_clearance_rear_m": 0.21,
                        "high_height_m": 0.38,
                        "induced_drag_ratio": 0.05,
                        "lift_area_m2": 0.0,
                        "optimal_height_m": 0.18,
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
                    "wheels": {"front_drag_coefficient": 0.045, "rear_drag_coefficient": 0.045},
                },
            }
        },
    )

    # 10. fuel.json (60 L safety cell @ 0.74 kg/L = 44.4 kg)
    hashes["fuel.json"] = write_json(
        PROFILE_DIR / "fuel.json",
        {
            "fuel": {
                "brake_specific_consumption_kg_per_kwh": 0.35,
                "capacity_kg": 44.4,
                "density_kg_per_litre": 0.74,
                "estimated_lap_consumption_kg": 2.8,
                "idle_consumption_kg_per_hour": 2.4,
                "initial_kg": 22.2,
                "reference_lap_time_s": 180.0,
                "tank_position_local_m": {"x": 0.0, "y": 0.44, "z": 1.05},
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
                "maximum_radiator_damage": 0.55,
                "maximum_engine_damage": 0.26,
                "maximum_transmission_damage": 0.3,
                "severity_exponent": 1.2,
                "min_impulse_speed_m_s": 1.5,
                "zone_weights": {
                    "nose": {"radiator": 1.0, "engine": 0.65},
                    "front_underbody": {"radiator": 0.55, "engine": 1.0},
                    "side": {"radiator": 0.2, "engine": 0.2},
                    "rear": {"radiator": 0.08, "engine": 0.12},
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
                "maximum_radiator_damage": 0.1,
                "maximum_engine_damage": 0.08,
                "severity_exponent": 1.0,
                "zone_weights": {
                    "nose": {"radiator": 1.0, "engine": 0.85},
                    "front_underbody": {"radiator": 0.75, "engine": 1.0},
                    "front_wheels": {"radiator": 0.35, "engine": 0.25},
                    "rear_wheels": {"radiator": 0.1, "engine": 0.1},
                    "rear": {"radiator": 0.1, "engine": 0.15},
                },
            },
            "thermal": {
                "minimum_cooling_factor": 0.45,
                "minimum_torque_factor": 0.6,
                "oil_pressure_loss_at_full_engine_damage": 0.35,
                "permanent_minimum_torque_factor": 0.7,
                "damage_start_c": 110.0,
                "full_rate_temperature_c": 120.0,
                "grace_seconds": 6.0,
                "maximum_damage_per_second": 0.015,
                "recovery_rate_per_second": 2.0,
            },
            "steam": {
                "start_damage": 0.25,
                "continuous_damage": 0.5,
                "heavy_damage": 0.75,
                "local_position": [0.0, 0.48, -1.70],
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
                "damping_n_s_m": 3500.0,
                "enabled": True,
                "linear_rate_n_m": 450000.0,
                "max_force_per_probe_n": 15000.0,
                "normal_min_y": 0.5,
                "progressive_rate_n_m2": 6000000.0,
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
            "center_local_metres": {"x": 0.0, "y": 0.21, "z": -0.95},
            "half_extents_metres": {"x": 0.54, "y": 0.05, "z": 0.48},
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
                    {"x": -0.45, "y": 0.24, "z": -1.245},
                    {"x": 0.45, "y": 0.24, "z": -1.245},
                    {"x": 0.0, "y": 0.24, "z": 0.0},
                    {"x": -0.45, "y": 0.24, "z": 1.245},
                    {"x": 0.45, "y": 0.24, "z": 1.245},
                ],
                "body_collision_boxes": [
                    {"identifier": "front_clip", "center_local_metres": {"x": 0.0, "y": 0.56, "z": -1.25}, "half_extents_metres": {"x": 0.84, "y": 0.34, "z": 0.65}},
                    {"identifier": "cabin_tub", "center_local_metres": {"x": 0.0, "y": 0.78, "z": 0.08}, "half_extents_metres": {"x": 0.85, "y": 0.56, "z": 0.78}},
                    {"identifier": "rear_clip", "center_local_metres": {"x": 0.0, "y": 0.58, "z": 1.50}, "half_extents_metres": {"x": 0.84, "y": 0.35, "z": 0.74}},
                    {"identifier": "sump_guard", "center_local_metres": {"x": 0.0, "y": 0.21, "z": -0.95}, "half_extents_metres": {"x": 0.54, "y": 0.05, "z": 0.48}},
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
                    "tire_vertical_damping_newton_seconds_per_metre": [1100.0, 1100.0, 1100.0, 1100.0],
                    "tire_vertical_stiffness_newtons_per_metre": [180000.0, 180000.0, 180000.0, 180000.0],
                    "travel_stop_damping_newton_seconds_per_metre": [800.0, 800.0, 800.0, 800.0],
                    "travel_stop_engagement_fraction": [0.85, 0.85, 0.85, 0.85],
                    "travel_stop_stiffness_newtons_per_cubic_metre": [80000000.0, 80000000.0, 80000000.0, 80000000.0],
                },
                "collision_parts": collision_parts,
            }
        },
    )

    # 15. HISTORICAL_PROVENANCE.json
    write_json(
        PROFILE_DIR / "HISTORICAL_PROVENANCE.json",
        {
            "vehicle": "Fiat Abarth 131 Rally (FIA Group 4, Homologation No. 647)",
            "sources": [
                {
                    "id": "FIA Form 647 (Group 4, 1976-04-02)",
                    "facts": [
                        "1,995 cc I4 DOHC 16V Lampredi engine (Tipo 232CIG), dry sump, Kugelfischer mechanical injection",
                        "Length 4,181 mm, Group 4 Bertone flared width 1,720 mm base (~1.758 m wide tarmac/rally flares), wheelbase 2,489-2,490 mm",
                        "Tracks 1,461 mm front / 1,397 mm base (1,460-1,492 mm Group 4 rally evolution), quick rack 2.85 turns lock-to-lock",
                        "Independent rear MacPherson/Chapman strut + semi-trailing arm IRS replacing stock live axle",
                        "CIMA 5-speed straight-cut dog-box ratios [3.612, 2.045, 1.357, 1.000, 0.870] incl. 33/26 primary; reverse 3.244; 8/41 (5.125) gravel final drive",
                        "230-240 CV @ 7,000-7,500 rpm, 225-230 Nm @ 5,600 rpm; unassisted vented discs 300x28 mm front / 254x20 mm rear; 60 L FIA safety cell; 15-inch Cromodora wheels",
                    ],
                }
            ],
            "estimated": [
                "Group 4 competition mass budget set to 1,035 kg excluding 4x20 kg wheels and including 150 kg crew (matches ~965 kg uncrewed rally trim + crew/spares)",
                "Component inertias, ~52:48 F/R balance, Bilstein damper curves, tire/thermal/cooling coefficients and Cd 0.46 / 2.22 m^2 aerodynamics are engineering estimates calibrated to rally Gr.4 specs",
                "Visual exterior derived from RallyManiacAssets Fiat 131.fbx + high-res fiat_131_abarth_alta.png PBR without PSX finish and fitted piecewise-linearly to 2.490 m wheelbase / 4.181 m length",
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
            "audio_source": "Dedicated GT3 bank gt3-bank/fiat-131-abarth built exclusively from engine-type samples of bank 33406 (2.0L L4 DOHC 16V NA, 8 engine layers 1000-8000 rpm) + shared res://sounds/banks/commons/ audio for whine, backfire, shifts, and environment.",
        },
    )
    print(f"FIAT_131_PROFILE_GENERATED_OK: {PROFILE_DIR}")


if __name__ == "__main__":
    main()
