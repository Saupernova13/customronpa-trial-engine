extends GdUnitTestSuite
## CameraDirector must resolve the current Camera3D per call. The autoload's
## _ready() runs while the main scene is current, and that is the start menu,
## which has no Camera3D - so a camera that only appears later, as the trial
## room's does, still has to be found.

const MOTION_DURATION := 0.05


## Connects before executing: the no-camera path emits motion_completed
## synchronously, so a listener attached afterwards would never see it.
func _run_motion(motion: Dictionary) -> int:
	var completions: Array[int] = [0]
	var on_done := func() -> void: completions[0] += 1
	CameraDirector.motion_completed.connect(on_done)
	CameraDirector.execute_motion(motion)
	# Bounded rather than open-ended, so a regression fails instead of hanging.
	for _i in range(120):
		if completions[0] > 0:
			break
		await get_tree().process_frame
	CameraDirector.motion_completed.disconnect(on_done)
	return completions[0]


func test_motion_drives_a_camera_that_appeared_after_startup() -> void:
	var camera: Camera3D = auto_free(Camera3D.new())
	camera.fov = 55.0
	add_child(camera)
	camera.make_current()
	await get_tree().process_frame

	assert_int(await _run_motion({"type": "zoom_in", "duration": MOTION_DURATION})).is_equal(1)
	# zoom_in tweens fov to 20; the latched-null bug left it untouched at 55.
	assert_float(camera.fov).is_equal_approx(20.0, 0.5)


func test_motion_completes_when_no_camera_is_current() -> void:
	# The signal is what unblocks ScriptDirector, so it must fire even here or
	# the trial stalls on any line authored with a camera motion.
	assert_object(get_viewport().get_camera_3d()).is_null()
	assert_int(await _run_motion({"type": "zoom_in", "duration": MOTION_DURATION})).is_equal(1)


func _camera(fov: float = 55.0) -> Camera3D:
	var camera: Camera3D = auto_free(Camera3D.new())
	camera.fov = fov
	add_child(camera)
	camera.make_current()
	return camera


func test_a_new_motion_supersedes_the_one_still_running() -> void:
	# Nothing waited or cancelled, so advancing the script mid-pan left two
	# tweens writing fov and the camera followed whichever wrote last that
	# frame. The second motion's target is the one that must win.
	var camera := _camera()
	await get_tree().process_frame

	CameraDirector.execute_motion({"type": "zoom_in", "duration": 5.0})
	await get_tree().process_frame
	CameraDirector.execute_motion({"type": "zoom_out", "duration": MOTION_DURATION})

	for _i in range(120):
		await get_tree().process_frame
		if is_equal_approx(camera.fov, 60.0):
			break
	# zoom_out targets 60; the abandoned zoom_in was heading for 20.
	assert_float(camera.fov).is_equal_approx(60.0, 0.5)

	# And it stays there. Reaching 60 proves only that the later tween wrote
	# last on some frame - with both alive, the 5s zoom_in keeps writing and
	# drags the camera back down after the short one has finished.
	for _i in range(30):
		await get_tree().process_frame
	assert_float(camera.fov).override_failure_message(
		"fov drifted to %s after the superseding motion finished" % camera.fov
	).is_equal_approx(60.0, 0.5)


func test_a_superseded_motion_does_not_report_completion() -> void:
	# motion_completed is what unblocks a waiting caller. The first tween's
	# `finished` used to fire while the second was still running, so the
	# signal announced a motion that had not happened.
	# The node itself is not read; it has to exist and be current.
	_camera()
	await get_tree().process_frame

	var completions: Array[int] = [0]
	var on_done := func() -> void: completions[0] += 1
	CameraDirector.motion_completed.connect(on_done)

	CameraDirector.execute_motion({"type": "pan", "duration": 0.2})
	await get_tree().process_frame
	CameraDirector.execute_motion({"type": "cut", "duration": MOTION_DURATION})

	# Long enough for the abandoned pan's timer to have expired.
	for _i in range(60):
		await get_tree().process_frame
	CameraDirector.motion_completed.disconnect(on_done)

	assert_int(completions[0]).override_failure_message(
		"motion_completed fired %d times for two motions, one of them superseded"
		% completions[0]
	).is_equal(1)


