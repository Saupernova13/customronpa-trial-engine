extends ValidationRule
## trialName and characters: the two top-level fields nothing downstream can
## do without. TrialManifest reads both unconditionally.


func check(data: Dictionary, report: ValidationReport) -> void:
	if not data.get("trialName") is String:
		report.error("trialName is missing or not a string")
	if not data.get("characters") is Array:
		report.error("characters is missing or not an array")
