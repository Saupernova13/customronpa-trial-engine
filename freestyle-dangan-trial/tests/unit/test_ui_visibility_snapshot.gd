extends GdUnitTestSuite
## Hiding the conversation UI for a minigame and putting it back.
##
## This was two bool fields, two captures and two restores in MinigameRunner,
## which is how the second hidden node arrived - copied from the first. The
## cases below are the ones that copy would have had to get right a third time.


func _item(visible: bool) -> CanvasItem:
	var item: CanvasItem = auto_free(Control.new())
	add_child(item)
	item.visible = visible
	return item


func test_hiding_hides_and_restoring_puts_back() -> void:
	var shown := _item(true)
	var snapshot := UiVisibilitySnapshot.hide_all([shown])
	assert_bool(shown.visible).is_false()
	snapshot.restore()
	assert_bool(shown.visible).is_true()


func test_a_node_that_was_already_hidden_stays_hidden() -> void:
	# The point of capturing rather than just showing everything afterwards.
	var already_hidden := _item(false)
	var snapshot := UiVisibilitySnapshot.hide_all([already_hidden])
	snapshot.restore()
	assert_bool(already_hidden.visible).is_false()


func test_a_mixed_set_is_restored_per_node() -> void:
	var shown := _item(true)
	var hidden := _item(false)
	var snapshot := UiVisibilitySnapshot.hide_all([shown, hidden])
	assert_bool(shown.visible).is_false()
	assert_bool(hidden.visible).is_false()

	snapshot.restore()
	assert_bool(shown.visible).is_true()
	assert_bool(hidden.visible).is_false()


func test_a_null_in_the_set_is_skipped() -> void:
	# MinigameRunner is handed its nodes by the trial room and any of them can
	# be absent, so a caller must not have to filter first.
	var shown := _item(true)
	var snapshot := UiVisibilitySnapshot.hide_all([null, shown, null])
	assert_int(snapshot.size()).is_equal(1)
	snapshot.restore()
	assert_bool(shown.visible).is_true()


func test_a_node_freed_before_the_restore_is_skipped() -> void:
	# The scene can change under a running minigame.
	var doomed: CanvasItem = Control.new()
	add_child(doomed)
	var survivor := _item(true)
	var snapshot := UiVisibilitySnapshot.hide_all([doomed, survivor])

	doomed.free()
	snapshot.restore()

	assert_bool(survivor.visible).is_true()


func test_restoring_twice_is_harmless() -> void:
	var shown := _item(true)
	var snapshot := UiVisibilitySnapshot.hide_all([shown])
	snapshot.restore()
	snapshot.restore()
	assert_bool(shown.visible).is_true()


func test_an_empty_snapshot_restores_nothing() -> void:
	var snapshot := UiVisibilitySnapshot.hide_all([])
	assert_int(snapshot.size()).is_equal(0)
	snapshot.restore()


func test_the_runner_holds_no_visibility_flags_of_its_own() -> void:
	# Two fields per node was the growth pattern this replaced.
	var source := FileAccess.get_file_as_string("res://scripts/game/minigame_runner.gd")
	assert_str(source).is_not_empty()
	assert_bool(source.contains("_was_visible")).override_failure_message(
		"minigame_runner.gd tracks visibility in its own fields again"
	).is_false()
