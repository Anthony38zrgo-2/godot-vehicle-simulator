import json, pathlib

vehicles = {
    'lancia-fulvia': r'game\data\vehicles\lancia-fulvia',
    'ford-escort-rs2000': r'game\data\vehicles\ford-escort-rs2000',
    'rt-alfa-giulia-gta': r'game\data\vehicles\rt\rt-alfa-giulia-gta',
    'rt-alpine-a110': r'game\data\vehicles\rt\rt-alpine-a110',
    'rt-escort-rs2000': r'game\data\vehicles\rt\rt-escort-rs2000',
    'rt-fiat-abarth-1000': r'game\data\vehicles\rt\rt-fiat-abarth-1000',
    'rt-lancia-fulvia': r'game\data\vehicles\rt\rt-lancia-fulvia',
    'rt-lancia-stratos': r'game\data\vehicles\rt\rt-lancia-stratos',
    'rt-lotus-cortina': r'game\data\vehicles\rt\rt-lotus-cortina',
    'rt-mini-cooper-s': r'game\data\vehicles\rt\rt-mini-cooper-s',
    'rt-opel-kadett': r'game\data\vehicles\rt\rt-opel-kadett',
    'rt-porsche-356a': r'game\data\vehicles\rt\rt-porsche-356a',
    'rt-saab-96-v4': r'game\data\vehicles\rt\rt-saab-96-v4',
    'rt-volvo-amazon': r'game\data\vehicles\rt\rt-volvo-amazon',
}

for name, path_str in vehicles.items():
    p = pathlib.Path(path_str)
    ch = json.loads((p / 'chassis.json').read_text(encoding='utf-8'))
    pw = json.loads((p / 'powertrain.json').read_text(encoding='utf-8'))['powertrain']
    su = json.loads((p / 'suspension.json').read_text(encoding='utf-8'))['suspension']
    st = json.loads((p / 'steering.json').read_text(encoding='utf-8'))['steering']
    br = json.loads((p / 'brakes.json').read_text(encoding='utf-8'))['brakes']
    
    mass = ch['chassis'].get('vehicle_mass')
    fdist = ch['chassis'].get('front_weight_distribution')
    cgz = ch['chassis'].get('target_cg_z_m')
    wb = ch['geometry'].get('wheelbase')
    ft = ch['geometry'].get('front_track')
    rt_ = ch['geometry'].get('rear_track')
    
    # Check body inertia
    comps = ch.get('physical_mass_inventory', {}).get('components', [])
    body_comp = next((c for c in comps if c.get('properties', {}).get('name') in ['body_and_systems', 'bodywork_and_cage']), None)
    if body_comp:
        m_body = body_comp['properties'].get('mass_kilograms')
        in_matrix = body_comp['properties'].get('inertia_about_center_of_mass', {}).get('entries_kilogram_square_metres', [[0,0,0],[0,0,0],[0,0,0]])
        body_ix = in_matrix[0][0]
        body_iy = in_matrix[1][1]
        body_iz = in_matrix[2][2]
    else:
        m_body, body_ix, body_iy, body_iz = None, None, None, None
    
    tq = pw.get('max_torque')
    rpm = pw.get('max_rpm')
    gears = pw.get('gear_ratios')
    final = pw.get('final_drive')
    gravel_final = pw.get('final_drive_gravel')
    tarmac_final = pw.get('final_drive_tarmac')
    diff = pw.get('differential', {})
    
    bump = su.get('geometry_physical', {}).get('front', {}).get('wheel_bump_m')
    droop = su.get('geometry_physical', {}).get('front', {}).get('wheel_droop_m')
    camF = su.get('front', {}).get('camber')
    camR = su.get('rear', {}).get('camber')
    axleF = su.get('front', {}).get('axle_type')
    axleR = su.get('rear', {}).get('axle_type')
    
    turns = st.get('turns_lock_to_lock')
    ratio = st.get('ratio_to_one')
    
    bias = br.get('front_brake_bias')
    max_b = br.get('max_brake_torque')
    servo = br.get('servo_assist', {})
    
    print(f'=== {name} ===')
    print(f'  Mass: {mass} kg (Body: {m_body} kg), Fdist: {fdist}, CGz: {cgz} m')
    print(f'  Body Inertia [Ix(pitch), Iy(yaw), Iz(roll)]: [{body_ix}, {body_iy}, {body_iz}]')
    print(f'  Geometry: WB: {wb} m, Track: {ft}/{rt_} m')
    print(f'  Powertrain: {tq} Nm @ {rpm} rpm, Gears: {gears}, Final: {final} (Gravel: {gravel_final}, Tarmac: {tarmac_final})')
    print(f'  Differential: Preload={diff.get("preload_nm")} Nm, Lock={diff.get("lock_pct_power")}%/{diff.get("lock_pct_coast")}%, Ramps={diff.get("power_ramp_angle_deg")}/{diff.get("coast_ramp_angle_deg")}')
    print(f'  Suspension: Axles={axleF}/{axleR}, Bump={bump} m, Droop={droop} m, CamF={round(camF*57.2958, 2) if camF is not None else None} deg, CamR={round(camR*57.2958, 2) if camR is not None else None} deg')
    print(f'  Steering: Turns={turns}, Ratio={ratio}:1')
    print(f'  Brakes: Bias={bias}, MaxTq={max_b} Nm, Servo={servo}')
