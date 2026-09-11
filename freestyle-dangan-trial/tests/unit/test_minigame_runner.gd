extends GdUnitTestSuite
## The influence gauge is the trial's only escape from the replay loop, so who
## is allowed to refill it is a contract, not a detail.

## Reads the minigame sources, so this only runs from a source checkout - which
## is the only place tests run.
func _source_of(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	assert_str(text).override_failure_message("Could not read %s" % path).is_not_empty()
	return text


func test_no_minigame_resets_the_influence_gauge() -> void:
	# Five minigames used to reset in their own start(), which MinigameRunner
	# calls once per attempt - so every replay refilled the gauge and the
	# game-over screen was unreachable for six of the eight. The reset belongs
	# to the runner, once per minigame line.
	var offenders: Array[String] = []
	for game_type in MinigameCatalog.SCRIPTS:
		var path: String = MinigameCatalog.SCRIPTS[game_type]
		if _source_of(path).contains("InfluenceGauge.reset("):
			offenders.append(path)
	assert_array(offenders).is_empty()


func test_the_runner_caps_replays() -> void:
	# Three minigames never damage the gauge at all, so without a cap an
	# unwinnable round leaves killing the process as the only way out.
	assert_int(MinigameRunner.MAX_ATTEMPTS).is_greater(0)
	assert_str(
		_source_of("res://scripts/game/minigame_runner.gd")
	).contains("InfluenceGauge.reset()")
