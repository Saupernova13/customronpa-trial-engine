extends GdUnitTestSuite
## typeSpecific is author-written JSON that no loader parses into typed fields,
## and it used to be read raw. `Dictionary.get(key, default)` returns the
## default only when the key is ABSENT, so a present `"answerKey": null` came
## back as null and `.to_upper()` on it aborted initialize() partway - leaving
## MinigameRunner to call start() on a half-built minigame that could never be
## completed and replayed to the attempt cap.
##
## These pin the drop-and-warn behaviour at each shape the engine reads: a
## wrong-typed scalar takes the default, and a wrong-typed list entry is
## dropped rather than carried to the call that cannot answer it.


func _probe(game_type: String, type_specific: Dictionary) -> MinigameBase:
	var script: GDScript = load(MinigameCatalog.SCRIPTS[game_type])
	var game: MinigameBase = auto_free(script.new())
	game.initialize(MinigameData.from_dict({
		"gameId": "mg_probe",
		"gameType": game_type,
		"typeSpecific": type_specific,
	}))
	return game


# ---------------------------------------------------------------------------
# JsonRead
# ---------------------------------------------------------------------------


func test_a_null_value_takes_the_fallback_rather_than_the_absent_key_rule() -> void:
	# The whole bug in one line: get() with a default cannot tell these apart.
	var present_null := {"k": null}
	assert_object(present_null.get("k", "fallback")).is_null()
	assert_str(JsonRead.str_of(present_null.get("k"), "fallback")).is_equal("fallback")


func test_scalars_of_the_wrong_type_take_the_fallback() -> void:
	assert_str(JsonRead.str_of(7, "d")).is_equal("d")
	assert_str(JsonRead.str_of("kept", "d")).is_equal("kept")
	# "true" is a String, not a bool: coercing it would make an authoring
	# mistake look like a deliberate answer.
	assert_bool(JsonRead.bool_of("true", false)).is_false()
	assert_bool(JsonRead.bool_of(true, false)).is_true()
	assert_int(JsonRead.int_of("3", 9)).is_equal(9)
	assert_int(JsonRead.int_of(3.7, 9)).is_equal(3)
	assert_dict(JsonRead.dict_of("nope")).is_empty()
	assert_array(JsonRead.array_of("nope")).is_empty()


func test_list_entries_of_the_wrong_type_are_dropped_not_carried() -> void:
	var mixed := [{"a": 1}, "junk", 7, {"b": 2}]
	assert_int(JsonRead.dicts_of(mixed).size()).is_equal(2)
	assert_int(JsonRead.strings_of(["a", 1, null, "b"]).size()).is_equal(2)
	# A String is iterable in GDScript, so an un-guarded list read walked it
	# character by character instead of failing.
	assert_array(JsonRead.strings_of("abc")).is_empty()
	assert_array(JsonRead.dicts_of(null)).is_empty()


# ---------------------------------------------------------------------------
# The sites the issue verified
# ---------------------------------------------------------------------------


func test_a_null_answer_key_leaves_hangmans_gambit_fully_initialised() -> void:
	# `answerKey: null` aborted initialize() at line 1 of 6: _revealed_letters
	# was never sized and _spawn_interval kept its declared default, so the
	# minigame started with no answer slots and spawned nothing.
	var game := _probe("hangmans_gambit", {"answerKey": null})
	assert_str(game.answer_key).is_empty()
	assert_array(game._revealed_letters).is_empty()
	# Reached only if initialize() ran to the end.
	assert_float(game._spawn_interval).is_equal(
		MinigameConfig.get_spawn_interval("hangmans_gambit", game.difficulty)
	)
	assert_array(game.validate_data()).is_not_empty()


func test_a_string_argument_list_does_not_reach_debate_scrums_element_reads() -> void:
	var game := _probe("debate_scrum", {"arguments": "not a list"})
	assert_array(game.arguments).is_empty()


func test_debate_scrum_drops_non_object_arguments_and_non_string_keywords() -> void:
	var game := _probe("debate_scrum", {
		"arguments": [
			"junk",
			{"defenseKeywords": ["real", 7, null]},
		],
	})
	assert_int(game.arguments.size()).is_equal(1)
	# One survivor keeps the round winnable; validate_data must not report it.
	assert_array(game.validate_data()).is_empty()
	assert_array(game._keywords_of(game.arguments[0], "defenseKeywords")).contains_exactly(["real"])


