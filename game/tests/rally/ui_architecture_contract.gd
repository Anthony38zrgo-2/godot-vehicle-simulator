extends SceneTree
## Contract test verifying SOLID UI architecture, Data-Driven JSON tokens/presets/catalogs,
## StyleBoxFlat caching, focus navigation, screen stack, reusable Atomic Design components,
## and strict architectural invariants (zero inline StyleBoxFlat.new() in migrated menus,
## zero immediate-mode _draw() / _hit_regions in garage and tire strategy screens).

const UITokenRegistry := preload("res://scripts/ui/core/ui_token_registry.gd")
const UIThemeBuilder := preload("res://scripts/ui/core/ui_theme_builder.gd")
const UIComponentFactory := preload("res://scripts/ui/core/ui_component_factory.gd")
const UIFocusNavigator := preload("res://scripts/ui/core/ui_focus_navigator.gd")
const UINavigationStack := preload("res://scripts/ui/core/ui_navigation_stack.gd")
const UIScreenView := preload("res://scripts/ui/core/ui_screen_view.gd")
const MenuCatalogService := preload("res://scripts/ui/services/menu_catalog_service.gd")
const ServiceRepairCalculator := preload("res://scripts/ui/services/service_repair_calculator.gd")
const TireTunerCatalogService := preload("res://scripts/ui/services/tire_tuner_catalog_service.gd")
const GarageSetupPresenter := preload("res://scripts/ui/services/garage_setup_presenter.gd")

const COMPONENT_SCENES: Array[String] = [
	# Molecules
	"res://ui/molecules/ui_panel_header.tscn",
	"res://ui/molecules/ui_panel_footer.tscn",
	"res://ui/molecules/ui_stat_card.tscn",
	"res://ui/molecules/ui_selectable_card.tscn",
	"res://ui/molecules/ui_tab_bar.tscn",
	"res://ui/molecules/ui_slider_row.tscn",
	"res://ui/molecules/ui_podium_card.tscn",
	"res://ui/molecules/ui_confirm_dialog.tscn",
	# Organisms
	"res://ui/organisms/ui_modal_shell.tscn",
	"res://ui/organisms/ui_damage_overview.tscn",
	"res://ui/organisms/ui_vehicle_showroom.tscn",
	# Screens: Main Menu
	"res://ui/screens/main_menu/main_menu_view.tscn",
	"res://ui/screens/main_menu/stage_select_view.tscn",
	"res://ui/screens/main_menu/car_select_view.tscn",
	"res://ui/screens/main_menu/weather_select_view.tscn",
	# Screens: Pause & Competition
	"res://ui/screens/pause/pause_telemetry_sidebar.tscn",
	"res://ui/screens/competition/stage_results_view.tscn",
	"res://ui/screens/competition/final_podium_view.tscn",
	# Screens: Tire Strategy
	"res://ui/screens/strategy/tire_strategy_step1_view.tscn",
	"res://ui/screens/strategy/tire_strategy_step2_view.tscn",
	# Screens: Garage Tabs
	"res://ui/screens/garage/garage_stage_tab.tscn",
	"res://ui/screens/garage/garage_chassis_tab.tscn",
	"res://ui/screens/garage/garage_powertrain_tab.tscn",
	"res://ui/screens/garage/garage_strategy_tab.tscn",
]

const COMPONENT_SCRIPTS: Array[String] = [
	"res://ui/atoms/ui_button.gd",
	"res://ui/atoms/ui_badge.gd",
	"res://ui/atoms/ui_notice_banner.gd",
	"res://ui/atoms/ui_progress_meter.gd",
	"res://ui/atoms/ui_divider.gd",
	"res://ui/atoms/ui_spinner.gd",
	"res://ui/molecules/ui_subviewport_stage.gd",
	"res://ui/organisms/ui_route_preview.gd",
	"res://ui/organisms/ui_telemetry_chart.gd",
	"res://ui/organisms/ui_tire_slot_card.gd",
	"res://ui/organisms/ui_tire_board_3d.gd",
]

const MIGRATED_MENU_SCRIPTS: Array[String] = [
	"res://scripts/rally/rally_loading_overlay.gd",
	"res://scripts/rally/rally_maniac_menu.gd",
	"res://scripts/rally/rally_competition_panel.gd",
	"res://scripts/rally/rally_service_panel.gd",
	"res://scripts/rally/rally_service_workshop.gd",
	"res://scripts/rally/rally_pause_inventory.gd",
	"res://scripts/rally/rally_tire_tuner_panel.gd",
	"res://scripts/rally/rally_tire_strategy_screen.gd",
	"res://scripts/rally/rally_garage_panel.gd",
]

