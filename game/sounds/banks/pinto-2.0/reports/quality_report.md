# Rally Maniac Sample Bank Quality Report

- **Profile ID**: `pinto-rs2000-7wot`
- **Display Name**: Ford Escort RS2000 Mk1/Mk2 2.0L Pinto 7-state compact bank (idle=900, low=2300, mid=4300, max=7300 RPM)
- **Technical Demo Status**: `true` (`Ford Escort RS2000 2.0L Pinto SOHC L4 (7-state bank: idle 900, WOT 2300/4300/7300 @ throttle=1.0, coast overrun 2300/4300/7300 @ throttle=0.0)`)
- **Geometry**: 4 cylinders, 720 deg cycle, firing order `[1, 3, 4, 2]`, angles `[0.0, 180.0, 360.0, 540.0]`
- **Format**: 48000 Hz mono, `pcm16` primary delivery (`14 clips total`)
- **RPM Anchors**: idle `900`, low `2300`, mid `4300`, high `7300`, redline `7300`
- **Memory Footprint (decoded float32 in-RAM bank)**: `5.13 MiB`
- **Clip Safety**: all peaks < -1.0 dBFS = `true`, max |DC| = `0.000005`, sequence 08 determinism = `true`

## Uniform Per-Bus Headroom

| Bus | Peak Before (dBFS) | Uniform Gain | Peak After (dBFS) |
| --- | ---: | ---: | ---: |
| `exhaust` | -2.43 | 0.88387 | -3.50 |
| `mechanical` | -7.29 | 1.54669 | -3.50 |

## Delivered Loops Telemetry (§8.1)

| Key | Bus | Nominal RPM | Native RPM | Torque | Cycles | Len (smp) | Start Phase (deg) | RMS (dBFS) | Peak (dBFS) | Crest (dB) | Seam Score | Amp Diff | Spec Diff (dB) |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `idle_idle_exhaust` | `exhaust` | 900 | 900.00 | +0.05 | 15 | 96000 | 11520.0 | -28.40 | -17.64 | 10.76 | 1.4162 | 0.01015 | 4.81 |
| `idle_idle_mechanical` | `mechanical` | 900 | 900.00 | +0.05 | 15 | 96000 | 11520.0 | -20.06 | -13.50 | 6.56 | 0.5043 | 0.00000 | 3.65 |
| `low_high_load_exhaust` | `exhaust` | 2300 | 2300.01 | +1.00 | 38 | 95165 | 29520.0 | -21.61 | -11.32 | 10.29 | 1.0741 | 0.02421 | 8.45 |
| `low_high_load_mechanical` | `mechanical` | 2300 | 2300.01 | +1.00 | 38 | 95165 | 29520.0 | -7.53 | -3.50 | 4.03 | 0.3927 | 0.00000 | 3.10 |
| `low_overrun_exhaust` | `exhaust` | 2300 | 2300.01 | -0.50 | 38 | 95165 | 35280.0 | -24.76 | -16.55 | 8.21 | 1.5884 | 0.00391 | 6.92 |
| `low_overrun_mechanical` | `mechanical` | 2300 | 2300.01 | -0.50 | 38 | 95165 | 35280.0 | -9.87 | -6.47 | 3.40 | 0.4575 | 0.00018 | 1.71 |
| `mid_high_load_exhaust` | `exhaust` | 4300 | 4299.98 | +1.00 | 72 | 96447 | 59040.0 | -8.70 | -3.66 | 5.04 | 0.4939 | 0.00159 | 2.89 |
| `mid_high_load_mechanical` | `mechanical` | 4300 | 4299.98 | +1.00 | 72 | 96447 | 59040.0 | -13.39 | -6.64 | 6.74 | 0.3913 | 0.00000 | 2.80 |
| `mid_overrun_exhaust` | `exhaust` | 4300 | 4299.98 | -0.50 | 72 | 96447 | 61920.0 | -10.90 | -6.19 | 4.71 | 0.6643 | 0.00284 | 3.93 |
| `mid_overrun_mechanical` | `mechanical` | 4300 | 4299.98 | -0.50 | 72 | 96447 | 61920.0 | -15.30 | -11.58 | 3.72 | 0.3235 | 0.00001 | 2.11 |
| `high_high_load_exhaust` | `exhaust` | 7300 | 7300.00 | +1.00 | 122 | 96263 | 128880.0 | -11.15 | -3.50 | 7.65 | 0.5604 | 0.00875 | 2.43 |
| `high_high_load_mechanical` | `mechanical` | 7300 | 7300.00 | +1.00 | 122 | 96263 | 128880.0 | -10.84 | -5.72 | 5.12 | 0.4954 | 0.00007 | 2.51 |
| `high_overrun_exhaust` | `exhaust` | 7300 | 7300.00 | -0.50 | 122 | 96263 | 77040.0 | -12.61 | -5.98 | 6.63 | 0.8037 | 0.00452 | 4.46 |
| `high_overrun_mechanical` | `mechanical` | 7300 | 7300.00 | -0.50 | 122 | 96263 | 77040.0 | -15.45 | -9.64 | 5.81 | 0.3784 | 0.00000 | 0.87 |

