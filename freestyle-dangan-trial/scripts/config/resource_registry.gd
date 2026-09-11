class_name ResourceRegistry
extends RefCounted
## Scene paths with lazy load caching, for scenes the game instantiates at
## runtime: UI, minigame overlays, effects and per-item pieces.
##
## It used to claim that every "res://" lives here. Twenty did not, across
## eight files, and stating an invariant falsely is worse than not stating it -
## it is the reason a reviewer would skip grepping for stray paths after a
## rename. The real scope, and what deliberately sits outside it:
##
## - **Scene transitions** (`change_scene_to_file`) name their target inline.
##   They are control flow, not instantiation, and nothing caches them.
## - **Script preloads** - `MinigameCatalog.SCRIPTS`, `trial_file_picker.gd`,
##   `dialogue_box.gd`. The catalog especially is normative on purpose:
##   `TrialValidator` checks gameType against it and test_trial_manifest pins
##   it to the schema's enum, so it has to stay one table keyed by gameType
##   rather than becoming scene keys here.
## - **Data and shaders** - `data/*.json`, `shaders/*.gdshader`.
## - **Two title-card textures**, loaded on demand for the one hardcoded
##   orange-frame case (`minigame_title_card.gd`). These are the arguable ones;
##   see #115, which covers that special case.
##
## So: a scene rename touches this file. Any other kind of rename does not, and
## still wants a grep.

const SCENES := {
	# Minigame overlays
	"break_shatter": "res://scenes/minigames/break_shatter.tscn",
	"debate_ambience": "res://scenes/minigames/debate_ambience.tscn",
	"slow_time_vignette": "res://scenes/minigames/slow_time_vignette.tscn",
	"nonstop_debate_overlay": "res://scenes/minigames/nonstop_debate_overlay.tscn",
	"debate_scrum_overlay": "res://scenes/minigames/debate_scrum_overlay.tscn",
	"hangmans_gambit_overlay": "res://scenes/minigames/hangmans_gambit_overlay.tscn",
	"logic_dive_overlay": "res://scenes/minigames/logic_dive_overlay.tscn",
	"mass_panic_debate_overlay": "res://scenes/minigames/mass_panic_debate_overlay.tscn",
	"stub_minigame_overlay": "res://scenes/minigames/stub_minigame_overlay.tscn",

	# Minigame pieces
	"debate_text_panel": "res://scenes/minigames/debate_text_panel.tscn",
	"bullet_projectile": "res://scenes/minigames/bullet_projectile.tscn",
	"hangman_slot": "res://scenes/minigames/hangman_slot.tscn",
	"floating_letter": "res://scenes/minigames/floating_letter.tscn",
	"lane_button": "res://scenes/minigames/lane_button.tscn",
	"bullet_preview": "res://scenes/minigames/bullet_preview.tscn",
	"bullet_preview_cell": "res://scenes/minigames/bullet_preview_cell.tscn",
	"evidence_card": "res://scenes/minigames/evidence_card.tscn",

	# Spawnable VFX
	"drift_popup": "res://scenes/effects/drift_popup.tscn",
	"shard_burst": "res://scenes/effects/shard_burst.tscn",
	"panel_shatter": "res://scenes/effects/panel_shatter.tscn",

	# Shared HUD / UI
	"influence_gauge": "res://scenes/ui/influence_gauge.tscn",
	"concentrate_gauge": "res://scenes/ui/concentrate_gauge.tscn",
	"timer_display": "res://scenes/ui/timer_display.tscn",
	"crosshair": "res://scenes/ui/crosshair.tscn",
	"truth_bullet_selector": "res://scenes/ui/truth_bullet_selector.tscn",
	"settings_menu": "res://scenes/ui/settings_menu.tscn",
	"mobile_hud": "res://scenes/ui/mobile_hud.tscn",
	"mobile_toast": "res://scenes/ui/mobile_toast.tscn",
	"screen_effects_overlay": "res://scenes/ui/screen_effects_overlay.tscn",
	"trial_file_list": "res://scenes/ui/trial_file_list.tscn",
	"trial_file_row": "res://scenes/ui/trial_file_row.tscn",
	"game_over_screen": "res://scenes/ui/game_over_screen.tscn",
	"roaming_char": "res://scenes/ui/roaming_char.tscn",
	"minigame_title_card": "res://scenes/ui/minigame_title_card.tscn",
	"minigame_result_card": "res://scenes/ui/minigame_result_card.tscn",
}

static var _cache: Dictionary = {}

static func get_scene(key: String) -> PackedScene:
	if not SCENES.has(key):
		push_error("ResourceRegistry: unknown scene key '%s'" % key)
		return null
	if _cache.has(key):
		return _cache[key]
	var scene: PackedScene = load(SCENES[key])
	if scene == null:
		push_error("ResourceRegistry: failed to load '%s' from %s" % [key, SCENES[key]])
		return null
	_cache[key] = scene
	return scene

static func instantiate(key: String) -> Node:
	var scene := get_scene(key)
	if scene == null:
		return null
	return scene.instantiate()