const NO_IMMEDIATE_DRAW_SCRIPTS: Array[String] = [
	"res://scripts/rally/rally_garage_panel.gd",
	"res://scripts/rally/rally_tire_strategy_screen.gd",
]

const JSON_DATA_FILES: Array[String] = [
	"res://data/ui/tokens.json",
	"res://data/ui/component_presets.json",
	"res://data/ui/menus/countries_stages.json",
	"res://data/ui/menus/main_menu.json",
	"res://data/ui/menus/weather_options.json",
	"res://data/ui/menus/garage_layout.json",
	"res://data/ui/menus/service_parts.json",
	"res://data/ui/menus/pause_actions.json",
]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var errors: Array[String] = []

	# 1. Validate all Data-Driven JSON files under res://data/ui/
	for jpath in JSON_DATA_FILES:
		if not FileAccess.file_exists(jpath):
			errors.append("Missing UI JSON file: %s" % jpath)
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(jpath))
		if not (parsed is Dictionary) or (parsed as Dictionary).is_empty():
			errors.append("Invalid or empty UI JSON file: %s" % jpath)

	# 2. Design tokens & font resources
	var colors := UITokenRegistry.list_color_keys()
	if colors.size() < 20:
		errors.append("Expected >= 20 color tokens in tokens.json, got %d" % colors.size())
	var fonts := UITokenRegistry.list_font_keys()
	if fonts.is_empty():
		errors.append("No fonts registered in tokens.json")
	for fk in fonts:
		if UITokenRegistry.get_font(fk) == null:
			errors.append("Missing font resource for token '%s'" % fk)

	# 3. Component presets inheritance & resolution
	var presets := UITokenRegistry.list_preset_ids()
	if presets.is_empty():
		errors.append("No component presets loaded from component_presets.json")
	for pid in presets:
		var resolved := UITokenRegistry.resolve_preset(pid)
		if resolved.is_empty():
			errors.append("Failed to resolve UI preset '%s'" % pid)

	# 4. Declarative menu catalogs & domain services
	for cat_name in ["countries_stages", "main_menu", "weather_options", "garage_layout", "service_parts", "pause_actions"]:
		var doc := MenuCatalogService.load_catalog(cat_name)
		if doc.is_empty():
			errors.append("Failed to load menu JSON catalog '%s'" % cat_name)
	var repair_costs := ServiceRepairCalculator.resolve_service_costs({})
	if int(repair_costs.get("inflate", 0)) <= 0 or ServiceRepairCalculator.get_parts_dict().size() < 9:
		errors.append("ServiceRepairCalculator failed to resolve parts/costs from JSON")
	if TireTunerCatalogService.read_json_dict(TireTunerCatalogService.OFFICIAL_CATALOG_RES).is_empty():
		errors.append("TireTunerCatalogService failed to read official tire catalog")
	if GarageSetupPresenter.get_vehicle_registry_entries().is_empty():
		errors.append("GarageSetupPresenter failed to load vehicle registry entries")

	# 5. StyleBoxFlat & Theme caching
	var sb_a := UITokenRegistry.get_flat_stylebox(UITokenRegistry.get_color("bg_card"), UITokenRegistry.get_color("border_card"), 1, 2, 12, 8)
	var sb_b := UITokenRegistry.get_flat_stylebox(UITokenRegistry.get_color("bg_card"), UITokenRegistry.get_color("border_card"), 1, 2, 12, 8)
	if sb_a != sb_b:
		errors.append("UITokenRegistry.get_flat_stylebox must return cached instance")
	var theme_a := UIThemeBuilder.get_menu_theme()
	var theme_b := UIThemeBuilder.get_menu_theme()
	if theme_a == null or theme_a != theme_b:
		errors.append("UIThemeBuilder.get_menu_theme must build and cache Theme")

	# 6. Static SOLID/DRY architectural guards (ignoring comment lines)
	for mpath in MIGRATED_MENU_SCRIPTS:
		if not FileAccess.file_exists(mpath):
			errors.append("Missing migrated menu script: %s" % mpath)
			continue
		for raw_line in FileAccess.get_file_as_string(mpath).split("\n"):
			var line := raw_line.strip_edges()
			if line.begins_with("#"):
				continue
			if line.contains("StyleBoxFlat.new("):
				errors.append("Forbidden inline StyleBoxFlat.new() in migrated menu script: %s" % mpath)
				break

	for draw_path in NO_IMMEDIATE_DRAW_SCRIPTS:
		var has_draw := false
		var has_hits := false
		for raw_line in FileAccess.get_file_as_string(draw_path).split("\n"):
			var line := raw_line.strip_edges()
			if line.begins_with("#"):
				continue
			if line.contains("func _draw("):
				has_draw = true
			if line.contains("_hit_regions"):
				has_hits = true
		if has_draw:
			errors.append("Forbidden immediate-mode func _draw() in migrated Control screen: %s" % draw_path)
		if has_hits:
			errors.append("Forbidden manual _hit_regions in migrated Control screen: %s" % draw_path)

	# 7. Instantiate all .tscn scenes and .gd components cleanly (zero duplicate/white backdrop regression)
	var sandbox := Control.new()
	root.add_child(sandbox)
	var instantiated_scenes: Array[Dictionary] = []
	for scene_path in COMPONENT_SCENES:
		var packed := load(scene_path) as PackedScene
		if packed == null:
			errors.append("Failed to load UI component scene: %s" % scene_path)
			continue
		var inst := packed.instantiate()
		if inst == null:
			errors.append("Failed to instantiate UI component scene: %s" % scene_path)
			continue
		sandbox.add_child(inst)
		instantiated_scenes.append({"path": scene_path, "node": inst})
	for script_path in COMPONENT_SCRIPTS:
		var scr := load(script_path) as GDScript
		if scr == null:
			errors.append("Failed to load UI component script: %s" % script_path)
			continue
		var inst: Variant = scr.new()
		if inst is Node:
			sandbox.add_child(inst as Node)
	await process_frame
	for entry in instantiated_scenes:
		_assert_no_white_or_duplicate_nodes(entry["node"] as Node, str(entry["path"]), errors)

	# 8. NavigationStack + FocusNavigator contract
	var s1 := UIScreenView.new()
	s1.screen_id = "first"
	var b1 := UIComponentFactory.create_button("A", "button.primary_cta")
	var b2 := UIComponentFactory.create_button("B", "button.secondary_chrome")
	s1.add_child(b1)
	s1.add_child(b2)
	var s2 := UIScreenView.new()
	s2.screen_id = "second"
	var b3 := UIComponentFactory.create_button("C", "button.danger")
	s2.add_child(b3)
	sandbox.add_child(s1)
	sandbox.add_child(s2)
	await process_frame

	UIFocusNavigator.wire_horizontal_cycle([b1, b2])
	if b1.focus_neighbor_right != b1.get_path_to(b2) or b2.focus_neighbor_right != b2.get_path_to(b1):
		errors.append("UIFocusNavigator.wire_horizontal_cycle failed")

	var nav := UINavigationStack.new()
	nav.register_screen("first", s1)
	nav.register_screen("second", s2)
	nav.show_screen("first", {}, false)
	b2.grab_focus()
	await process_frame
	nav.show_screen("second")
	if nav.current_screen_id() != "second" or not s2.visible or s1.visible:
		errors.append("UINavigationStack.show_screen failed transition")
	nav.pop_screen()
	await process_frame
	if nav.current_screen_id() != "first" or not s1.visible or not b2.has_focus():
		errors.append("UINavigationStack.pop_screen failed to restore previous screen and focus")

	sandbox.queue_free()
	await process_frame
	await process_frame

	if errors.is_empty():
		print("PASS: ui_architecture_contract (%d colors, %d fonts, %d presets, %d scenes, %d scripts, %d json_files, %d cached styleboxes)" % [
			colors.size(), fonts.size(), presets.size(), COMPONENT_SCENES.size(), COMPONENT_SCRIPTS.size(), JSON_DATA_FILES.size(), UITokenRegistry.get_stylebox_cache_size()
		])
		quit(0)
	else:
		for e in errors:
			push_error(e)
		print("FAIL: ui_architecture_contract (%d errors)" % errors.size())
		quit(1)


func _assert_no_white_or_duplicate_nodes(node: Node, label: String, errors: Array[String]) -> void:
	for ch in node.get_children():
		if ch is ColorRect:
			var cr := ch as ColorRect
			if cr.color.is_equal_approx(Color.WHITE) and cr.material == null:
				errors.append("Unstyled solid WHITE ColorRect in %s (%s)" % [label, cr.name])
		if ch is Control:
			var ctrl := ch as Control
			if ctrl.has_theme_stylebox_override("panel"):
				var sb := ctrl.get_theme_stylebox("panel")
				if sb is StyleBoxFlat and (sb as StyleBoxFlat).bg_color.is_equal_approx(Color.WHITE):
					errors.append("Solid WHITE Panel StyleBoxFlat in %s (%s)" % [label, ctrl.name])
		_assert_no_white_or_duplicate_nodes(ch, label, errors)
