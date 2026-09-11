extends GdUnitTestSuite
## GameRandom promises that "one seed per launch drives every minigame's
## procedural variation, so a whole session replays from it". One minigame of
## four honoured it: Debate Scrum called Array.shuffle(), which reads the
## global RNG the session seed does not drive, and Hangman's Gambit and
## Nonstop Debate used bare randf()/randi(). A seed reproduced the debate
## panel's visuals while the spawn logic driving them diverged.

const SOURCE_ROOT := "res://scripts"

## GameRandom itself draws the session seed from entropy, by design.
const EXEMPT := ["res://scripts/core/game_random.gd"]

## Bare calls read the global RNG. `rng.randf()` does not, and the scan tells
## them apart by the character in front of the name.
const GLOBAL_RNG_CALLS := [
	"randf(",
	"randi(",
	"randf_range(",
	"randi_range(",
	"randfn(",
	"rand_from_seed(",
	".shuffle(",
]


func _probe_scrum() -> MinigameBase:
	var script: GDScript = load(MinigameCatalog.SCRIPTS["debate_scrum"])
	var game: MinigameBase = auto_free(script.new())
	game.initialize(MinigameData.from_dict({"gameId": "mg_s", "gameType": "debate_scrum"}))
	game._defense_buttons.resize(5)
	return game


func _deal_from_seed(seed_value: int) -> Array:
	GameRandom.reseed(seed_value)
	var defense: Array[String] = ["d1", "d2"]
	var opposition: Array[String] = ["o1", "o2", "o3", "o4", "o5", "o6"]
	return _probe_scrum()._deal_keywords(defense, opposition)


func test_one_seed_deals_a_scrum_round_the_same_way_twice() -> void:
	assert_array(_deal_from_seed(12345)).is_equal(_deal_from_seed(12345))


func test_different_seeds_deal_differently() -> void:
	# Six decoys for four free buttons: the order and the subset both move, so
	# a shared prefix across all ten is a shuffle that is not running.
	var first := _deal_from_seed(1)
	var differed := false
	for candidate_seed in range(2, 12):
		if _deal_from_seed(candidate_seed) != first:
			differed = true
			break
	assert_bool(differed).override_failure_message(
		"the deal was identical under ten different seeds: %s" % [first]
	).is_true()


func test_reseeding_restores_the_stream_a_replay_would_get() -> void:
	# stream() hands out a distinct stream per call on a label, so a second
	# attempt differs - but reseed() clears the counters, so the same seed
	# replays the session from the start.
	GameRandom.reseed(777)
	var first := GameRandom.stream("probe").randi()
	var second := GameRandom.stream("probe").randi()
	GameRandom.reseed(777)
	assert_int(GameRandom.stream("probe").randi()).is_equal(first)
	assert_int(GameRandom.stream("probe").randi()).is_equal(second)


# ---------------------------------------------------------------------------
# Source tripwire
#
# The behavioural tests above cover the sites that exist today. This one is
# what stops the fourth minigame from being written the same way again: the
# guarantee is a whole-codebase property, so it is checked across the whole
# codebase rather than one call site at a time.
# ---------------------------------------------------------------------------


func test_no_script_reaches_for_the_global_rng() -> void:
	var offenders: Array[String] = []
	_scan_dir(SOURCE_ROOT, offenders)
	assert_array(offenders).override_failure_message(
		(
			"These read the global RNG, which DANGAN_SEED does not drive. "
			+ "Take a stream with GameRandom.stream(label) and call it on that, "
			+ "or use GameRandom.shuffle_with for a shuffle:\n  %s"
		)
		% "\n  ".join(offenders)
	).is_empty()


## A scanner that matches nothing passes forever. These are the exact lines
## this change removed, and the sanctioned forms that replaced them.
func test_the_scan_can_tell_a_bare_call_from_a_method_call() -> void:
	assert_bool(_calls_globally("	if randf() < 0.4:", "randf(")).is_true()
	assert_bool(_calls_globally("	letter = a[randi() % a.length()]", "randi(")).is_true()
	assert_bool(_calls_globally("		audio_duration = randf_range(4.0, 6.0)", "randf_range(")).is_true()
	assert_bool(_calls_globally("		chosen.shuffle()", ".shuffle(")).is_true()

	assert_bool(_calls_globally("	if _rng.randf() < 0.4:", "randf(")).is_false()
	assert_bool(_calls_globally("		audio_duration = _rng.randf_range(4.0, 6.0)", "randf_range(")).is_false()
	assert_bool(_calls_globally("	GameRandom.shuffle_with(chosen, _rng)", ".shuffle(")).is_false()
	# randfn is a different call; "randf(" must not match inside it.
	assert_bool(_calls_globally("	var x := session.randfn(0.0, 1.0)", "randf(")).is_false()


func _scan_dir(path: String, offenders: Array[String]) -> void:
	var dir := DirAccess.open(path)
	assert_object(dir).override_failure_message("cannot open %s" % path).is_not_null()
	for name in dir.get_directories():
		_scan_dir(path.path_join(name), offenders)
	for name in dir.get_files():
		if name.ends_with(".gd"):
			_scan_file(path.path_join(name), offenders)


func _scan_file(path: String, offenders: Array[String]) -> void:
	if EXEMPT.has(path):
		return
	var text := FileAccess.get_file_as_string(path)
	assert_str(text).override_failure_message("cannot read %s" % path).is_not_empty()
	var lines := text.split("\n")
	for i in range(lines.size()):
		var line: String = lines[i]
		# Comment lines describe these calls on purpose.
		if line.strip_edges().begins_with("#"):
			continue
		for call in GLOBAL_RNG_CALLS:
			if _calls_globally(line, call):
				offenders.append("%s:%d: %s" % [path, i + 1, line.strip_edges()])
				break


## True when `call` appears as a bare call rather than a method on an object.
## `.shuffle(` is listed with its dot, because every shuffle goes through
## GameRandom.shuffle_with - there is no receiver that makes it acceptable.
func _calls_globally(line: String, call: String) -> bool:
	var from := 0
	while true:
		var at := line.find(call, from)
		if at < 0:
			return false
		from = at + 1
		if call.begins_with("."):
			return true
		# `rng.randf(` and `randfn(` both contain "randf(" - only a name
		# boundary in front makes it a bare call.
		if at == 0:
			return true
		var before := line[at - 1]
		if not (before == "." or before == "_" or before.is_valid_identifier()):
			return true
	return false
