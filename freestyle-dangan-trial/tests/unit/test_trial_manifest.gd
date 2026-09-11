extends GdUnitTestSuite
## Parsing contract for the typed model. Assertions here describe relationships
## that hold however the fixture grows - a reference resolving, a type round-
## tripping - never its element counts, so editing the fixture to cover a new
## case does not turn unrelated tests red.

const FIXTURE_PATH := "res://tests/fixtures/minimal-trial/trial.json"


## The schema lives beside the Godot project, not inside it, so res:// cannot
## reach it. Tests only ever run from a source checkout, where this resolves.
func _schema_path() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../schema/trial.schema.json")


func _load_manifest() -> TrialManifest:
	var text := FileAccess.get_file_as_string(FIXTURE_PATH)
	var json := JSON.new()
	assert_int(json.parse(text)).is_equal(OK)
	return TrialManifest.from_dict(json.data)


func test_fixture_parses_into_typed_model() -> void:
	var manifest := _load_manifest()
	assert_str(manifest.trial_name).is_equal("Fixture Trial")
	assert_str(manifest.format_version).is_equal("4.0")
	# Shape only, so a truncated or unparsed fixture still fails loudly.
	assert_array(manifest.script_lines).is_not_empty()
	assert_array(manifest.minigames).is_not_empty()


func test_every_minigame_reference_resolves() -> void:
	var manifest := _load_manifest()
	var seen := 0
	for line in manifest.script_lines:
		if line.type != ScriptLine.TYPE_MINIGAME:
			continue
		seen += 1
		assert_object(manifest.find_minigame(line.minigame_id)).is_not_null()
	assert_int(seen).is_greater(0)


func test_every_speaking_line_names_a_character_in_the_cast() -> void:
	var manifest := _load_manifest()
	var seen := 0
	for line in manifest.script_lines:
		if line.type != ScriptLine.TYPE_SPEAKING:
			continue
		seen += 1
		assert_bool(line.character_id in manifest.character_ids).is_true()
	assert_int(seen).is_greater(0)


func test_script_line_types_survive_parsing() -> void:
	var manifest := _load_manifest()
	var types := {}
	for line in manifest.script_lines:
		types[line.type] = true
	# The fixture is expected to exercise all three, in whatever order.
	assert_bool(types.has(ScriptLine.TYPE_SPEAKING)).is_true()
	assert_bool(types.has(ScriptLine.TYPE_NARRATOR)).is_true()
	assert_bool(types.has(ScriptLine.TYPE_MINIGAME)).is_true()


func test_null_audio_file_parses_as_empty() -> void:
	var manifest := _load_manifest()
	var found := false
	for line in manifest.script_lines:
		if line.id == "line_fixture_3":
			# This line carries "audioFile": null, which must not become "<null>".
			assert_str(line.audio_file).is_empty()
			found = true
	assert_bool(found).is_true()


## Makes the "CI cross-checks all three" claim in trial_validator.gd true for
## the one field where a divergence corrupts play silently: an unregistered
## gameType is reported to the script as a win (see #101).
func test_schema_game_types_match_the_runner_registry() -> void:
	var text := FileAccess.get_file_as_string(_schema_path())
	assert_str(text).override_failure_message(
		"Could not read %s" % _schema_path()
	).is_not_empty()
	var json := JSON.new()
	assert_int(json.parse(text)).is_equal(OK)
	var schema: Dictionary = json.data
	var minigame_def: Dictionary = schema["$defs"]["minigame"]
	var enum_values: Array = minigame_def["properties"]["gameType"]["enum"]
	assert_array(enum_values).contains_exactly_in_any_order(
		MinigameCatalog.SCRIPTS.keys()
	)


func test_find_minigame() -> void:
	var manifest := _load_manifest()
	var found := manifest.find_minigame("mg_fixture_debate")
	assert_object(found).is_not_null()
	assert_str(found.game_type).is_equal("nonstop_debate")
	assert_object(manifest.find_minigame("mg_nope")).is_null()


## Defence in depth, not a production path: TrialValidator.validate errors on
## a non-object script line and trial_loader refuses to load when validation
## returns errors, so nothing reaches from_dict with this input today. Kept
## because from_dict is also the entry point for tests and for any future
## caller that skips validation - but it is not a promise the format makes.
func test_non_dictionary_lines_are_skipped() -> void:
	var manifest := TrialManifest.from_dict({
		"trialName": "T",
		"characters": [],
		"script": {"lines": [{"id": "l1", "type": "narrator", "text": "hi"}, "junk", 7]},
		"metadata": {"version": "4.0"},
	})
	assert_int(manifest.script_lines.size()).is_equal(1)


func test_empty_dict_yields_empty_manifest() -> void:
	var manifest := TrialManifest.from_dict({})
	assert_str(manifest.trial_name).is_empty()
	assert_str(manifest.format_version).is_empty()
	assert_array(manifest.script_lines).is_empty()
	assert_array(manifest.minigames).is_empty()
	assert_object(manifest.find_minigame("anything")).is_null()


## The engine half of the fixture check. debate_text_panel.gd reads these names
## and nothing else; the fixture used to carry text/isWeakPoint/correctBulletId,
## which no code has ever written or read, and neither validator constrains
## typeSpecific enough to notice.
func test_fixture_debate_lines_use_the_names_the_panel_reads() -> void:
	var required := [
		"sentenceBeginning",
		"target",
		"sentenceEnd",
		"isShootable",
		"answerBulletId",
		"useNegativeBullet",
		"textEffect",
		"textFont",
		"textMovementDirection",
		"characterId",
	]
	var debates := _load_manifest().minigames.filter(
		func(mg: MinigameData) -> bool: return mg.game_type == "nonstop_debate"
	)
	assert_array(debates).is_not_empty()
	for minigame in debates:
		var lines: Array = minigame.type_specific.get("dialogueLines", [])
		assert_array(lines).is_not_empty()
		for line in lines:
			for key in required:
				assert_bool(line.has(key)).override_failure_message(
					"fixture dialogue line is missing '%s'" % key
				).is_true()