func test_a_scrum_round_whose_keywords_are_all_non_strings_is_reported() -> void:
	var game := _probe("debate_scrum", {"arguments": [{"defenseKeywords": [1, 2]}]})
	assert_array(game.validate_data()).is_not_empty()


func test_a_string_is_correct_is_reported_as_an_unwinnable_logic_dive_question() -> void:
	# It used to pass validation as truthy, then fail the bool bind when the
	# player clicked - mid-play, after the question was already on screen.
	var game := _probe("logic_dive", {
		"questions": [
			{
				"questionId": "q1",
				"answers": [
					{"answerId": "a1", "answerText": "One", "isCorrect": "true"},
					{"answerId": "a2", "answerText": "Two", "isCorrect": false},
				],
			}
		],
	})
	var errors := game.validate_data()
	assert_array(errors).is_not_empty()
	assert_str(errors[0]).contains("no correct answer")


func test_logic_dive_drops_a_non_object_question_instead_of_refusing_the_round() -> void:
	# The survivor is winnable, so the round plays with one question fewer
	# rather than failing validation and replaying to the attempt cap.
	var game := _probe("logic_dive", {
		"questions": [
			"junk",
			{
				"questionId": "q1",
				"answers": [
					{"answerId": "a1", "answerText": "One", "isCorrect": true},
					{"answerId": "a2", "answerText": "Two", "isCorrect": false},
				],
			},
		],
	})
	assert_int(game.questions.size()).is_equal(1)
	assert_array(game.validate_data()).is_empty()


func test_logic_dive_drops_non_object_answers() -> void:
	var game := _probe("logic_dive", {
		"questions": [
			{
				"questionId": "q1",
				"answers": [
					"junk",
					{"answerId": "a1", "answerText": "One", "isCorrect": true},
				],
			}
		],
	})
	assert_int(game._answers_of(game.questions[0]).size()).is_equal(1)
	assert_array(game.validate_data()).is_empty()


func test_mass_panic_speaker_ids_are_strings_even_when_authored_null() -> void:
	# speaker_ids[i] is written straight into the panel's line data and then
	# read back as a String; a null aborted _spawn_group() mid-loop, so
	# speakers 2 and 3 never spawned.
	var game := _probe("mass_panic_debate", {
		"lineGroups": [{"groupId": "g1"}],
		"speaker1CharacterId": null,
		"speaker2CharacterId": 7,
		"speaker3CharacterId": "char_c",
	})
	assert_array(game.speaker_ids).contains_exactly(["", "", "char_c"])


func test_a_string_line_group_is_dropped_before_it_reaches_group_get() -> void:
	var game := _probe("mass_panic_debate", {"lineGroups": ["junk"]})
	assert_array(game.line_groups).is_empty()
	assert_array(game.validate_data()).is_not_empty()


func test_nonstop_debate_keeps_only_object_lines_and_string_bullet_ids() -> void:
	var game := _probe("nonstop_debate", {
		"dialogueLines": [{"target": "you"}, "junk"],
		"selectedBullets": ["tb_1", 7, null],
	})
	assert_int(game.dialogue_lines.size()).is_equal(1)
	assert_array(game.selected_bullets).contains_exactly(["tb_1"])


# ---------------------------------------------------------------------------
# DebateTextPanel
# ---------------------------------------------------------------------------


func test_a_wrong_typed_panel_field_no_longer_aborts_apply_setup() -> void:
	# A number passed the old `!= null` guard and then failed the typed assign,
	# aborting _apply_setup() partway: the panel scrolled blank but still
	# answered check_hit(), so a shot was scored against a bullet id that had
	# never been set.
	var panel: DebateTextPanel = auto_free(ResourceRegistry.instantiate("debate_text_panel"))
	# setup() before add_child, as both production callers do.
	panel.setup({
		"answerBulletId": 7,
		"isShootable": "yes",
		"textMovementDirection": null,
		"characterId": null,
		"textEffect": 3,
		"sentenceBeginning": 12,
	})
	add_child(panel)
	await await_idle_frame()
	assert_str(panel.answer_bullet_id).is_empty()
	assert_bool(panel.is_shootable).is_false()
	assert_str(panel.movement_direction).is_equal("left_to_right")
	assert_str(panel.character_id).is_empty()
	assert_str(panel.text_effect).is_equal("normal")
