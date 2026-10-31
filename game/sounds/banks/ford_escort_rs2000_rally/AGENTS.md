# ford_escort_rs2000_rally — Ford engine and exhaust samples

Scope: eight Ford Escort engine/exhaust WAV samples copied from the Open Formula Rally Trophy staging car, plus the twelve Escort-only Colin McRae Rally 2 Cosworth voices (`fm/rm-cos` retention pair, `rs/rt-cos` exhaust layers, `ft-cos`/`whine` whine pair, `chatter`, `det1-4` backfires, `detidle`): everything in this bank applies to the Escort alone, never to the shared commons bank.
Consumers: `game/scripts/rally/rally_vehicle_audio.gd`.
Rules: preserve the original sample filenames and do not resample in place. The source hashes and the nominal RPM mapping are recorded in `manifest.json`. These are playback samples; no DSP synthesis or thermal audio model is active in the rally experiment.

The Rally audio controller uses the samples at their native 22050 Hz mono rate and owns crossfading by measured engine RPM. Reference centres and the source `Sounds.ini` ranges are recorded in `manifest.json`; `EX_2k5.wav` remains in the source folder but is not referenced by `Sounds.ini` and is not played.

Bank selection is explicit for the Rally session. This bank is the source of its engine and exhaust samples; shared impact, surface and tire sounds remain in `sounds/banks/commons/`.
