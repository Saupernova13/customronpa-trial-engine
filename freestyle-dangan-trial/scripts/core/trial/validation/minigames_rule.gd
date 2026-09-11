extends ValidationRule
## The minigames catalog. gameId and gameType are how a script line resolves to
## something playable, so a missing one is fatal; a gameType this build has no
## script for is not, because the runner tells the player and skips.


func check(data: Dictionary, report: ValidationReport) -> void:
	if not data.has("minigames"):
		return
	var minigames: Variant = data["minigames"]
	if not minigames is Array:
		report.error("minigames is not an array")
		return

	# Every bad entry, not the first. Stopping early meant an author with five
	# malformed minigames fixed them one reload at a time.
	for i in range(minigames.size()):
		_check_entry(minigames[i], i + 1, report)
	_warn_unplayable_types(minigames, report)


func _check_entry(entry: Variant, number: int, report: ValidationReport) -> void:
	if not entry is Dictionary:
		report.error("minigame %d is not an object" % number)
		return
	if not entry.get("gameId") is String:
		report.error("minigame %d has no gameId" % number)
	if not entry.get("gameType") is String:
		report.error(
			"minigame %d (%s) has no gameType" % [number, str(entry.get("gameId", "?"))]
		)


## One message per run, not one per entry: a trial from a newer minor could
## carry dozens, and this is the author's cue that the engine is behind the
## editor rather than that the file is broken. MinigameCatalog is the normative
## list - test_trial_manifest.gd pins it to the schema's enum.
func _warn_unplayable_types(minigames: Array, report: ValidationReport) -> void:
	var unknown: Array[String] = []
	for entry in minigames:
		if not entry is Dictionary:
			continue
		var game_type: Variant = entry.get("gameType")
		if not game_type is String or MinigameCatalog.has_type(game_type):
			continue
		if not unknown.has(game_type):
			unknown.append(game_type)
	if not unknown.is_empty():
		report.warn(
			"Trial uses minigame types this engine cannot play: %s" % ", ".join(unknown)
		)
