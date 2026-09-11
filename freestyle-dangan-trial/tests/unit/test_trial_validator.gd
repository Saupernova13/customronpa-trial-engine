extends GdUnitTestSuite
## Engine half of the trial.json contract tests. These are hand-written cases
## against the fixture, not a schema check: the only artifact shared with the
## editor's suite is the fixture file itself. The one assertion that genuinely
## ties the two together is the gameType enum check in test_trial_manifest.gd.

const FIXTURE_PATH := "res://tests/fixtures/minimal-trial/trial.json"


func _load_fixture() -> Dictionary:
	var text := FileAccess.get_file_as_string(FIXTURE_PATH)
	assert_str(text).is_not_empty()
	var json := JSON.new()
	assert_int(json.parse(text)).is_equal(OK)
	return json.data


func test_fixture_passes_validation() -> void:
	var data := _load_fixture()
	assert_str(TrialValidator.check_version(data)).is_empty()
	assert_array(TrialValidator.validate(data)).is_empty()


func test_missing_script_lines_fails() -> void:
	var data := _load_fixture()
	data.erase("script")
	assert_array(TrialValidator.validate(data)).is_not_empty()


func test_minigame_line_without_id_fails() -> void:
	var data := _load_fixture()
	data["script"]["lines"].append({"id": "line_bad", "type": "minigame"})
	assert_array(TrialValidator.validate(data)).is_not_empty()


func test_minigame_entry_without_game_type_fails() -> void:
	var data := _load_fixture()
	data["minigames"].append({"gameId": "mg_broken"})
	assert_array(TrialValidator.validate(data)).is_not_empty()


func test_non_array_truth_bullets_fails() -> void:
	var data := _load_fixture()
	data["truthBullets"] = {"not": "an array"}
	assert_array(TrialValidator.validate(data)).is_not_empty()


func test_unknown_line_type_warns_but_passes() -> void:
	var data := _load_fixture()
	data["script"]["lines"].append({"id": "line_future", "type": "hologram"})
	assert_array(TrialValidator.validate(data)).is_empty()


## The line-type strings used to be spelled out independently in ScriptLine,
## ScriptDirector's dispatch table and here. These pin all three to one source,
## so a renamed constant fails CI instead of silently unhooking the dispatch.
func test_validator_line_types_come_from_script_line() -> void:
	assert_array(TrialValidator.LINE_TYPES).is_equal(ScriptLine.TYPES)


func test_script_line_types_list_is_complete() -> void:
	assert_array(ScriptLine.TYPES).contains_exactly_in_any_order(
		[ScriptLine.TYPE_SPEAKING, ScriptLine.TYPE_NARRATOR, ScriptLine.TYPE_MINIGAME]
	)


func test_director_dispatch_is_keyed_on_the_constants() -> void:
	var director := get_node("/root/ScriptDirector")
	assert_object(director).is_not_null()
	assert_array(director._line_handlers.keys()).contains_exactly_in_any_order(ScriptLine.TYPES)


func test_an_unknown_game_type_still_loads() -> void:
	# A warning, not an error: check_version deliberately accepts a newer minor
	# that might carry a type this build has no script for, and the runner now
	# tells the player and skips rather than reporting it as a win.
	var errors := TrialValidator.validate({
		"trialName": "T",
		"characters": [],
		"script": {"lines": []},
		"minigames": [{"gameId": "mg_1", "gameType": "quantum_debate"}],
	})
	assert_array(errors).is_empty()


func test_a_known_game_type_is_one_the_engine_can_actually_run() -> void:
	# MinigameCatalog is the normative list, and the schema's enum is pinned to
	# it by test_trial_manifest.gd - so the validator agreeing with the catalog
	# is what makes the three sources one.
	for game_type in MinigameCatalog.SCRIPTS:
		var errors := TrialValidator.validate({
			"trialName": "T",
			"characters": [],
			"script": {"lines": []},
			"minigames": [{"gameId": "mg_1", "gameType": game_type}],
		})
		assert_array(errors).override_failure_message(
			"%s was rejected: %s" % [game_type, errors]
		).is_empty()


func _trial(overrides: Dictionary) -> Dictionary:
	var base := {"trialName": "T", "characters": [], "script": {"lines": []}}
	base.merge(overrides, true)
	return base


func test_every_malformed_minigame_is_reported_not_just_the_first() -> void:
	# The old `break` meant an author with five bad entries fixed them one
	# reload at a time, and the message named neither index nor gameId.
	var errors := TrialValidator.validate(_trial({
		"minigames": [
			{"gameId": "mg_1", "gameType": "nonstop_debate"},
			{"gameType": "nonstop_debate"},
			{"gameId": "mg_3"},
			"not an object",
		],
	}))
	assert_array(errors).has_size(3)


func test_a_malformed_minigame_message_names_which_one() -> void:
	var errors := TrialValidator.validate(_trial({
		"minigames": [{"gameId": "mg_1", "gameType": "nonstop_debate"}, {"gameId": "mg_2"}],
	}))
	assert_str(errors[0]).contains("mg_2")


func test_a_dangling_reference_warns_rather_than_rejecting_the_trial() -> void:
	# Any error rejects the whole file, and a dangling reference degrades one
	# line rather than making the trial unplayable - so failing on it would
	# lock the author out of the editor's own broken output.
	var errors := TrialValidator.validate(_trial({
		"script": {"lines": [{"id": "l1", "type": "minigame", "minigameId": "mg_gone"}]},
		"minigames": [],
	}))
	assert_array(errors).is_empty()


## The three tests that used to call TrialValidator._dangling_references()
## directly now live in test_validation_rules.gd, against the rule itself, and
## in test_validation_report.gd, against the composite's report. Reaching for a
## private static was the only way to see those findings at all.


## check_version's edges. The policy is deliberately lax - an unrecognised
## version warns and loads - so these pin which inputs take which branch
## rather than asserting that any of them fail.
