extends GdUnitTestSuite
## Each validation rule on its own.
##
## This is what the composite bought. The checks used to be five inline blocks
## inside one 60-line static function plus a second 60-line one beside it, so
## exercising a single check meant running all eight and, for anything they
## reported as a warning, scraping engine output. A rule is now a class with
## one entry point, and a test can hand it a Dictionary and read the report.
##
## Rules are not registered as global classes - TrialValidator is the only
## thing that builds them - so they are preloaded by path here, the same way it
## does.

const TrialNameRule := preload("res://scripts/core/trial/validation/trial_name_rule.gd")
const ScriptLinesRule := preload("res://scripts/core/trial/validation/script_lines_rule.gd")
const MinigamesRule := preload("res://scripts/core/trial/validation/minigames_rule.gd")
const TruthBulletsRule := preload("res://scripts/core/trial/validation/truth_bullets_rule.gd")
const DanglingReferencesRule := preload(
	"res://scripts/core/trial/validation/dangling_references_rule.gd"
)


func _run(rule_script: GDScript, data: Dictionary) -> ValidationReport:
	var report := ValidationReport.new()
	var rule: ValidationRule = rule_script.new()
	rule.check(data, report)
	return report


# ---------------------------------------------------------------------------
# TrialNameRule
# ---------------------------------------------------------------------------
func test_trial_name_rule_wants_both_fields() -> void:
	assert_array(_run(TrialNameRule, {}).errors).has_size(2)
	assert_array(_run(TrialNameRule, {"trialName": "T", "characters": []}).errors).is_empty()


func test_trial_name_rule_rejects_a_non_string_name() -> void:
	# A number here reaches TrialManifest.trial_name, which is typed String.
	assert_array(_run(TrialNameRule, {"trialName": 7, "characters": []}).errors).has_size(1)


# ---------------------------------------------------------------------------
# ScriptLinesRule
# ---------------------------------------------------------------------------
func test_script_lines_rule_is_fatal_only_about_the_array_itself() -> void:
	assert_array(_run(ScriptLinesRule, {}).errors).has_size(1)
	assert_array(_run(ScriptLinesRule, {"script": {}}).errors).has_size(1)
	assert_array(_run(ScriptLinesRule, {"script": {"lines": []}}).errors).is_empty()


func test_script_lines_rule_warns_about_a_type_it_cannot_play() -> void:
	# check_version accepts a newer minor, which may carry one; the director
	# skips it with a batched report rather than failing.
	var report := _run(ScriptLinesRule, {"script": {"lines": [{"type": "hologram"}]}})
	assert_array(report.errors).is_empty()
	assert_array(report.warnings).has_size(1)


func test_script_lines_rule_reports_an_unknown_type_before_the_minigame_check() -> void:
	# An unknown type must not also be reported as a minigame line missing its
	# id - one problem, one message.
	var report := _run(ScriptLinesRule, {"script": {"lines": [{"type": null}]}})
	assert_array(report.errors).is_empty()
	assert_array(report.warnings).has_size(1)


func test_script_lines_rule_is_fatal_about_a_minigame_line_with_no_id() -> void:
	var report := _run(ScriptLinesRule, {"script": {"lines": [{"type": "minigame"}]}})
	assert_array(report.errors).has_size(1)
	assert_str(report.errors[0]).contains("line 1")


func test_script_lines_rule_numbers_lines_from_one() -> void:
	var report := _run(ScriptLinesRule, {
		"script": {"lines": [{"type": "narrator"}, {"type": "minigame"}]},
	})
	assert_str(report.errors[0]).contains("script line 2")


# ---------------------------------------------------------------------------
# MinigamesRule
# ---------------------------------------------------------------------------
func test_minigames_rule_ignores_a_trial_with_no_minigames() -> void:
	var report := _run(MinigamesRule, {})
	assert_array(report.errors).is_empty()
	assert_array(report.warnings).is_empty()


func test_minigames_rule_reports_every_bad_entry() -> void:
	# Stopping at the first meant an author with five bad entries fixed them
	# one reload at a time.
	var report := _run(MinigamesRule, {"minigames": [
		{"gameType": "nonstop_debate"},
		{"gameId": "mg_2"},
		"not an object",
	]})
	assert_array(report.errors).has_size(3)


func test_minigames_rule_names_the_entry_it_is_complaining_about() -> void:
	var report := _run(MinigamesRule, {"minigames": [{"gameId": "mg_late"}]})
	assert_str(report.errors[0]).contains("mg_late")


