# Rally consumable wear tuning

`rally_wear.json` controls per-wheel brake wear independently of tire replacements and collision damage. Actual brake work from the powertrain solver is accumulated through the thermal update. At the baseline rate, 1 MJ consumes 2% of brake life. Work above 550 C progressively increases consumption up to 3x at 800 C. No brake work means no natural wear. At complete wear, the configured maximum torque loss is 65%; the response exponent of 1.5 makes the early loss gentler. Temperature fade and collision loss multiply this remaining efficiency separately.

Brake wear survives stage thermal preparation and is stored in the event vehicle damage snapshot. Older saves without this field start at zero natural brake wear. It is not a replaceable tire-state field. The per-wheel HUD shows remaining brake condition as F percent unless collision damage takes warning priority.

Tire wear remains friction-work based with permanent overheating damage. The normal compound now uses 1e-8/J, with 0.85x abrasion when wet. The rain compound uses 1.6e-8/J, with 1.6x abrasion in dry conditions. Wet/dry abrasion blends across 0.1-1 mm of water. Existing durability_life_scale (0.425) still applies. Full wear reduces tire grip by 35% (normal) or 40% (rain), before other grip factors. These are initial gameplay tuning values, not measured stage-life guarantees.

No tests or driving validation were run for this change, at the user's request.
