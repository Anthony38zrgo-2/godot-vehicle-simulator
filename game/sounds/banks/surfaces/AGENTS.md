# surfaces — shared rolling and tire slip bank

Source truth: manifest.json; regenerate with python -m tools.audio.cmr4_surfaces extract / prepare / verify. Original decrypted WAVs and config roles live in game/sounds/bank_sources/cmr4/surfaces. Keep filenames, source hashes and processing provenance. Runtime uses exterior samples only, at native PCM16 mono 22050 Hz. Loops have a baked 120 ms crossfade; do not apply another runtime crossfade.

Unified overrides (tool revision 2): gravel, dirt and sand share artofrally/gravel.wav, built from the art of rally clip gravel3 (bank_sources/artofrally/surfaces/06_tierra_rodadura__gravel3.wav); every grass role shares artofrally/grass.wav, built from grass2 (04_hierba_rodadura__grass2.wav). Rebuild them with python -m tools.audio.cmr4_surfaces unify; prepare also regenerates them. The legacy surf_sand.wav stays archived but is no longer mapped. Snow, ice, mud, mul and special events remain inactive until the scenario identifies them.
