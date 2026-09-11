extends ValidationRule
## Ids that name something the trial does not contain.
##
## Every one of these used to degrade silently at runtime instead: a minigame
## line warned and skipped, a bad character id gave a bench with no sprite and
## a portrait left over from the previous speaker, and a bad bullet id made the
## minigame unwinnable with nothing pointing at the trial file.
##
## All warnings, never errors. An error rejects the whole trial, and a dangling
## reference costs one line or one minigame - so failing on one would lock an
## author out of the editor's own broken output.
##
## Collected in a single pass rather than stopping at the first, so an author
## sees the whole list at once instead of one reload at a time.


func check(data: Dictionary, report: ValidationReport) -> void:
	var known := _known_ids(data)
	_check_script_lines(data, known, report)
	_check_minigames(data, known, report)


## The three id sets every reference below is resolved against, built once.
func _known_ids(data: Dictionary) -> Dictionary:
	return {
		"minigames": _ids_of(data.get("minigames", []), "gameId"),
		"bullets": _ids_of(data.get("truthBullets", []), "bulletId"),
		"characters": _string_set(data.get("characters", [])),
	}


func _ids_of(entries: Variant, key: String) -> Dictionary:
	var ids := {}
	if not entries is Array:
		return ids
	for entry in entries:
		if entry is Dictionary and entry.get(key) is String:
			ids[entry[key]] = true
	return ids


func _string_set(values: Variant) -> Dictionary:
	var ids := {}
	if not values is Array:
		return ids
	for value in values:
		if value is String:
			ids[value] = true
	return ids


func _check_script_lines(data: Dictionary, known: Dictionary, report: ValidationReport) -> void:
	var script: Variant = data.get("script")
	if not script is Dictionary or not script.get("lines") is Array:
		return

	var lines: Array = script["lines"]
	for i in range(lines.size()):
		var line: Variant = lines[i]
		if not line is Dictionary:
			continue
		var number := i + 1
		match line.get("type"):
			ScriptLine.TYPE_MINIGAME:
				var minigame_id: Variant = line.get("minigameId")
				if minigame_id is String:
					_require(minigame_id, known["minigames"], report,
						"script line %d references minigame '%s', which does not exist"
						% [number, minigame_id])
			ScriptLine.TYPE_SPEAKING:
				var character_id: Variant = line.get("characterId")
				# The editor writes "" for a line with no character chosen,
				# which is unset rather than dangling.
				if character_id is String and not character_id.is_empty():
					_require(character_id, known["characters"], report,
						"script line %d references character '%s', who is not in the cast"
						% [number, character_id])


func _check_minigames(data: Dictionary, known: Dictionary, report: ValidationReport) -> void:
	for entry in data.get("minigames", []):
		if not entry is Dictionary:
			continue
		var label := str(entry.get("gameId", "?"))
		var type_specific := JsonRead.dict_of(entry.get("typeSpecific"))

		var selected := JsonRead.strings_of(
			type_specific.get("selectedBullets"), "minigame '%s' selectedBullets" % label
		)
		for bullet_id in selected:
			_require(bullet_id, known["bullets"], report,
				"minigame '%s' selects truth bullet '%s', which does not exist"
				% [label, bullet_id])

		var dialogue_lines := JsonRead.dicts_of(
			type_specific.get("dialogueLines"), "minigame '%s' dialogueLines" % label
		)
		for line in dialogue_lines:
			var answer_id := JsonRead.str_of(line.get("answerBulletId"))
			if not answer_id.is_empty():
				_require(answer_id, known["bullets"], report,
					"minigame '%s' answers with truth bullet '%s', which does not exist"
					% [label, answer_id])


func _require(id: String, known: Dictionary, report: ValidationReport, message: String) -> void:
	if not known.has(id):
		report.warn(message)
