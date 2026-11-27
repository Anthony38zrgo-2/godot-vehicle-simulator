# Menu GUI Component Architecture (SOLID · Atomic Design · Data-Driven JSON)

This document describes the modular menu GUI architecture under `game/data/ui/`, `game/scripts/ui/`, and `game/ui/`.

> **Scope**: All menu screens (Main Menu, Stage/Car/Weather Select, Garage & Setup, Tire Strategy, Pause & Inventory, Service Panel & Workshop, Competition Results & Podium, Tire Tuner, Loading Overlay). In-track real-time HUD scripts (`rally_f1_head_up_display.gd`, `formula_hud_panels.gd`, `cmr2_pacenote_hud.gd`, `rally_start_lights.gd`) remain intentionally isolated for per-frame telemetry rendering.

---

## 1. Directory Layout

```text
game/
├── data/ui/
│   ├── tokens.json                  # Design tokens: colors, fonts, radii, spacing, motion, sizes
│   ├── component_presets.json       # Composable style presets with `extends` inheritance
│   └── menus/
│       ├── countries_stages.json    # Country / stage catalog, difficulty & terrain tags
│       ├── main_menu.json           # Main menu actions & descriptions
│       ├── weather_options.json     # Weather presets & icon/badge colors
│       ├── garage_layout.json       # Garage tab metadata & setup parameter group layout
│       ├── service_parts.json       # Serviceable mechanical parts, repair costs & wear thresholds
│       └── pause_actions.json       # Pause menu action specs
├── scripts/ui/
│   ├── core/
│   │   ├── ui_token_registry.gd     # Loads & caches tokens, fonts, presets, and StyleBoxFlat instances
│   │   ├── ui_theme_builder.gd      # Builds cached Godot Theme + applies preset/tone styling
│   │   ├── ui_component_factory.gd  # Factory methods for preset-driven Controls
│   │   ├── ui_focus_navigator.gd    # Keyboard/gamepad focus wrapping & restoration
│   │   ├── ui_screen_view.gd        # Base screen lifecycle (`on_enter`, `on_exit`, `get_initial_focus`)
│   │   └── ui_navigation_stack.gd   # Push/pop navigation stack with focus memory
│   └── services/
│       ├── menu_catalog_service.gd      # Loads & caches declarative menu JSON catalogs
│       ├── service_repair_calculator.gd # Pure repair time/cost calculations from `service_parts.json`
│       ├── tire_tuner_catalog_service.gd# Tire tuner schema, file IO & backups
│       └── garage_setup_presenter.gd    # Vehicle registry resolution, stage route/altitude/terrain loaders, field formatting
└── ui/
    ├── atoms/          # Lightweight pure `.gd` (`class_name`) primitives
    ├── molecules/      # Reusable `.tscn` + `.gd` UI blocks (headers, footers, cards, tabs, sliders, confirm dialog)
    ├── organisms/      # Complex domain components (`UIModalShell`, `UIDamageOverview`, `UIVehicleShowroom`, `UIRoutePreview`, `UITelemetryChart`, `UITireSlotCard`, `UITireBoard3D`)
    └── screens/        # Screen-specific editable `.tscn` + `.gd` views
        ├── main_menu/  # `main_menu_view`, `stage_select_view`, `car_select_view`, `weather_select_view`
        ├── pause/      # `pause_telemetry_sidebar`
        ├── competition/# `stage_results_view`, `final_podium_view`
        ├── strategy/   # `tire_strategy_step1_view`, `tire_strategy_step2_view`
        └── garage/     # `garage_stage_tab`, `garage_chassis_tab`, `garage_powertrain_tab`, `garage_strategy_tab`
```

---

## 2. Core Principles & Invariants

1. **Single Source of Truth for Visuals (JSON Tokens + StyleBox Caching)**:
   - Never hardcode palette constants (`const C_*`, `const BG_*`) or call `StyleBoxFlat.new()` directly in menu scripts or UI components.
   - Always resolve colors, radii, spacing, and fonts through `UITokenRegistry` (`res://scripts/ui/core/ui_token_registry.gd`) and `UIThemeBuilder` (`res://scripts/ui/core/ui_theme_builder.gd`).
   - `UITokenRegistry.get_flat_stylebox(...)` deduplicates and caches `StyleBoxFlat` instances by key.
   - `RallyUITheme` (`res://scripts/rally/rally_ui_theme.gd`) remains as a thin backwards-compatible facade delegating to `UITokenRegistry` and `UIThemeBuilder`.

2. **Real Godot `Control` Trees (Zero Immediate-Mode UI `_draw()`)**:
   - All menu screens — including `RallyGaragePanel` and `RallyTireStrategyScreen` — use real Godot `Control` nodes, native signals, and standard focus/mouse handling.
   - Immediate-mode `_draw()` is reserved strictly for custom vector visualizations (`UIRoutePreview`, `UITelemetryChart`, `UISpinner`) and 3D drag/drop overlays.

3. **Hybrid `.tscn` + `.gd` Pattern with Dual Instantiation**:
   - Molecules, organisms, and screen views ship as `.tscn` + `.gd` pairs so they can be inspected in the Godot editor while also working when instantiated directly via `.new()` in scripts or headless tests.
   - Every view script uses an idempotent `_ensure_nodes()` helper called from both `_ready()` and public `populate()` / `configure()` entry points.

4. **Headless Cold-Cache Safety (`preload` Convention)**:
   - Under `godot.cmd --headless`, newly added `class_name` identifiers may not exist in `.godot/global_script_class_cache.cfg`.
   - Always reference core/service/component scripts via `const _Tokens := preload("res://scripts/ui/core/ui_token_registry.gd")` rather than bare `class_name` type hints across newly created files.

5. **Presenter / Controller Separation (SRP)**:
   - View scripts (`game/ui/screens/...`) only render state passed into `populate(data)` / `sync_view(data)` and emit semantic signals (`tab_selected`, `value_changed`, `confirm_pressed`, etc.).
   - Domain logic, JSON IO, and calculations live in `game/scripts/ui/services/`.
   - Orchestrator panels (`game/scripts/rally/rally_*_panel.gd`) bind gameplay/vehicle state to views and preserve public APIs and contract signals.

---

## 3. Adding a New Menu Screen or Component

1. **Tokens / Presets**: If a new color, spacing, or visual variant is needed, add it to `game/data/ui/tokens.json` or `game/data/ui/component_presets.json` (using `"extends"` to inherit from an existing preset).
2. **Menu Data**: Put static labels, options, and metadata into `game/data/ui/menus/<menu_name>.json` and read it via `MenuCatalogService.load_catalog("<menu_name>")`.
3. **Create the Component**:
   - Atom (stateless visual primitive or vector chart): add `game/ui/atoms/ui_<name>.gd`.
   - Molecule / Organism / Screen view: add `game/ui/<tier>/<name>.gd` + `game/ui/<tier>/<name>.tscn` with `_ensure_nodes()` and signal-only outward communication.
4. **Register in Contract**: Add the new `.tscn` or `.gd` path to `COMPONENT_SCENES` / `COMPONENT_SCRIPTS` in `game/tests/rally/ui_architecture_contract.gd`.
5. **Verify**: Run:
   ```powershell
   godot.cmd --headless --path game -s res://tests/rally/ui_architecture_contract.gd
   ```