func test_back_to_back_motions_each_report_once() -> void:
	# The guard must not swallow completions for motions that ran to the end.
	# The node itself is not read; it has to exist and be current.
	_camera()
	await get_tree().process_frame

	assert_int(await _run_motion({"type": "zoom_in", "duration": MOTION_DURATION})).is_equal(1)
	assert_int(await _run_motion({"type": "zoom_out", "duration": MOTION_DURATION})).is_equal(1)


# ---------------------------------------------------------------------------
# Cancellation reaches the motions that await, not only the ones that tween.
# ---------------------------------------------------------------------------
## Restores whatever the shake intensity setting was: the shake is a no-op at
## zero, so these would pass vacuously on a machine whose player turned it off.
func _with_shake_enabled() -> float:
	var prior: float = Settings.screen_shake_intensity
	Settings.screen_shake_intensity = 1.0
	return prior


func test_a_superseded_shake_stops_writing_the_camera() -> void:
	# Cancellation was `_active_tween.kill()`, and a shake sets no tween - so
	# nothing stopped it. It kept writing global_position from the origin it
	# captured before the supersede, then restored the camera to it on the way
	# out, discarding wherever the motion that replaced it had moved to.
	var prior := _with_shake_enabled()
	var camera := _camera()
	camera.global_position = Vector3.ZERO
	await get_tree().process_frame

	CameraDirector.execute_motion({"type": "shake", "duration": 0.6})
	await get_tree().process_frame
	await get_tree().process_frame
	CameraDirector.execute_motion({"type": "truck_right", "duration": MOTION_DURATION})

	# Well past the abandoned shake's own duration, so its restore would have
	# run by now if it were still going to.
	for _i in range(90):
		await get_tree().process_frame

	Settings.screen_shake_intensity = prior
	assert_float(camera.global_position.x).override_failure_message(
		"camera ended at x=%s; truck_right targeted 0.4" % camera.global_position.x
	).is_equal_approx(0.4, 0.05)


func test_a_superseded_shake_does_not_report_completion() -> void:
	var prior := _with_shake_enabled()
	_camera()
	await get_tree().process_frame

	var completions: Array[int] = [0]
	var on_done := func() -> void: completions[0] += 1
	CameraDirector.motion_completed.connect(on_done)

	CameraDirector.execute_motion({"type": "shake", "duration": 0.4})
	await get_tree().process_frame
	CameraDirector.execute_motion({"type": "cut", "duration": MOTION_DURATION})

	for _i in range(60):
		await get_tree().process_frame
	CameraDirector.motion_completed.disconnect(on_done)
	Settings.screen_shake_intensity = prior

	assert_int(completions[0]).override_failure_message(
		"motion_completed fired %d times for two motions, one superseded" % completions[0]
	).is_equal(1)


func test_a_shake_that_runs_to_the_end_still_restores_the_camera() -> void:
	# The cancellation path must not cost the uncancelled one its restore.
	var prior := _with_shake_enabled()
	var camera := _camera()
	camera.global_position = Vector3(1.0, 2.0, 3.0)
	await get_tree().process_frame

	assert_int(await _run_motion({"type": "shake", "duration": 0.1})).is_equal(1)
	Settings.screen_shake_intensity = prior
	assert_vector(camera.global_position).is_equal_approx(Vector3(1.0, 2.0, 3.0), Vector3.ONE * 0.01)


func test_a_superseded_dramatic_zoom_leaves_the_fov_to_its_replacement() -> void:
	# Its two halves used to be joined by the zoom tween's `finished`, which a
	# kill suppresses - so the shake half never ran, and the coroutine waiting
	# on that signal was stranded holding the camera.
	var prior := _with_shake_enabled()
	var camera := _camera(55.0)
	await get_tree().process_frame

	CameraDirector.execute_motion({"type": "dramatic_zoom", "duration": 2.0})
	await get_tree().process_frame
	CameraDirector.execute_motion({"type": "zoom_out", "duration": MOTION_DURATION})

	for _i in range(90):
		await get_tree().process_frame

	Settings.screen_shake_intensity = prior
	# zoom_out targets 60; the abandoned dramatic zoom was heading for 20.
	assert_float(camera.fov).override_failure_message(
		"fov ended at %s; zoom_out targeted 60" % camera.fov
	).is_equal_approx(60.0, 0.5)


