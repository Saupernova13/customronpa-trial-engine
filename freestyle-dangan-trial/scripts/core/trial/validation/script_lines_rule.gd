extends ValidationRule
## The script itself. Without playable lines there is no trial, so a missing or
## misshapen script.lines is fatal - but an individual line is not.
##
## An unknown line type warns rather than failing: check_version deliberately
## accepts an older or newer minor, which may carry a type this build has no
## handler for, and ScriptDirector skips those with one batched report.

const LINE_TYPES := ScriptLine.TYPES


func check(data: Dictionary, report: ValidationReport) -> void:
	var script: Variant = data.get("script")
	if not script is Dictionary or not script.get("lines") is Array:
		report.error("script.lines is missing or not an array")
		return

	var lines: Array = script["lines"]
	for i in range(lines.size()):
		_check_line(lines[i], i + 1, report)


func _check_line(line: Variant, number: int, report: ValidationReport) -> void:
	if not line is Dictionary:
		report.error("script line %d is not an object" % number)
		return
	if not line.get("type") is String or not LINE_TYPES.has(line["type"]):
		report.warn(
			"script line %d has unknown type '%s' (will be skipped)"
			% [number, str(line.get("type"))]
		)
		return
	# A minigame line with no id names nothing to play, and ScriptDirector
	# would step over it silently.
	if line["type"] == ScriptLine.TYPE_MINIGAME and not line.get("minigameId") is String:
		report.error("script line %d: minigame line has no minigameId" % number)