func test_minigames_rule_warns_once_about_all_unplayable_types() -> void:
	var report := _run(MinigamesRule, {"minigames": [
		{"gameId": "a", "gameType": "quantum_debate"},
		{"gameId": "b", "gameType": "quantum_debate"},
	]})
	assert_array(report.errors).is_empty()
	assert_array(report.warnings).has_size(1)


func test_minigames_rule_accepts_every_type_the_catalog_can_build() -> void:
	# MinigameCatalog is the normative list and the schema's enum is pinned to
	# it, so the validator agreeing with the catalog is what makes the three
	# sources one.
	for game_type in MinigameCatalog.SCRIPTS:
		var report := _run(MinigamesRule, {
			"minigames": [{"gameId": "mg_1", "gameType": game_type}],
		})
		assert_array(report.warnings).override_failure_message(
			"%s was warned about: %s" % [game_type, report.warnings]
		).is_empty()


# ---------------------------------------------------------------------------
# TruthBulletsRule
# ---------------------------------------------------------------------------
func test_truth_bullets_rule_is_fatal_only_about_the_array() -> void:
	assert_array(_run(TruthBulletsRule, {"truthBullets": {}}).errors).has_size(1)
	assert_array(_run(TruthBulletsRule, {"truthBullets": []}).errors).is_empty()


func test_truth_bullets_rule_warns_about_an_entry_it_cannot_match() -> void:
	# An array of strings used to pass every check and reach a Dictionary-typed
	# signal, which dropped it per listener with no crash and nothing said.
	var report := _run(TruthBulletsRule, {"truthBullets": ["tb_1", {"name": "no id"}]})
	assert_array(report.errors).is_empty()
	assert_array(report.warnings).has_size(2)


# ---------------------------------------------------------------------------
# DanglingReferencesRule
# ---------------------------------------------------------------------------
func _cast_of(overrides: Dictionary) -> Dictionary:
	var base := {"characters": ["CH_1"], "truthBullets": [{"bulletId": "tb_1"}]}
	base.merge(overrides, true)
	return base


func test_dangling_rule_finds_all_four_reference_kinds_in_one_pass() -> void:
	var report := _run(DanglingReferencesRule, _cast_of({
		"script": {"lines": [
			{"type": "minigame", "minigameId": "mg_gone"},
			{"type": "speaking", "characterId": "CH_GONE"},
			{"type": "speaking", "characterId": "CH_1"},
		]},
		"minigames": [{
			"gameId": "mg_1",
			"typeSpecific": {
				"selectedBullets": ["tb_1", "tb_gone"],
				"dialogueLines": [{"answerBulletId": "tb_also_gone"}],
			},
		}],
	}))
	# A missing minigame, a missing character, a missing selected bullet and a
	# missing answer bullet.
	assert_array(report.warnings).has_size(4)


func test_dangling_rule_never_reports_a_fatal() -> void:
	# Any error rejects the whole file, and a dangling reference costs one line
	# - so failing on one would lock an author out of the editor's own output.
	var report := _run(DanglingReferencesRule, _cast_of({
		"script": {"lines": [{"type": "minigame", "minigameId": "mg_gone"}]},
	}))
	assert_array(report.errors).is_empty()


func test_dangling_rule_is_quiet_about_a_coherent_trial() -> void:
	var report := _run(DanglingReferencesRule, _cast_of({
		"script": {"lines": [{"type": "speaking", "characterId": "CH_1"}]},
		"minigames": [{
			"gameId": "mg_1",
			"typeSpecific": {
				"selectedBullets": ["tb_1"],
				"dialogueLines": [{"answerBulletId": "tb_1"}],
			},
		}],
	}))
	assert_array(report.warnings).is_empty()


func test_dangling_rule_treats_an_empty_character_id_as_unset() -> void:
	# The editor writes "" for a speaking line with no character chosen.
	var report := _run(DanglingReferencesRule, _cast_of({
		"script": {"lines": [{"type": "speaking", "characterId": ""}]},
	}))
	assert_array(report.warnings).is_empty()


func test_dangling_rule_survives_a_trial_with_no_sections_at_all() -> void:
	# Every id set is built from a section that may be absent or the wrong
	# type; none of that may abort the pass.
	assert_array(_run(DanglingReferencesRule, {}).warnings).is_empty()
	assert_array(_run(DanglingReferencesRule, {
		"characters": "not an array",
		"truthBullets": 7,
		"minigames": {},
		"script": [],
	}).warnings).is_empty()
