# commons — Shared non-engine bank

Scope: the shared bank for impacts, surfaces, and tire scrub, with its manifest.
The shared neutral/first-gear contact sample layers with the existing upshift
recording only on confirmed N-to-first or first-to-N transitions. Its source is
`../../bank_sources/neutral_first_gear_transition_source.wav`; regenerate its
runtime WAV and manifest entry with `python -m tools.audio.prepare_neutral_first_gear_sample`.
Consumers: every session needing non-engine sounds.
The metallic underfloor `impact_scrape.wav` source is
`../../bank_sources/underfloor_metallic_scrape_source.wav`; regenerate its runtime
WAV and manifest entry with `python -m tools.audio.prepare_underfloor_metallic_scrape_sample`.
Preparation preserves the supplied pitch and duration, downmixes to mono PCM16
at 44.1 kHz, removes the mean offset, and limits true peak through attenuation
to -3 dBFS.
Rules: stays V10-agnostic by design. Never merge it into an engine bank and never rename its `bank_manifest.json`.
Rolling/impact provenance: `surf_grass`, `surf_gravel`, `surf_sand`, `surf_rumble` and the `impact_*` one-shots are promoted from the original Colin McRae Rally 2 PC install (`Sounds/surface.bfl` outside-rolling loops, `Game/Bigfiles/common.bfl` `collis1-6` crashes). All are mono PCM16 at 44.1 kHz with the mean removed and peak 0.89; rolling loops carry a 120 ms equal-power loop crossfade. Gravel has its own `surf_gravel` loop (the stage road); loose `Dirt` shoulders reuse it, `Sand` keeps its own loop, and asphalt rolling stays on `tyre_scrub`. `impact_scrape` is retained (no loopable CMR2 equivalent).
