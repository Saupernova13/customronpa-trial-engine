class_name TrialValidator
extends RefCounted
## Structural validation for trial.json, as a composite of rules.
##
## schema/trial.schema.json is normative and these rules must track it, but
## only two things are actually enforced: the editor cross-checks its own
## validator against the schema case by case
## (web-ui-editor/tests/schema.test.js), and test_trial_manifest.gd pins the
## gameType enum to MinigameCatalog. Everything else here can drift from the
## schema without CI noticing - the missing per-line required-field checks
## especially.
##
## Deliberately laxer than the editor: checks only what playback needs, so
## imperfect files stay playable and per-line problems warn instead of failing.
##
## The rules run unconditionally and in order; none of them decides whether a
## later one runs, so this is a composite rather than a chain of
## responsibility. Order is not load-bearing for correctness, only for the
## order errors come out in.

const SUPPORTED_FORMAT_MAJOR := 4
const LINE_TYPES := ScriptLine.TYPES

const RULES: Array = [
	preload("res://scripts/core/trial/validation/trial_name_rule.gd"),
	preload("res://scripts/core/trial/validation/script_lines_rule.gd"),
	preload("res://scripts/core/trial/validation/minigames_rule.gd"),
	preload("res://scripts/core/trial/validation/truth_bullets_rule.gd"),
	preload("res://scripts/core/trial/validation/dangling_references_rule.gd"),
]


## "" when acceptable; an error message when the file needs a newer engine.
##
## Separate from the rules because it gates them: TrialLoader refuses a file
## from a newer major before reading anything else out of it, and the shapes
## the rules check are exactly what a major bump is allowed to change.
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


## Everything every rule found, at both severities. Prefer this over validate()
## when the warnings matter - a tool reporting to an author, or a test.
static func report(data: Dictionary) -> ValidationReport:
	var result := ValidationReport.new()
	for rule_script in RULES:
		var rule: ValidationRule = rule_script.new()
		rule.check(data, result)
	return result


## Returns human-readable errors; empty means loadable. Warnings go to the
## engine, because this is what TrialLoader calls and an author running the
## editor has nowhere else to see them.
static func validate(data: Dictionary) -> Array[String]:
	var result := report(data)
	for message in result.warnings:
		push_warning(message)
	return result.errors
