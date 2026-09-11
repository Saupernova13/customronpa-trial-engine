extends GdUnitTestSuite
## Empty authored data must be reported and skipped, never played. Four
## minigames spin on it: nothing spawns, nothing can be hit, the timer expires
## and the attempt replays identically.

## Builds an initialised instance the way MinigameCatalog's probe does. Nothing
## is added to the tree and start() is never called, so validate_data() sees
## exactly what the runner sees.
func _probe(game_type: String, type_specific: Dictionary) -> MinigameBase:
	var script: GDScript = load(MinigameCatalog.SCRIPTS[game_type])
	var game: MinigameBase = auto_free(script.new())
	game.initialize(MinigameData.from_dict({
		"gameType": game_type,
		"typeSpecific": type_specific,
	}))
	return game


func test_empty_data_is_rejected_for_every_minigame_that_spins_on_it() -> void:
	# Keyed by the field the editor writes, so a rename here fails loudly.
	var empty_cases := {
		"nonstop_debate": {"dialogueLines": []},
		"logic_dive": {"questions": []},
		"mass_panic_debate": {"lineGroups": []},
		"hangmans_gambit": {"answerKey": ""},
	}
	for game_type in empty_cases:
		var errors: Array[String] = _probe(game_type, empty_cases[game_type]).validate_data()
		assert_array(errors).override_failure_message(
			"%s accepted empty data" % game_type
		).is_not_empty()


func test_populated_data_is_accepted() -> void:
	var valid_cases := {
		"nonstop_debate": {"dialogueLines": [{"text": "It was you."}]},
		"logic_dive": {
			"questions": [
				{
					"questionId": "q1",
					"questionText": "Who?",
					"answers": [
						{"answerId": "a1", "answerText": "You", "isCorrect": true},
						{"answerId": "a2", "answerText": "Me", "isCorrect": false},
					],
				}
			]
		},
		"mass_panic_debate": {"lineGroups": [{"groupId": "g1"}]},
		"hangmans_gambit": {"answerKey": "KNIFE"},
	}
	for game_type in valid_cases:
		var errors: Array[String] = _probe(game_type, valid_cases[game_type]).validate_data()
		assert_array(errors).override_failure_message(
			"%s rejected valid data: %s" % [game_type, errors]
		).is_empty()


func test_a_whitespace_only_answer_key_is_rejected() -> void:
	# Every slot starts revealed, so _check_complete() is never reached and the
	# only way out is influence depletion.
	var errors: Array[String] = _probe("hangmans_gambit", {"answerKey": "   "}).validate_data()
	assert_array(errors).is_not_empty()


func test_minigames_without_required_data_validate_clean() -> void:
	# The stubs and the games that carry no authored payload must not be
	# skipped by a hook they do not override.
	for game_type in ["rebuttal_showdown", "psyche_taxi", "closing_argument", "debate_scrum"]:
		var errors: Array[String] = _probe(game_type, {}).validate_data()
		assert_array(errors).override_failure_message(
			"%s reported %s" % [game_type, errors]
		).is_empty()


func test_a_debate_whose_evidence_does_not_resolve_is_rejected() -> void:
	# Not the same as an empty selection, which means "all bullets": here the
	# author named ids that no longer exist, so every weak-point shot is a miss
	# and the attempt ends on the player's first correct-looking one.
	var errors: Array[String] = _probe("nonstop_debate", {
		"dialogueLines": [{"text": "It was you."}],
		"selectedBullets": ["tb_deleted_by_the_author"],
	}).validate_data()
	assert_array(errors).is_not_empty()


func test_an_empty_bullet_selection_is_accepted() -> void:
	var errors: Array[String] = _probe("nonstop_debate", {
		"dialogueLines": [{"text": "It was you."}],
		"selectedBullets": [],
	}).validate_data()
	assert_array(errors).is_empty()


func test_a_scrum_round_with_no_defense_keywords_is_rejected() -> void:
	# Every button is marked wrong, so the round can never be won - and
	# _finish(false) then replays it, identically, forever.
	var errors: Array[String] = _probe("debate_scrum", {
		"arguments": [
			{"argumentId": "a1", "defenseKeywords": ["knife"], "oppositionKeywords": []},
			{"argumentId": "a2", "defenseKeywords": [], "oppositionKeywords": ["rope"]},
		],
	}).validate_data()
	assert_array(errors).has_size(1)
	assert_str(errors[0]).contains("argument 2")


