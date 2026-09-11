class_name ValidationReport
extends RefCounted
## What a validation pass found, at two severities.
##
## An error rejects the whole trial (trial_loader.gd), so it is reserved for a
## file playback cannot proceed on. A warning degrades one line, one minigame
## or one bullet and is reported to the author without blocking them - notably
## for anything the editor itself can emit, because failing on that would lock
## an author out of their own broken output.
##
## Severity used to be a property of the consumer rather than of the finding:
## a check either appended to a local array TrialValidator returned, or called
## push_warning itself. _dangling_references did both - collecting into an
## array named `errors` that the caller downgraded to warnings one at a time.
## Nothing could ask for the warnings, and no test could assert on them.

var errors: Array[String] = []
var warnings: Array[String] = []


## Fatal: the trial will not load.
func error(message: String) -> void:
	errors.append(message)


## Advisory: something is wrong but the trial still plays.
func warn(message: String) -> void:
	warnings.append(message)


func has_errors() -> bool:
	return not errors.is_empty()
