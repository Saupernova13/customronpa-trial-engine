extends GdUnitTestSuite
## The gameType registry is the data layer's, not the scene layer's.
##
## It used to live on MinigameRunner - a Node that instantiates overlays and
## drives ScriptDirector - while TrialValidator, a RefCounted that runs during
## parsing before any scene exists, reached up into it. These assertions pin
## the direction of that dependency, because nothing else would notice it
## being reintroduced.


func test_the_catalog_knows_the_types_it_can_build() -> void:
	assert_bool(MinigameCatalog.has_type("nonstop_debate")).is_true()
	assert_bool(MinigameCatalog.has_type("no_such_minigame")).is_false()


func test_every_registered_type_builds_a_minigame_base() -> void:
	for game_type in MinigameCatalog.SCRIPTS:
		var game: MinigameBase = MinigameCatalog.create(game_type)
		assert_object(game).override_failure_message(
			"%s did not build a MinigameBase" % game_type
		).is_not_null()
		game.free()


func test_an_unregistered_type_builds_nothing() -> void:
	# The caller recovers from null; it must not get a half-built Node.
	assert_object(MinigameCatalog.create("no_such_minigame")).is_null()


func test_validation_errors_reports_what_the_minigame_reports() -> void:
	var empty := MinigameData.from_dict({
		"gameType": "nonstop_debate",
		"typeSpecific": {"dialogueLines": []},
	})
	assert_array(MinigameCatalog.validation_errors(empty)).is_not_empty()

	var populated := MinigameData.from_dict({
		"gameType": "nonstop_debate",
		"typeSpecific": {"dialogueLines": [{"text": "It was you."}]},
	})
	assert_array(MinigameCatalog.validation_errors(populated)).is_empty()


## Structural, not behavioural, and deliberately so: gdUnit4's memory observer
## guards every instance created during a test and reclaims it at teardown, so
## a probe the catalog failed to free is collected by the framework and the
## suite still reports zero orphans. A leak cannot be observed from inside a
## test here. What can be pinned is that only one place builds a probe, and
## that it frees it in the same function - which is the actual claim.
func test_only_the_catalog_builds_a_probe_and_it_frees_it_there() -> void:
	var catalog := FileAccess.get_file_as_string(
		"res://scripts/core/trial/minigame_catalog.gd"
	)
	assert_str(catalog).is_not_empty()
	assert_str(catalog).contains("probe.free()")

	# When create-and-free was the caller's to pair up, an early return added
	# between them leaked one MinigameBase per minigame line, silently.
	var runner := FileAccess.get_file_as_string("res://scripts/game/minigame_runner.gd")
	assert_str(runner).is_not_empty()
	assert_bool(runner.contains("validate_data()")).override_failure_message(
		"minigame_runner.gd builds its own probe again"
	).is_false()


func test_validation_errors_on_an_unregistered_type_is_not_an_error() -> void:
	# An unsupported type is reported by the runner's own unsupported path, not
	# as an authoring error - so this must stay empty rather than inventing one.
	var data := MinigameData.from_dict({"gameType": "no_such_minigame"})
	assert_array(MinigameCatalog.validation_errors(data)).is_empty()


func test_the_validator_does_not_depend_on_the_scene_layer() -> void:
	# TrialValidator runs during TrialLoader._parse_manifest(), before any
	# scene exists. Naming MinigameRunner there makes a RefCounted in
	# core/trial/ resolve a Node class that pulls in overlays, the HUD and
	# ScriptDirector - and it is why validation could not be tested alone.
	var source := FileAccess.get_file_as_string(
		"res://scripts/core/trial/trial_validator.gd"
	)
	assert_str(source).is_not_empty()
	assert_bool(source.contains("MinigameRunner")).override_failure_message(
		"trial_validator.gd reaches into the scene layer again"
	).is_false()
