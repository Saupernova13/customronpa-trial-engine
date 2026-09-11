class_name MinigameCatalog
extends RefCounted
## The gameType registry: which minigame types this build can play, and how to
## build one.
##
## Normative. `TrialValidator` warns about a type that is not here, and
## `test_trial_manifest.gd` asserts these keys match the schema's `gameType`
## enum exactly, so a type added to the schema and not to this table fails CI.
##
## It lives in the data layer rather than on `MinigameRunner` because both
## sides need it and only one of them is a scene. `TrialValidator` runs inside
## `TrialLoader._parse_manifest()`, before any scene exists; when the table was
## the runner's, validating a trial resolved a `Node` class that instantiates
## overlays, the HUD and `ScriptDirector`, and validation could not be
## exercised without all of it.

## gameType -> script path. A new minigame needs one entry here plus a
## MinigameBase subclass.
const SCRIPTS := {
	"nonstop_debate": "res://scripts/minigames/nonstop_debate.gd",
	"hangmans_gambit": "res://scripts/minigames/hangmans_gambit.gd",
	"logic_dive": "res://scripts/minigames/logic_dive.gd",
	"debate_scrum": "res://scripts/minigames/debate_scrum.gd",
	"mass_panic_debate": "res://scripts/minigames/mass_panic_debate.gd",
	"rebuttal_showdown": "res://scripts/minigames/rebuttal_showdown.gd",
	"psyche_taxi": "res://scripts/minigames/psyche_taxi.gd",
	"closing_argument": "res://scripts/minigames/closing_argument.gd",
}


static func has_type(game_type: String) -> bool:
	return SCRIPTS.has(game_type)


## Returns null on any of the three ways this can fail; each one logs which.
static func create(game_type: String) -> MinigameBase:
	if not SCRIPTS.has(game_type):
		Log.error("MinigameCatalog", "No script registered for minigame type: %s" % game_type)
		return null
	var path: String = SCRIPTS[game_type]
	var script: GDScript = load(path)
	if script == null:
		Log.error("MinigameCatalog", "Failed to load minigame script: %s" % path)
		return null
	var instance := script.new() as MinigameBase
	if instance == null:
		Log.error("MinigameCatalog", "%s does not extend MinigameBase" % path)
	return instance


## Authoring errors that would make this minigame unplayable, empty when it is
## fine. Empty too for a type this build does not know: that is the runner's
## unsupported-type path, not an authoring problem.
##
## validate_data() needs an initialised instance, and the one that actually
## plays is not built until the title card has finished - so this builds a
## throwaway probe. The probe is never added to the tree and start() is never
## called on it. Its whole lifetime is inside this function on purpose: when
## the create-and-free pair was the caller's, an early return added between
## them would have leaked one MinigameBase per minigame line, silently.
static func validation_errors(data: MinigameData) -> Array[String]:
	var probe: MinigameBase = create(data.game_type)
	if probe == null:
		return []
	probe.initialize(data)
	var errors: Array[String] = probe.validate_data()
	probe.free()
	return errors
