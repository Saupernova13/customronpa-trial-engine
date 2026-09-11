class_name TrialValidator
extends RefCounted
## Structural validation for trial.json. schema/trial.schema.json is normative
## and this file must track it, but only two things are actually enforced: the
## editor cross-checks its own validator against the schema case by case
## (web-ui-editor/tests/schema.test.js), and test_trial_manifest.gd pins the
## gameType enum to MinigameCatalog. Everything else here can drift from the
## schema without CI noticing - the missing per-line required-field checks
## especially.
##
## Deliberately laxer than the editor: checks only what playback needs, so
## imperfect files stay playable and per-line problems warn instead of failing.

const SUPPORTED_FORMAT_MAJOR := 4
const LINE_TYPES := ScriptLine.TYPES


## "" when acceptable; an error message when the file needs a newer engine.
static func check_version(data: Dictionary) -> String:
	var metadata = data.get("metadata")
	if not metadata is Dictionary or not metadata.get("version") is String:
		push_warning("trial.json has no metadata.version; assuming a legacy file")
		return ""
	var version: String = metadata["version"]
	var parts := version.split(".")
	if parts.size() < 1 or not parts[0].is_valid_int():
		push_warning("Unrecognized trial format version '%s'" % version)
		return ""
	var major := parts[0].to_int()
	if major > SUPPORTED_FORMAT_MAJOR:
		return (
			"This trial uses format %s, made with a newer editor. "
			+ "Update the engine to play it."
		) % version
	if major < SUPPORTED_FORMAT_MAJOR:
		push_warning(
			"Trial format %s is older than %d.x; attempting to load"
			% [version, SUPPORTED_FORMAT_MAJOR]
		)
	return ""


