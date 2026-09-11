extends GdUnitTestSuite
## White noise is parked pending a positioning rework, and the parking was
## documented on _split_dialogue_lines only. The flag itself was left intact
## on every line, so DebateTextPanel could still be handed isWhiteNoise: true
## - which makes get_hit_zone() return "white_noise" for the panel's whole
## body, so its weak point can never be exposed.
##
## A statement authored as white noise was therefore unshootable. Only a
## hand-edited or third-party trial.json can produce one today, because the
## editor never writes the field.


func _debate(lines: Array) -> MinigameBase:
	var script: GDScript = load(MinigameCatalog.SCRIPTS["nonstop_debate"])
	var game: MinigameBase = auto_free(script.new())
	game.initialize(MinigameData.from_dict({
		"gameId": "mg_nd",
		"gameType": "nonstop_debate",
		"typeSpecific": {"dialogueLines": lines},
	}))
	return game


func test_every_line_still_spawns_as_a_main_line() -> void:
	var game := _debate([
		{"target": "you", "isWhiteNoise": true},
		{"target": "me"},
	])
	assert_int(game._main_lines.size()).is_equal(2)
	assert_array(game._white_noise_lines).is_empty()


func test_the_flag_is_stripped_so_the_panel_cannot_act_on_it() -> void:
	var game := _debate([{"target": "you", "isWhiteNoise": true}])
	assert_bool(game._main_lines[0].get("isWhiteNoise")).is_false()


func test_stripping_does_not_write_back_into_the_trial_data() -> void:
	# type_specific is shared with TrialManifest; editing it in place would
	# change what a later reader sees.
	var game := _debate([{"target": "you", "isWhiteNoise": true}])
	assert_bool(game.dialogue_lines[0].get("isWhiteNoise")).is_true()


func test_a_white_noise_line_keeps_its_weak_point_shootable() -> void:
	# The behaviour the strip protects: with the flag through, get_hit_zone
	# answers "white_noise" for the entire panel and the weak point is
	# unreachable.
	var panel: DebateTextPanel = auto_free(ResourceRegistry.instantiate("debate_text_panel"))
	panel.setup({
		"sentenceBeginning": "It was",
		"target": "you",
		"sentenceEnd": "all along",
		"isShootable": true,
		"isWhiteNoise": true,
	})
	add_child(panel)
	await await_idle_frame()
	assert_bool(panel.is_white_noise).override_failure_message(
		"the panel honours isWhiteNoise, so nonstop_debate must keep stripping it"
	).is_true()

	var game := _debate([{"target": "you", "isWhiteNoise": true, "isShootable": true}])
	assert_bool(JsonRead.bool_of(game._main_lines[0].get("isWhiteNoise"))).is_false()