# ---------------------------------------------------------------------------
# The motion table. Every entry has to build and run; before these were
# objects, a typo in a bind() was only found by authoring a trial that used it.
# ---------------------------------------------------------------------------
func test_every_registered_motion_runs_and_reports_once() -> void:
	var prior := _with_shake_enabled()
	_camera()
	await get_tree().process_frame

	for motion_type in CameraDirector._motions:
		var completions := await _run_motion(
			{"type": motion_type, "duration": MOTION_DURATION}
		)
		assert_int(completions).override_failure_message(
			"'%s' reported %d completions" % [motion_type, completions]
		).is_equal(1)
	Settings.screen_shake_intensity = prior


func test_pan_and_tracking_are_the_same_motion() -> void:
	# They were two identical handlers. Sharing the instance is what stops them
	# drifting apart again.
	assert_object(CameraDirector._motions["pan"]).is_same(CameraDirector._motions["tracking"])


func test_an_unknown_motion_type_still_reports_completion() -> void:
	# The signal is what unblocks a waiting caller, and a trial from a newer
	# minor can name a motion this build has never heard of.
	_camera()
	await get_tree().process_frame
	assert_int(await _run_motion({"type": "warp_drive", "duration": MOTION_DURATION})).is_equal(1)


func test_a_relative_rotation_is_applied_from_where_the_camera_is() -> void:
	var camera := _camera()
	camera.rotation = Vector3(0.0, 1.0, 0.0)
	await get_tree().process_frame

	assert_int(await _run_motion({"type": "pan_left", "duration": MOTION_DURATION})).is_equal(1)
	assert_float(camera.rotation.y).is_equal_approx(1.0 + deg_to_rad(15.0), 0.01)


func test_a_truck_moves_along_the_cameras_own_right_axis() -> void:
	var camera := _camera()
	camera.global_position = Vector3.ZERO
	camera.rotation = Vector3(0.0, PI / 2.0, 0.0)
	await get_tree().process_frame

	assert_int(await _run_motion({"type": "truck_right", "duration": MOTION_DURATION})).is_equal(1)
	# Yawed 90 degrees, the camera's right points down -Z in world space.
	assert_float(camera.global_position.z).is_equal_approx(-0.4, 0.05)


# ---------------------------------------------------------------------------
# Which way each local-axis motion actually goes.
#
# dolly_in used to move the camera backwards: it was bound to a negative
# distance against a `forward` that was already negated, so the two cancelled.
# The truck and pedestal beside it went through a different function and were
# right, which is why the pair read as correct. These pin all six, so the next
# person editing this table cannot quietly swap another one.
# ---------------------------------------------------------------------------
func _after_motion(motion_type: String) -> Camera3D:
	var camera := _camera()
	camera.global_position = Vector3.ZERO
	camera.rotation = Vector3.ZERO
	await get_tree().process_frame
	assert_int(await _run_motion({"type": motion_type, "duration": MOTION_DURATION})).is_equal(1)
	return camera


func test_dolly_in_moves_towards_what_the_camera_is_looking_at() -> void:
	# A Camera3D looks along its local -Z, so moving in means negative z.
	var camera := await _after_motion("dolly_in")
	assert_float(camera.global_position.z).override_failure_message(
		"dolly_in ended at z=%s; moving in means negative z" % camera.global_position.z
	).is_equal_approx(-0.5, 0.05)


func test_dolly_out_moves_away_from_what_the_camera_is_looking_at() -> void:
	var camera := await _after_motion("dolly_out")
	assert_float(camera.global_position.z).is_equal_approx(0.5, 0.05)


func test_truck_left_and_right_move_along_the_world_x_axis_unrotated() -> void:
	assert_float((await _after_motion("truck_left")).global_position.x).is_equal_approx(-0.4, 0.05)
	assert_float((await _after_motion("truck_right")).global_position.x).is_equal_approx(0.4, 0.05)


func test_pedestal_up_and_down_move_along_the_world_y_axis_unrotated() -> void:
	assert_float((await _after_motion("pedestal_up")).global_position.y).is_equal_approx(0.3, 0.05)
	assert_float((await _after_motion("pedestal_down")).global_position.y).is_equal_approx(-0.3, 0.05)