## Essentials only. typeSpecific shapes are constrained by the schema and the
## editor's mirror of it, and each minigame's validate_data() reports a payload
## it cannot play - checking them a third time here would be a third copy to
## keep in step.
## Returns human-readable errors; empty means loadable.
static func validate(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if not data.get("trialName") is String:
		errors.append("trialName is missing or not a string")
	if not data.get("characters") is Array:
		errors.append("characters is missing or not an array")

	var script = data.get("script")
	if not script is Dictionary or not script.get("lines") is Array:
		errors.append("script.lines is missing or not an array")
	else:
		for i in range(script["lines"].size()):
			var line = script["lines"][i]
			if not line is Dictionary:
				errors.append("script line %d is not an object" % (i + 1))
				continue
			if not line.get("type") is String or not LINE_TYPES.has(line["type"]):
				push_warning(
					"script line %d has unknown type '%s' (will be skipped)"
					% [i + 1, str(line.get("type"))]
				)
			elif line["type"] == ScriptLine.TYPE_MINIGAME and not line.get("minigameId") is String:
				errors.append("script line %d: minigame line has no minigameId" % (i + 1))

	if data.has("minigames") and not data.get("minigames") is Array:
		errors.append("minigames is not an array")
	elif data.get("minigames") is Array:
		# Every bad entry, not the first. The old `break` meant an author with
		# five malformed minigames fixed them one reload at a time, and the
		# message named neither the index nor the gameId.
		for i in range(data["minigames"].size()):
			var mg = data["minigames"][i]
			if not mg is Dictionary:
				errors.append("minigame %d is not an object" % (i + 1))
				continue
			if not mg.get("gameId") is String:
				errors.append("minigame %d has no gameId" % (i + 1))
			if not mg.get("gameType") is String:
				errors.append(
					"minigame %d (%s) has no gameType" % [i + 1, str(mg.get("gameId", "?"))]
				)
		_warn_unknown_game_types(data["minigames"])

	if data.has("truthBullets") and not data.get("truthBullets") is Array:
		errors.append("truthBullets is not an array")
	elif data.get("truthBullets") is Array:
		# Element shape was unchecked, so an array of strings passed here,
		# passed TrialManifest.from_dict, and reached
		# TruthBulletManager.load_bullets - which emits it into a
		# Dictionary-typed signal. Godot checks that per listener at dispatch,
		# so the emitter survives and the listener silently never runs: the
		# player sees a stale or blank bullet name, with no crash and nothing
		# pointing at the trial file.
		for i in range(data["truthBullets"].size()):
			var bullet = data["truthBullets"][i]
			if not bullet is Dictionary:
				push_warning("truth bullet %d is not an object; it will not be selectable" % (i + 1))
			elif not bullet.get("bulletId") is String:
				push_warning("truth bullet %d has no bulletId; it cannot be matched" % (i + 1))

	# Warned, never fatal. Any error here rejects the whole trial
	# (trial_loader.gd:199), and a dangling reference degrades one line or one
	# minigame rather than making the file unplayable - so failing on it would
	# lock the author out of the editor's own broken output.
	for message in _dangling_references(data):
		push_warning(message)
	return errors

## Ids that name something the trial does not contain. Every dangling
## reference used to degrade silently at runtime instead - a minigame line
## warned and skipped, a bad character id gave a bench with no sprite and a
## portrait from the previous speaker, and a bad bullet id made the minigame
## unwinnable.
##
## Collected rather than stopping at the first, so an author sees the whole
## list in one pass instead of one reload at a time.
static func _dangling_references(data: Dictionary) -> Array[String]:
	var errors: Array[String] = []

	var minigame_ids := {}
	for mg in data.get("minigames", []):
		if mg is Dictionary and mg.get("gameId") is String:
			minigame_ids[mg["gameId"]] = true

	var bullet_ids := {}
	for bullet in data.get("truthBullets", []):
		if bullet is Dictionary and bullet.get("bulletId") is String:
			bullet_ids[bullet["bulletId"]] = true

	var character_ids := {}
	for character_id in data.get("characters", []):
		if character_id is String:
			character_ids[character_id] = true

	var script = data.get("script")
	if script is Dictionary and script.get("lines") is Array:
		for i in range(script["lines"].size()):
			var line = script["lines"][i]
			if not line is Dictionary:
				continue
			var line_type = line.get("type")
			if line_type == ScriptLine.TYPE_MINIGAME:
				var minigame_id = line.get("minigameId")
				if minigame_id is String and not minigame_ids.has(minigame_id):
					errors.append(
						"script line %d references minigame '%s', which does not exist"
						% [i + 1, minigame_id]
					)
			elif line_type == ScriptLine.TYPE_SPEAKING:
				var character_id = line.get("characterId")
				if character_id is String and not character_id.is_empty():
					if not character_ids.has(character_id):
						errors.append(
							"script line %d references character '%s', who is not in the cast"
							% [i + 1, character_id]
						)

	for mg in data.get("minigames", []):
		if not mg is Dictionary:
			continue
		var label = str(mg.get("gameId", "?"))
		var type_specific := JsonRead.dict_of(mg.get("typeSpecific"))
		var selected := JsonRead.strings_of(
			type_specific.get("selectedBullets"), "minigame '%s' selectedBullets" % label
		)
		for bullet_id in selected:
			if not bullet_ids.has(bullet_id):
				errors.append(
					"minigame '%s' selects truth bullet '%s', which does not exist"
					% [label, bullet_id]
				)
		var dialogue_lines := JsonRead.dicts_of(
			type_specific.get("dialogueLines"), "minigame '%s' dialogueLines" % label
		)
		for line in dialogue_lines:
			var answer_id := JsonRead.str_of(line.get("answerBulletId"))
			if not answer_id.is_empty() and not bullet_ids.has(answer_id):
				errors.append(
					"minigame '%s' answers with truth bullet '%s', which does not exist"
					% [label, answer_id]
				)

	return errors

## A warning, not an error: an unknown type is skipped at runtime with a notice
## rather than making the trial unloadable, and check_version deliberately
## accepts a newer minor that might carry one. MinigameCatalog is the normative
## list - test_trial_manifest.gd pins it to the schema's enum - so naming it at
## load makes the problem visible before the player reaches it.
static func _warn_unknown_game_types(minigames: Array) -> void:
	var unknown: Array[String] = []
	for mg in minigames:
		if not mg is Dictionary:
			continue
		var game_type = mg.get("gameType")
		if not game_type is String or MinigameCatalog.has_type(game_type):
			continue
		if not unknown.has(game_type):
			unknown.append(game_type)
	if not unknown.is_empty():
		push_warning("Trial uses minigame types this engine cannot play: %s" % ", ".join(unknown))
