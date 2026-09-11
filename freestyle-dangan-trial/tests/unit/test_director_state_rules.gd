extends GdUnitTestSuite
## What each of the director's states permits.
##
## The question "may the script be stepped forward from here?" was written out
## three times - in _on_advance_input, in the hold-to-skip branch of _process
## and in the auto-advance branch - and the class docstring spent a paragraph
## explaining that two of the eight states existed only so those comparisons
## would evaluate false. These assertions are that paragraph, made executable.

func after_test() -> void:
	ScriptDirector.reset()


# ---------------------------------------------------------------------------
# Stepping the script
# ---------------------------------------------------------------------------
func test_only_waiting_for_advance_steps_the_script() -> void:
	for state: int in ScriptDirector.State.values():
		var expected: bool = state == ScriptDirector.State.WAITING_FOR_ADVANCE
		assert_bool(ScriptDirector.state_steps_script(state)).override_failure_message(
			"state %d disagreed about stepping the script" % state
		).is_equal(expected)


func test_the_minigame_states_refuse_because_of_what_they_are() -> void:
	# MINIGAME_LOADING and MINIGAME_RESULT are assigned and never compared
	# against, which reads like dead weight. This is what they are for: while
	# the director sits in either, player input cannot step the script out from
	# under a minigame or its result card.
	assert_bool(ScriptDirector.state_steps_script(ScriptDirector.State.MINIGAME_LOADING)).is_false()
	assert_bool(ScriptDirector.state_steps_script(ScriptDirector.State.MINIGAME_ACTIVE)).is_false()
	assert_bool(ScriptDirector.state_steps_script(ScriptDirector.State.MINIGAME_RESULT)).is_false()


func test_a_paused_trial_refuses_to_advance() -> void:
	# The explicit PAUSED guard in _on_advance_input was redundant - PAUSED is
	# not WAITING_FOR_ADVANCE, so the next line returned anyway - but removing
	# a guard needs the behaviour it was guarding pinned somewhere real.
	assert_bool(ScriptDirector.state_steps_script(ScriptDirector.State.PAUSED)).is_false()


func test_advance_input_while_paused_does_not_move_the_line() -> void:
	ScriptDirector.script_lines = _two_narrator_lines()
	ScriptDirector.current_line_index = 0
	ScriptDirector._transition_to(ScriptDirector.State.WAITING_FOR_ADVANCE)
	ScriptDirector.pause_trial()

	ScriptDirector._on_advance_input()

	assert_int(ScriptDirector.current_line_index).override_failure_message(
		"a paused trial stepped to line %d" % ScriptDirector.current_line_index
	).is_equal(0)
	ScriptDirector.resume_trial()


func test_resuming_returns_to_the_state_that_was_paused() -> void:
	ScriptDirector._transition_to(ScriptDirector.State.WAITING_FOR_ADVANCE)
	ScriptDirector.pause_trial()
	assert_int(ScriptDirector.current_state).is_equal(ScriptDirector.State.PAUSED)
	ScriptDirector.resume_trial()
	assert_int(ScriptDirector.current_state).is_equal(ScriptDirector.State.WAITING_FOR_ADVANCE)


# ---------------------------------------------------------------------------
# Pausing
# ---------------------------------------------------------------------------
func test_an_idle_or_finished_trial_is_not_pausable() -> void:
	# There is nothing to come back to, so recording PAUSED over either would
	# lose the only state that means anything.
	assert_bool(ScriptDirector.state_is_pausable(ScriptDirector.State.IDLE)).is_false()
	assert_bool(ScriptDirector.state_is_pausable(ScriptDirector.State.TRIAL_COMPLETE)).is_false()


func test_every_other_state_is_pausable() -> void:
	for state: int in ScriptDirector.State.values():
		if state == ScriptDirector.State.IDLE or state == ScriptDirector.State.TRIAL_COMPLETE:
			continue
		assert_bool(ScriptDirector.state_is_pausable(state)).override_failure_message(
			"state %d refused to pause" % state
		).is_true()


func test_pausing_a_finished_trial_leaves_it_finished() -> void:
	ScriptDirector._transition_to(ScriptDirector.State.TRIAL_COMPLETE)
	ScriptDirector.pause_trial()
	assert_int(ScriptDirector.current_state).is_equal(ScriptDirector.State.TRIAL_COMPLETE)
	ScriptDirector.resume_trial()
	assert_int(ScriptDirector.current_state).is_equal(ScriptDirector.State.TRIAL_COMPLETE)


func test_nested_pauses_remember_the_state_underneath_them() -> void:
	# The settings menu can be opened on top of the game-over screen, which has
	# already paused. Without the count the inner pause would record PAUSED as
	# the state to return to, losing the real one, and closing the menu would
	# unpause a trial meant to stay stopped.
	ScriptDirector._transition_to(ScriptDirector.State.MINIGAME_ACTIVE)
	ScriptDirector.pause_trial()
	ScriptDirector.pause_trial()

	ScriptDirector.resume_trial()
	assert_int(ScriptDirector.current_state).override_failure_message(
		"the inner resume unpaused a trial that is meant to stay stopped"
	).is_equal(ScriptDirector.State.PAUSED)

	ScriptDirector.resume_trial()
	assert_int(ScriptDirector.current_state).is_equal(ScriptDirector.State.MINIGAME_ACTIVE)


func test_resuming_more_often_than_pausing_is_harmless() -> void:
	ScriptDirector._transition_to(ScriptDirector.State.WAITING_FOR_ADVANCE)
	ScriptDirector.resume_trial()
	assert_int(ScriptDirector.current_state).is_equal(ScriptDirector.State.WAITING_FOR_ADVANCE)
	assert_int(ScriptDirector._pause_depth).is_equal(0)


func _two_narrator_lines() -> Array[ScriptLine]:
	var lines: Array[ScriptLine] = []
	for id in ["n1", "n2"]:
		lines.append(ScriptLine.from_dict({"id": id, "type": "narrator", "text": id}))
	return lines
