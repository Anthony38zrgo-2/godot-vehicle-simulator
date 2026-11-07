# Ford Escort brake physics review

Update: the subsequent mass-coordinate and axle-distribution adjustment is documented in [MASS_DISTRIBUTION.md](MASS_DISTRIBUTION.md). The old negative CG figures below describe the pre-adjustment inventory. The current nominal CG height is 0.4744 m and the initial front fraction is 52.72%, from component packaging estimates at 25 kg fuel.

## Scope and physical basis

This change keeps one lumped temperature state per wheel brake. It does not attempt to activate the profile's existing detailed two-node brake configuration. The current brake profile supplies candidate rotor masses and dimensions; the in-game output should therefore be read as a first-order physical estimate, pending confirmation that those dimensions describe the intended historic Escort preparation.

The brake torque still comes from the existing configured total and front/rear bias. Changing that bias before resolving the vehicle mass coordinates and hardware specification would amount to tuning against a potentially invalid load model.

## Geometry and load-transfer calculation

The authored Ford has 2.410 m wheelbase, 0.280 m tire radius, and 1,095 kg mass at the initial 25 kg fuel load. Weighted mass inventory gives local CG `(0.000, -0.138, 0.068) m`; static axle fractions computed from the documented axle coordinates are 47.2% front and 52.8% rear.

The wheel-pivot height is 0.280 m, so the nominal tire-ground plane is local `y=0`. The mass inventory therefore places the CG 0.138 m below that nominal plane. This is a coordinate/ride-height inconsistency to resolve before using load transfer to set brake bias. For illustration only, the rigid-body relation `front fraction = static front fraction + (deceleration/g) * CG_height/wheelbase` gives 42.6% front at 0.8 g with the authored negative CG height, versus 62.1% if CG height were 0.45 m. The latter is an example, not an adopted vehicle parameter.

The historic Ford preparation guide documents multiple distinct systems: 9.6-inch front discs and production rear drums, a Group 1 ventilated-front conversion, and a works setup with 10.5-inch vented fronts and 10-inch solid rears. The current profile's 245 mm solid fronts and 203 mm solid rears do not identify which preparation it represents. That choice must be made before changing brake torque or axle bias.

## Brake energy model

Brake work is the integral `E = integral(|T_brake| * |wheel_angular_speed| dt)`. The wheel-spin solver now returns this work in joules. With constant external torque over a substep, it integrates the linear angular-speed segment, splits an interval at the instant of stopping, and holds a stopped rotor when the external torque is within brake capacity. If the external torque exceeds capacity, the remaining interval permits rotation and generates the corresponding brake work. Both airborne and contact paths pass `E / dt` to the thermal model. A locked rotor generates no disc friction work while it remains locked; tire/road sliding heat stays in the tire model.

The one-node disc balance is

`C_disc * dT/dt = eta * P_brake - Q_convection - Q_radiation`.

`C_disc = rotor_mass * 500 J/(kg K)` uses a representative grey-cast-iron specific heat. The earlier replacement still used an unsupported `h = 20 + 12*v W/(m² K)` coefficient; the current revision replaces it with an equivalent flat-plate correlation for the two annular faces: `Re = U_local * D / nu`, `Nu = 0.664 * sqrt(Re) * Pr^(1/3)`, `h = Nu * k / D`. Above Re=500,000 the transitional expression is `(0.037*Re^0.8 - 871)*Pr^(1/3)`. Local speed is vehicle speed times the profile installation_airflow_scale. Air viscosity follows Sutherland, density is the ideal-gas value at one atmosphere, and conductivity uses a power-law approximation; properties are evaluated at mean film temperature.

At rest, Churchill-Chu's vertical-surface natural-convection correlation supplies cooling. The larger of natural and forced coefficients is used, avoiding summing two complete boundary-layer estimates. Radiation uses `epsilon * sigma * A * ambient_view_factor * (T_K^4 - T_ambient,K^4)` with the per-axle profile view factor. These are face-flow engineering approximations, not an Escort wheel CFD solution: they exclude rotation-induced pumping, ducts, edge cooling and conduction to pads, hub, caliper and rim. Reduced loss terms should not be confused with a measured cooling calibration.

With the configured radii and masses, the modeled swept-face areas are 0.0635 m² front and 0.0421 m² rear. The modeled heat capacities are 2,250 J/K per front disc and 2,500 J/K per rear disc. At 100 km/h with a front disc at 200 C and ambient at 25 C, the current calculation gives Re=167,911, h=31.86 W/(m² K), and conductance 2.02 W/K. Combined convection and ambient-view radiation reject about 397 W per front disc. The first correction had 22.4 W/K convection; the original model had 353 W/K.

At the configured 55% front torque bias, a rolling stop from 40, 80 or 100 km/h of a 1,095 kg car would produce adiabatic temperature rises of approximately 7.85, 31.39 and 49.05 C per front disc, respectively, assuming the translational energy is dissipated by the service brakes and 95% enters the rotors. Drag, slip heat, engine braking, rotational energy and cooling change those estimates. The HUD reads the published brake_disc_c directly and marks below 150 C as cold; it is possible to remain in that color range after a single moderate-speed stop without a sensor fault. No artificial minimum disc temperature or heat multiplier is applied.

The published per-wheel state now also contains brake_heating_w, brake_cooling_w and brake_convection_w_k, so input work and modeled heat loss can be distinguished from a HUD threshold in subsequent observations. No tests were created or executed for this revision; the numbers above are direct analytical calculations.

The current implementation uses configured 95% heat fraction, cold efficiency, fade start, critical temperature and minimum fade efficiency. Pad friction actually depends on temperature, speed, pressure and energy; AP Racing warns that pad temperature windows are comparative and depend on disc mass and cooling. The configured fade curve is consequently a controllable approximation, not a claim that the exact historic pad compound has been identified.

## Work performed

- Corrected airborne wheel braking so torque opposes forward or reverse spin and airborne brake work heats the disc.
- Replaced the geometry-independent 2,500 J/K and 353 W/K-style cooling calculation with axle-specific rotor mass, swept area, convection and radiation.
- Connected the simplified brake fade calculation to the existing cold/fade thresholds and efficiency values.
- Left the 55% front bias and 5,500 Nm total unchanged pending a defensible CG height and brake-hardware definition.

## Sources

- Ford Escort Rally Preparation, brake chapter: <https://www.doublegmotorsport.com/rsprep/09-Brakes.pdf>
- AP Racing, pad characteristics and temperature-range caveat: <https://apracing.com/race-car/brake-pads/pad-characteristics>
- Brake thermal modelling review: <https://www.mdpi.com/1996-1073/13/1/203>
- Longitudinal vehicle load and pitch-moment equations: <https://www.mathworks.com/help/sdl/ref/vehiclebody.html>
- ASHRAE external-flow Nusselt correlations: <https://handbook.ashrae.org/Handbooks/F25/SI/f25_ch04/f25_ch04_si.aspx>
- Lienhard, A Heat Transfer Textbook, natural convection, section 8.3: <https://bpb-us-e1.wpmucdn.com/sites.mit.edu/dist/6/1810/files/2024/04/AHTTv600.pdf>