## Transition & Playback Audit Sequences (§8.2, 100 Hz telemetry)

| File | Dur (s) | Peak (dBFS) | RMS (dBFS) | Max Delta | Max D2 | Max 50ms Step (dB) | Low/Mid/High (dBFS) | CPU Realtime |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| `audit/01_idle_to_high_ramp.wav` | 6.0 | -0.87 | -9.25 | 0.08541 | 0.04870 | 1.73 | -10.6 / -10.0 / -24.3 | 125.2x |
| `audit/02_high_to_idle_lift.wav` | 6.0 | -0.74 | -11.74 | 0.08900 | 0.05266 | 2.24 | -13.5 / -12.1 / -26.5 | 128.5x |
| `audit/03_partial_to_high_load_step.wav` | 4.0 | -3.21 | -8.22 | 0.06350 | 0.02772 | 1.67 | -8.7 / -10.7 / -26.4 | 231.2x |
| `audit/04_drive_to_overrun_oscillation.wav` | 4.0 | -3.21 | -9.01 | 0.06350 | 0.02772 | 1.67 | -9.5 / -11.5 / -27.4 | 146.9x |
| `audit/05_upshift_1_2_3.wav` | 5.0 | -0.88 | -7.75 | 0.08655 | 0.04627 | 0.97 | -9.1 / -8.3 / -23.3 | 118.0x |
| `audit/06_downshift_blip.wav` | 4.0 | -2.69 | -11.20 | 0.05659 | 0.02596 | 1.63 | -12.1 / -12.5 / -28.3 | 93.5x |
| `audit/07_clutch_in_out_glide.wav` | 4.0 | -3.21 | -9.64 | 0.06915 | 0.04017 | 1.67 | -10.4 / -12.0 / -25.5 | 138.4x |
| `audit/08_determinism_check.wav` | 2.5 | -0.79 | -10.30 | 0.08665 | 0.05433 | 2.51 | -12.0 / -10.6 / -24.9 | 103.2x |
| `audit/09_full_throttle_sweep.wav` | 6.0 | -0.87 | -9.25 | 0.08541 | 0.04870 | 1.73 | -10.6 / -10.0 / -24.3 | 123.4x |
| `audit/10_full_coast_overrun.wav` | 6.0 | -3.62 | -12.74 | 0.04980 | 0.02531 | 1.18 | -13.9 / -14.0 / -28.8 | 109.6x |
| `audit/11_sweep_then_coast.wav` | 12.0 | -0.87 | -10.64 | 0.08541 | 0.04870 | 2.17 | -11.9 / -11.5 / -26.0 | 111.2x |

## Profile Warnings

- idle->low pitch ratio is 16.24 semitones (900->2300 RPM, >1 octave); enable dynamic idle->low transition window or lower low_rpm in final historical profile
- Using preset_base='pinto-rs2000' as acoustic/thermodynamic baseline; missing profile fields fall back to this technical demo preset (not final historical validation).

## Missing or Approximate Historical Parameters

| Parameter Path | Fallback / Approximate Value Used | Origin | Impact |
| --- | --- | --- | --- |
| `geometry.rod_length_mm` | `126.8700 mm` | `fallback from pinto-rs2000` | Slider-crank harmonic distortion |
| `geometry.exhaust_valve_diameter_mm` | `36.0000 mm` | `fallback from pinto-rs2000` | Exhaust blowdown curtain area and sharpness |
| `geometry.exhaust_max_lift_mm` | `10.5000 mm` | `fallback from pinto-rs2000` | Exhaust mass-flow envelope |
| `geometry.exhaust_open_deg` | `126.0000 deg` | `fallback from pinto-rs2000` | EVO timing phase |
| `geometry.exhaust_duration_deg` | `172.0000 deg` | `fallback from pinto-rs2000` | Exhaust valve open duration |
| `geometry.header_lengths_mm` | `[0.72, 0.75, 0.76, 0.71] m` | `fallback from pinto-rs2000` | Primary runner standing-wave resonances |
| `geometry.collector_volume_l` | `1.650 L` | `fallback from pinto-rs2000` | Collector Helmholtz resonance |
| `geometry.collector_outlet_length_m` | `0.560 m` | `fallback from pinto-rs2000` | Tailpipe quarter/half-wave resonance |
| `geometry.collector_outlet_diameter_m` | `0.052 m` | `fallback from pinto-rs2000` | Tailpipe radiation impedance |
| `geometry.collector_gas_temperature_k` | `880.0 K` | `fallback from pinto-rs2000` | Exhaust speed of sound |
