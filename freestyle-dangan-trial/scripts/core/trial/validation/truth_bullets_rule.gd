extends ValidationRule
## The evidence list. The array itself is fatal when misshapen, because
## TrialManifest and TruthBulletManager both walk it; an individual entry is
## not, because the rest of the trial still plays without it.


func check(data: Dictionary, report: ValidationReport) -> void:
	if not data.has("truthBullets"):
		return
	var bullets: Variant = data["truthBullets"]
	if not bullets is Array:
		report.error("truthBullets is not an array")
		return

	# Element shape was once unchecked, so an array of strings passed here,
	# passed TrialManifest.from_dict, and reached TruthBulletManager.load_bullets
	# - which emits it into a Dictionary-typed signal. Godot checks that per
	# listener at dispatch, so the emitter survives and the listener silently
	# never runs: the player sees a stale or blank bullet name, with no crash
	# and nothing pointing at the trial file.
	for i in range(bullets.size()):
		var bullet: Variant = bullets[i]
		if not bullet is Dictionary:
			report.warn(
				"truth bullet %d is not an object; it will not be selectable" % (i + 1)
			)
		elif not bullet.get("bulletId") is String:
			report.warn("truth bullet %d has no bulletId; it cannot be matched" % (i + 1))