func test_a_scrum_round_with_defense_keywords_is_accepted() -> void:
	var errors: Array[String] = _probe("debate_scrum", {
		"arguments": [{"argumentId": "a1", "defenseKeywords": ["knife"]}],
	}).validate_data()
	assert_array(errors).is_empty()


func test_a_logic_dive_question_with_no_correct_answer_is_rejected() -> void:
	var errors: Array[String] = _probe("logic_dive", {
		"questions": [
			{
				"questionId": "q1",
				"answers": [
					{"answerId": "a1", "answerText": "One", "isCorrect": false},
					{"answerId": "a2", "answerText": "Two", "isCorrect": false},
				],
			}
		],
	}).validate_data()
	assert_array(errors).has_size(1)
	assert_str(errors[0]).contains("no correct answer")


func test_a_logic_dive_question_of_nothing_but_blanks_is_rejected() -> void:
	# _show_question filters out blank answerText, so this leaves zero buttons.
	var errors: Array[String] = _probe("logic_dive", {
		"questions": [
			{
				"questionId": "q1",
				"answers": [
					{"answerId": "a1", "answerText": "   ", "isCorrect": true},
					{"answerId": "a2", "answerText": "", "isCorrect": false},
				],
			}
		],
	}).validate_data()
	assert_array(errors).has_size(1)
	assert_str(errors[0]).contains("no answers with any text")


func test_a_well_formed_logic_dive_question_is_accepted() -> void:
	var errors: Array[String] = _probe("logic_dive", {
		"questions": [
			{
				"questionId": "q1",
				"answers": [
					{"answerId": "a1", "answerText": "One", "isCorrect": true},
					{"answerId": "a2", "answerText": "Two", "isCorrect": false},
				],
			}
		],
	}).validate_data()
	assert_array(errors).is_empty()


func test_a_scrum_round_seats_every_correct_answer_before_any_decoy() -> void:
	# Concatenating both lists, shuffling, then taking the first five discarded
	# entries at random - and any of them could be a correct one. Three defense
	# and four opposition keywords is seven candidates for five buttons, and
	# some shuffles hid every correct answer.
	var scrum: MinigameBase = _probe("debate_scrum", {})
	scrum._defense_buttons.resize(5)

	# Typed, because _deal_keywords takes Array[String] - it is fed from
	# JsonRead.strings_of, so a raw JSON list never reaches it untyped.
	var defense: Array[String] = ["d1", "d2", "d3"]
	var opposition: Array[String] = ["o1", "o2", "o3", "o4"]
	for _attempt in range(50):
		var dealt: Array = scrum._deal_keywords(defense, opposition)
		assert_int(dealt.size()).is_equal(5)
		for correct in defense:
			assert_bool(dealt.has(correct)).override_failure_message(
				"deal dropped the correct answer '%s': %s" % [correct, dealt]
			).is_true()


func test_a_scrum_round_fills_the_remaining_buttons_with_decoys() -> void:
	var scrum: MinigameBase = _probe("debate_scrum", {})
	scrum._defense_buttons.resize(5)

	var opposition: Array[String] = ["o1", "o2", "o3", "o4", "o5", "o6"]
	var dealt: Array = scrum._deal_keywords(["d1"] as Array[String], opposition)
	assert_int(dealt.size()).is_equal(5)
	assert_bool(dealt.has("d1")).is_true()


func test_a_scrum_round_with_few_keywords_deals_only_what_it_has() -> void:
	var scrum: MinigameBase = _probe("debate_scrum", {})
	scrum._defense_buttons.resize(5)

	var dealt: Array = scrum._deal_keywords(["d1"] as Array[String], ["o1"] as Array[String])
	assert_array(dealt).contains_exactly_in_any_order(["d1", "o1"])


func test_a_scrum_round_does_not_deal_a_keyword_twice() -> void:
	# A keyword on both lists is one button, and it is a correct one.
	var scrum: MinigameBase = _probe("debate_scrum", {})
	scrum._defense_buttons.resize(5)

	var dealt: Array = scrum._deal_keywords(
		["shared"] as Array[String], ["shared", "o1"] as Array[String]
	)
	assert_array(dealt).contains_exactly_in_any_order(["shared", "o1"])
