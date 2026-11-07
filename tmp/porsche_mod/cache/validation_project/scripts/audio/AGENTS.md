# audio — Audio GDScript

Scope: Godot-side audio wiring, including the vehicle bus setup.
Consumers: vehicle and session scenes.
Rules: the independent simulator reinterprets the Rust audio rules in GDScript. Sample truth lives in `game/sounds/banks/`; Godot owns audio-thread mixing and resampling. No Rust runtime is required. Keep source provenance and identify local acoustic approximations.
