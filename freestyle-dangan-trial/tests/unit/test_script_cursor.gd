extends GdUnitTestSuite
## Walking the script, without a director.
##
## The index, the walk, the unknown-type skip and the batched skip report were
## 27 lines inside a Node autoload that also owns input, pause, settings and
## the minigame hand-off - so none of it could be exercised without a loaded
## trial and the whole autoload graph. Both of the non-obvious properties it
## carries are properties of the iteration itself: that it does not recurse,
## and that it reports a run of skipped types once rather than once per line.

const ScriptCursor := preload("res://scripts/core/trial/script_cursor.gd")

## Above Godot's default debug/settings/gdscript/max_call_stack of 1024, so a
## recursive walk would exceed the limit rather than sit just under it.
const UNKNOWN_RUN := 2000

const PLAYABLE := [ScriptLine.TYPE_SPEAKING, ScriptLine.TYPE_NARRATOR, ScriptLine.TYPE_MINIGAME]


func _lines(dicts: Array) -> Array[ScriptLine]:
	var out: Array[ScriptLine] = []
	for d in dicts:
		out.append(ScriptLine.from_dict(d))
	return out


func _cursor(dicts: Array) -> ScriptCursor:
	var cursor := ScriptCursor.new(PLAYABLE)
	cursor.lines = _lines(dicts)
	return cursor


func _narrator(id: String) -> Dictionary:
	return {"id": id, "type": "narrator", "text": id}


func test_a_fresh_cursor_sits_before_the_first_line() -> void:
	var cursor := _cursor([_narrator("n1")])
	assert_int(cursor.index).is_equal(-1)
	assert_object(cursor.current()).is_null()


func test_advancing_yields_each_line_in_order() -> void:
	var cursor := _cursor([_narrator("n1"), _narrator("n2")])
	var seen: Array[String] = []
	while cursor.advance():
		seen.append(cursor.current().id)
	assert_array(seen).is_equal(["n1", "n2"])


func test_advancing_past_the_end_reports_exhausted_and_stays_there() -> void:
	var cursor := _cursor([_narrator("n1")])
	assert_bool(cursor.advance()).is_true()
	assert_bool(cursor.advance()).is_false()
	# Repeatedly asking a finished cursor must not walk the index off forever.
	assert_bool(cursor.advance()).is_false()
	assert_object(cursor.current()).is_null()


func test_an_empty_script_is_exhausted_immediately() -> void:
	assert_bool(_cursor([]).advance()).is_false()


func test_a_line_whose_type_nothing_plays_is_flagged_not_hidden() -> void:
	# The director still emits line_started for it: skipping a line quietly is
	# not the same as never mentioning it.
	var cursor := _cursor([{"id": "u1", "type": "hologram"}])
	assert_bool(cursor.advance()).is_true()
	assert_object(cursor.current()).is_not_null()
	assert_bool(cursor.current_is_playable()).is_false()


func test_a_long_run_of_unknown_types_is_walked_not_recursed() -> void:
	# The walk used to advance by calling itself, so depth equalled the length
	# of the run. TrialValidator deliberately lets unknown types through with
	# a warning and check_version accepts a newer minor, so this input is
	# permitted by design and the engine has to survive it.
	var dicts: Array = []
	for i in range(UNKNOWN_RUN):
		dicts.append({"id": "u%d" % i, "type": "hologram"})
	dicts.append(_narrator("n1"))

	var cursor := _cursor(dicts)
	while cursor.advance():
		if cursor.current_is_playable():
			break

	assert_int(cursor.index).is_equal(UNKNOWN_RUN)
	assert_str(cursor.current().id).is_equal("n1")


func test_a_run_of_skipped_types_is_reported_once_per_type() -> void:
	# push_warning is expensive enough that a thousand of them cost far more
	# than the skipping, and a block of unknown types is one problem.
	var dicts: Array = []
	for i in range(50):
		dicts.append({"id": "a%d" % i, "type": "hologram"})
	for i in range(50):
		dicts.append({"id": "b%d" % i, "type": "interpretive_dance"})

	var cursor := _cursor(dicts)
	while cursor.advance():
		pass

	assert_array(cursor.take_skipped_types()).contains_exactly_in_any_order(
		["hologram", "interpretive_dance"]
	)


func test_taking_the_skipped_types_clears_them() -> void:
	# They are reported per walk, so a second report after the same run would
	# repeat a warning the author has already seen.
	var cursor := _cursor([{"id": "u1", "type": "hologram"}])
	while cursor.advance():
		pass
	assert_array(cursor.take_skipped_types()).has_size(1)
	assert_array(cursor.take_skipped_types()).is_empty()


func test_a_playable_line_is_never_recorded_as_skipped() -> void:
	var cursor := _cursor([_narrator("n1")])
	while cursor.advance():
		pass
	assert_array(cursor.take_skipped_types()).is_empty()


func test_replacing_the_lines_rewinds() -> void:
	# start_trial() loads a new script into a cursor that may be part way
	# through the previous one.
	var cursor := _cursor([_narrator("n1"), _narrator("n2")])
	cursor.advance()
	cursor.advance()
	cursor.lines = _lines([_narrator("m1")])
	assert_int(cursor.index).is_equal(-1)
	assert_bool(cursor.advance()).is_true()
	assert_str(cursor.current().id).is_equal("m1")


func test_rewinding_drops_what_the_previous_walk_skipped() -> void:
	var cursor := _cursor([{"id": "u1", "type": "hologram"}])
	cursor.advance()
	cursor.rewind()
	assert_int(cursor.index).is_equal(-1)
	assert_array(cursor.take_skipped_types()).is_empty()


func test_an_index_seeked_past_the_end_yields_no_line() -> void:
	# reset() and the retry path both write the index directly.
	var cursor := _cursor([_narrator("n1")])
	cursor.index = 99
	assert_object(cursor.current()).is_null()
	assert_bool(cursor.current_is_playable()).is_false()
