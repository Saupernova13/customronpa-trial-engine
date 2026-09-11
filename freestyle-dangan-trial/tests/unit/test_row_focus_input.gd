extends GdUnitTestSuite
## Row focus in Mass Panic Debate was read from KEY_UP/KEY_DOWN in the
## minigame's own _input(), while the same action arrived by touch through
## _on_row_tapped. Two implementations of one action, free to drift, and
## neither reachable from a gamepad.


func _key(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.pressed = true
	return event


## Stands in for any device bound to the action - d-pad, stick, a remapped
## key. is_action_pressed resolves all of them the same way.
func _action(name: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	return event


func _steps_from(event: InputEvent) -> Array:
	var seen: Array = []
	var handler := func(direction: int) -> void: seen.append(direction)
	InputManager.focus_step_requested.connect(handler)
	InputManager._input(event)
	InputManager.focus_step_requested.disconnect(handler)
	return seen


func test_the_arrow_keys_request_a_focus_step() -> void:
	assert_array(_steps_from(_key(KEY_UP))).is_equal([-1])
	assert_array(_steps_from(_key(KEY_DOWN))).is_equal([1])


func test_any_device_bound_to_ui_up_or_ui_down_requests_the_same_step() -> void:
	# The gamepad path the keycode match could never reach.
	assert_array(_steps_from(_action(&"ui_up"))).is_equal([-1])
	assert_array(_steps_from(_action(&"ui_down"))).is_equal([1])


func test_unrelated_keys_request_nothing() -> void:
	assert_array(_steps_from(_key(KEY_Q))).is_empty()


func test_the_navigation_event_is_left_for_the_gui_stage() -> void:
	# Consuming it here would disable focus navigation on every screen that
	# has focusable controls - which is exactly what the start menu's own
	# handler used to do to itself (#109).
	var viewport := get_viewport()
	InputManager._input(_key(KEY_UP))
	assert_bool(viewport.is_input_handled()).is_false()


func test_mass_panic_no_longer_reads_keycodes_itself() -> void:
	var script: GDScript = load(MinigameCatalog.SCRIPTS["mass_panic_debate"])
	var names: Array = script.get_script_method_list().map(
		func(entry: Dictionary) -> String: return entry["name"]
	)
	assert_bool(names.has("_input")).override_failure_message(
		"mass_panic_debate declares _input() again; row focus has two implementations"
	).is_false()


func test_a_focus_step_wraps_around_the_rows() -> void:
	var script: GDScript = load(MinigameCatalog.SCRIPTS["mass_panic_debate"])
	var game: MinigameBase = auto_free(script.new())
	game.focused_row = 0
	assert_int(game._next_row(-1)).is_equal(2)
	assert_int(game._next_row(1)).is_equal(1)
	game.focused_row = 2
	assert_int(game._next_row(1)).is_equal(0)
