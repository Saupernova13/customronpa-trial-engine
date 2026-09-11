extends GdUnitTestSuite
## Which findings are fatal and which are advisory.
##
## Severity used to be a property of the consumer, not the finding: a check
## either appended to a local `errors` array that TrialValidator returned, or
## called push_warning directly, and _dangling_references did both - it
## collected into an array named `errors` which the caller then downgraded to
## warnings one by one. Nothing could ask for the warnings, and no test could
## assert on them without scraping engine output.
##
## These pin the split itself. The exact-list assertions are characterisation:
## they were written against the pre-refactor validator and must keep passing.

func _trial(overrides: Dictionary) -> Dictionary:
	var base := {"trialName": "T", "characters": [], "script": {"lines": []}}
	base.merge(overrides, true)
	return base


# ---------------------------------------------------------------------------
# Characterisation: the exact errors, unchanged across the refactor.
# ---------------------------------------------------------------------------
func test_a_trial_missing_its_top_level_fields_reports_all_three() -> void:
	var errors := TrialValidator.validate({})
	assert_array(errors).contains_exactly_in_any_order([
		"trialName is missing or not a string",
		"characters is missing or not an array",
		"script.lines is missing or not an array",
	])


func test_malformed_minigames_are_reported_by_index_and_id() -> void:
	var errors := TrialValidator.validate(_trial({
		"minigames": [
			{"gameId": "mg_1", "gameType": "nonstop_debate"},
			{"gameType": "nonstop_debate"},
			{"gameId": "mg_3"},
			"not an object",
		],
	}))
	assert_array(errors).contains_exactly_in_any_order([
		"minigame 2 has no gameId",
		"minigame 3 (mg_3) has no gameType",
		"minigame 4 is not an object",
	])


func test_a_minigame_line_without_an_id_is_fatal() -> void:
	var errors := TrialValidator.validate(_trial({
		"script": {"lines": [{"id": "l1", "type": "minigame"}]},
	}))
	assert_array(errors).contains_exactly_in_any_order([
		"script line 1: minigame line has no minigameId",
	])


func test_a_non_array_truth_bullets_is_fatal() -> void:
	var errors := TrialValidator.validate(_trial({"truthBullets": {"not": "an array"}}))
	assert_array(errors).contains_exactly_in_any_order(["truthBullets is not an array"])


# ---------------------------------------------------------------------------
# The warnings, which nothing could reach before.
# ---------------------------------------------------------------------------
func test_an_unknown_line_type_warns_and_does_not_reject_the_trial() -> void:
	var report := TrialValidator.report(_trial({
		"script": {"lines": [{"id": "l1", "type": "hologram"}]},
	}))
	assert_array(report.errors).is_empty()
	assert_array(report.warnings).has_size(1)
	assert_str(report.warnings[0]).contains("hologram")


func test_an_unplayable_game_type_warns_once_for_the_whole_trial() -> void:
	# One message per run, not one per entry: a trial from a newer minor could
	# carry dozens, and push_warning is expensive.
	var report := TrialValidator.report(_trial({
		"minigames": [
			{"gameId": "mg_1", "gameType": "quantum_debate"},
			{"gameId": "mg_2", "gameType": "quantum_debate"},
			{"gameId": "mg_3", "gameType": "temporal_scrum"},
		],
	}))
	assert_array(report.errors).is_empty()
	var unplayable := report.warnings.filter(func(w: String) -> bool:
		return w.contains("cannot play")
	)
	assert_array(unplayable).has_size(1)
	assert_str(unplayable[0]).contains("quantum_debate")
	assert_str(unplayable[0]).contains("temporal_scrum")


func test_a_malformed_truth_bullet_warns_rather_than_rejecting() -> void:
	# An array of strings used to pass here, pass TrialManifest.from_dict, and
	# reach a Dictionary-typed signal that silently dropped it.
	var report := TrialValidator.report(_trial({
		"truthBullets": ["not an object", {"name": "no id"}],
	}))
	assert_array(report.errors).is_empty()
	assert_array(report.warnings).has_size(2)


func test_every_dangling_reference_warns_and_none_of_them_are_fatal() -> void:
	# Any error rejects the whole file, and a dangling reference degrades one
	# line rather than making the trial unplayable - so failing on one would
	# lock the author out of the editor's own broken output.
	var report := TrialValidator.report(_trial({
		"characters": ["CH_1"],
		"truthBullets": [{"bulletId": "tb_1"}],
		"script": {
			"lines": [
				{"id": "l1", "type": "minigame", "minigameId": "mg_gone"},
				{"id": "l2", "type": "speaking", "characterId": "CH_GONE", "dialogue": "x"},
				{"id": "l3", "type": "speaking", "characterId": "CH_1", "dialogue": "y"},
			]
		},
		"minigames": [
			{
				"gameId": "mg_1",
				"gameType": "nonstop_debate",
				"typeSpecific": {
					"selectedBullets": ["tb_1", "tb_gone"],
					"dialogueLines": [{"lineId": "dl1", "answerBulletId": "tb_also_gone"}],
				},
			}
		],
	}))
	assert_array(report.errors).is_empty()
	# A missing minigame, a missing character, a missing selected bullet and a
	# missing answer bullet - all found in one pass, so an author fixes them
	# together instead of one reload at a time.
	assert_array(report.warnings).has_size(4)


func test_a_coherent_trial_reports_nothing_at_either_severity() -> void:
	var report := TrialValidator.report(_trial({
		"characters": ["CH_1"],
		"truthBullets": [{"bulletId": "tb_1"}],
		"script": {"lines": [{"id": "l1", "type": "speaking", "characterId": "CH_1"}]},
		"minigames": [
			{
				"gameId": "mg_1",
				"gameType": "nonstop_debate",
				"typeSpecific": {
					"selectedBullets": ["tb_1"],
					"dialogueLines": [{"lineId": "dl1", "answerBulletId": "tb_1"}],
				},
			}
		],
	}))
	assert_array(report.errors).is_empty()
	assert_array(report.warnings).is_empty()


func test_an_empty_character_id_is_unset_rather_than_dangling() -> void:
	# The editor writes "" for a speaking line with no character chosen.
	var report := TrialValidator.report(_trial({
		"script": {"lines": [{"id": "l1", "type": "speaking", "characterId": ""}]},
	}))
	assert_array(report.warnings).is_empty()


func test_validate_returns_exactly_the_reports_errors() -> void:
	# The two entry points must not be able to disagree.
	var data := _trial({
		"minigames": [{"gameId": "mg_1"}],
		"script": {"lines": [{"id": "l1", "type": "hologram"}]},
	})
	assert_array(TrialValidator.validate(data)).is_equal(TrialValidator.report(data).errors)
