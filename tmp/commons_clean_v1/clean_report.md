# Limpieza del banco `commons`

Techo de pico real: -3.0 dBFS. Dither TPDF, PCM16 mono 44.1 kHz.

| archivo | LUFS antes | LUFS después | TP antes | TP después | sub30 antes | sub30 después | dur antes | dur después | ganancia dB | acciones |
|---|---|---|---|---|---|---|---|---|---|---|
| backfire_1.wav | -16.8 | -18.8 | -2.10 | -3.00 | 0.4 | 0.1 | 0.474 | 0.474 | -2.06 | hpf 30 Hz, match backfire_ext (-16.8->-18.8 LUFS) |
| backfire_5.wav | -9.5 | -15.6 | 0.03 | -3.00 | 0.1 | 0.0 | 0.159 | 0.159 | -3.77 | hpf 30 Hz, trim -3.8 dB (pico sobre techo), limit +3.8->-3.0 dBFS (-3.0 dB pico) |
| backfire_7.wav | -16.8 | -18.8 | -2.10 | -3.00 | 0.4 | 0.1 | 0.474 | 0.474 | -2.06 | hpf 30 Hz, match backfire_ext (-16.8->-18.8 LUFS) |
| backfire_9.wav | -10.4 | -18.8 | -0.86 | -5.83 | 1.5 | 0.3 | 0.430 | 0.430 | -8.34 | hpf 30 Hz, fade-in 0.4 ms, match backfire_ext (-10.5->-18.8 LUFS) |
| backfire_ext_1.wav | -16.8 | -18.8 | -2.10 | -3.00 | 0.4 | 0.1 | 0.474 | 0.474 | -2.06 | hpf 30 Hz, match backfire_ext (-16.8->-18.8 LUFS), alias de backfire_1.wav (mismo sha256) |
| backfire_ext_2.wav | -16.8 | -18.8 | -2.10 | -3.00 | 0.4 | 0.1 | 0.474 | 0.474 | -2.06 | hpf 30 Hz, match backfire_ext (-16.8->-18.8 LUFS), alias de backfire_1.wav (mismo sha256) |
| backfire_ext_3.wav | -16.8 | -18.8 | -2.10 | -3.00 | 0.4 | 0.1 | 0.474 | 0.474 | -2.06 | hpf 30 Hz, match backfire_ext (-16.8->-18.8 LUFS), alias de backfire_7.wav (mismo sha256) |
| backfire_ext_4.wav | -10.4 | -18.8 | -0.86 | -5.83 | 1.5 | 0.3 | 0.430 | 0.430 | -8.34 | hpf 30 Hz, fade-in 0.4 ms, match backfire_ext (-10.5->-18.8 LUFS), alias de backfire_9.wav (mismo sha256) |
| backfire_int.wav | -9.5 | -15.6 | 0.03 | -3.00 | 0.1 | 0.0 | 0.159 | 0.159 | -3.77 | hpf 30 Hz, trim -3.8 dB (pico sobre techo), limit +3.8->-3.0 dBFS (-3.0 dB pico), alias de backfire_5.wav (mismo sha256) |
| bad_brakes.wav | -19.2 | -19.2 | -9.36 | -9.35 | 0.0 | 0.0 | 1.080 | 1.080 | +0.00 | hpf 35 Hz |
| damaged_rin.wav | -19.0 | -19.0 | -4.17 | -4.34 | 0.0 | 0.0 | 2.471 | 2.471 | +0.00 | hpf 35 Hz |
| f2002_geardn.wav | -16.1 | -17.1 | -3.56 | -4.15 | 0.5 | 0.2 | 0.194 | 0.194 | -0.85 | hpf 30 Hz, match gearbox_f2002 (-16.3->-17.1 LUFS) |
| f2002_gearup.wav | -17.9 | -17.1 | -5.68 | -4.85 | 1.3 | 0.4 | 0.296 | 0.296 | +0.85 | hpf 30 Hz, match gearbox_f2002 (-18.0->-17.1 LUFS) |
| flat_tyre_mono.wav | -20.8 | -21.0 | -3.82 | -3.73 | 2.6 | 0.6 | 8.815 | 8.815 | +0.00 | hpf 35 Hz |
| impact_land_1.wav | -14.2 | -16.5 | -0.99 | -3.00 | 0.0 | 0.0 | 0.496 | 0.496 | -2.31 | hpf 30 Hz, match impact_land (-14.2->-16.5 LUFS) |
| impact_land_2.wav | -9.8 | -16.5 | -0.42 | -4.80 | 6.2 | 0.1 | 0.821 | 0.821 | -6.65 | hpf 30 Hz, match impact_land (-9.8->-16.5 LUFS) |
| impact_land_3.wav | -14.2 | -16.9 | -0.84 | -3.00 | 8.6 | 2.2 | 0.922 | 0.922 | -2.33 | hpf 30 Hz, match impact_land (-14.3->-16.5 LUFS), trim -0.2 dB (pico sobre techo), limit -1.0->-3.0 dBFS (-1.9 dB pico) |
| impact_large.wav | -15.7 | -16.1 | -0.92 | -3.00 | 0.4 | 0.1 | 1.132 | 1.132 | -0.18 | hpf 30 Hz, trim -0.2 dB (pico sobre techo), limit -1.0->-3.0 dBFS (-2.0 dB pico) |
| impact_medium_1.wav | -14.2 | -17.8 | -0.95 | -3.00 | 1.9 | 0.6 | 0.804 | 0.804 | -3.64 | hpf 30 Hz, match impact_medium (-14.2->-17.8 LUFS), limit -3.0->-3.0 dBFS (-0.0 dB pico) |
| impact_medium_2.wav | -15.5 | -17.8 | -1.00 | -3.03 | 0.4 | 0.1 | 0.787 | 0.787 | -2.22 | hpf 30 Hz, match impact_medium (-15.6->-17.8 LUFS) |
| impact_scrape.wav | -14.4 | -14.4 | -3.00 | -2.99 | 0.0 | 0.0 | 2.348 | 2.288 | +0.00 | hpf 30 Hz, loop crossfade 60 ms |
| impact_small_1.wav | -12.3 | -16.3 | -1.01 | -3.19 | 14.0 | 3.4 | 0.579 | 0.579 | -3.86 | hpf 30 Hz, match impact_small (-12.4->-16.3 LUFS) |
| impact_small_2.wav | -12.6 | -16.3 | -0.99 | -3.00 | 3.3 | 0.2 | 0.624 | 0.624 | -3.67 | hpf 30 Hz, match impact_small (-12.6->-16.3 LUFS) |
| impact_small_3.wav | -14.2 | -16.5 | -1.00 | -3.00 | 6.4 | 0.9 | 0.555 | 0.555 | -2.32 | hpf 30 Hz, match impact_small (-14.2->-16.3 LUFS), trim -0.2 dB (pico sobre techo), limit -2.4->-3.0 dBFS (-0.6 dB pico) |
| limiter_cut_loop.wav | -9.4 | -14.2 | -0.72 | -3.00 | 0.2 | 0.0 | 7.349 | 7.349 | -4.75 | hpf 35 Hz, attenuate +1.8->-3.0 dBFS |
| neutral_first_gear_transition.wav | -23.1 | -23.2 | -3.00 | -3.30 | 1.1 | 0.1 | 0.741 | 0.741 | +0.00 | hpf 30 Hz |
| tyre_contact.wav | -15.2 | -15.9 | -0.10 | -3.00 | 0.6 | 0.2 | 0.358 | 0.358 | -0.01 | downmix 2->1, hpf 30 Hz, limit -0.1->-3.0 dBFS (-2.9 dB pico) |
