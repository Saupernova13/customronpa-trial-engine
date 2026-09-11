extends Node
## Runs one camera motion at a time, and cancels the one it replaces.
##
## The newest line's camera direction is the one the author meant to see, so a
## new motion supersedes the running one rather than queueing behind it.
##
## Cancellation is the context's, not each motion's. It used to be
## `_active_tween.kill()` here plus a hand-copied generation guard in four of
## the handlers - which covered the tweened motions and missed the ones that
## await, so a superseded shake or cross-dissolve carried on and a fifth
## handler that forgot the guard was silently wrong.

const CameraMotionContext := preload("res://scripts/camera/camera_motion_context.gd")

const NoOpMotion := preload("res://scripts/camera/motions/no_op_motion.gd")
const CutMotion := preload("res://scripts/camera/motions/cut_motion.gd")
const BenchHoldMotion := preload("res://scripts/camera/motions/bench_hold_motion.gd")
const FovMotion := preload("res://scripts/camera/motions/fov_motion.gd")
const RotateMotion := preload("res://scripts/camera/motions/rotate_motion.gd")
const TranslateMotion := preload("res://scripts/camera/motions/translate_motion.gd")
const PoseMotion := preload("res://scripts/camera/motions/pose_motion.gd")
const SpinMotion := preload("res://scripts/camera/motions/spin_motion.gd")
const DutchTiltMotion := preload("res://scripts/camera/motions/dutch_tilt_motion.gd")
const ResetMotion := preload("res://scripts/camera/motions/reset_motion.gd")
const ShakeMotion := preload("res://scripts/camera/motions/shake_motion.gd")
const DramaticZoomMotion := preload("res://scripts/camera/motions/dramatic_zoom_motion.gd")
const CrossDissolveMotion := preload("res://scripts/camera/motions/cross_dissolve_motion.gd")

## No production listener - motions are fire-and-forget - but it is the only
## way to observe that one finished, and test_camera_director depends on it.
signal motion_completed

var _camera: Camera3D
var _bench_camera: Node
var _rest_fov: float = 30.0
var _rest_position: Vector3

## The running motion's context, and the handle that cancels it.
var _active_context: CameraMotionContext = null

## The web editor's camera tab -> motions, built once in _ready().
var _motions: Dictionary = {}


func _ready() -> void:
	_register_motions()


## Editor motion names -> the object that performs them. A new motion needs one
## entry here; a variant of an existing one needs only different arguments.
func _register_motions() -> void:
	# pan and tracking are the same motion, not two that happen to match.
	var bench_hold := BenchHoldMotion.new()
	_motions = {
		"none": NoOpMotion.new(),
		"split_screen": NoOpMotion.new(),
		"cut": CutMotion.new(),
		"pan": bench_hold,
		"tracking": bench_hold,
		"zoom_in": FovMotion.new(20.0),
		"zoom_out": FovMotion.new(60.0),
		"shake": ShakeMotion.new(),
		"dramatic_zoom": DramaticZoomMotion.new(),
		"spin": SpinMotion.new(),
		"overhead": PoseMotion.at(Vector3(0, 2.0, 0), Vector3(-PI / 2, 0, 0)),
		"low_angle": PoseMotion.shifted_by(Vector3(0, -0.3, 0), Vector3(0.2, 0, 0)),
		# Pans and tilts rotate in place; trucks, pedestals and dollies
		# translate along the camera's own axes.
		"pan_left": RotateMotion.new(Vector3(0, deg_to_rad(15.0), 0)),
		"pan_right": RotateMotion.new(Vector3(0, deg_to_rad(-15.0), 0)),
		"pan_up": RotateMotion.new(Vector3(deg_to_rad(10.0), 0, 0)),
		"pan_down": RotateMotion.new(Vector3(deg_to_rad(-10.0), 0, 0)),
		"tilt_up": RotateMotion.new(Vector3(deg_to_rad(18.0), 0, 0)),
		"tilt_down": RotateMotion.new(Vector3(deg_to_rad(-18.0), 0, 0)),
		"rotate_cw": RotateMotion.new(Vector3(0, 0, deg_to_rad(-12.0))),
		"rotate_ccw": RotateMotion.new(Vector3(0, 0, deg_to_rad(12.0))),
		"truck_left": TranslateMotion.new(Vector3(-0.4, 0, 0)),
		"truck_right": TranslateMotion.new(Vector3(0.4, 0, 0)),
		"pedestal_up": TranslateMotion.new(Vector3(0, 0.3, 0)),
		"pedestal_down": TranslateMotion.new(Vector3(0, -0.3, 0)),
		# A Camera3D looks along its local -Z, so dollying in is negative z.
		# These were the other way round, and self-consistently so: the old
		# _execute_dolly negated `forward` and was then bound a negative
		# distance, and the two cancelled.
		"dolly_in": TranslateMotion.new(Vector3(0, 0, -0.5)),
		"dolly_out": TranslateMotion.new(Vector3(0, 0, 0.5)),
		"cross_dissolve": CrossDissolveMotion.new(),
		"dutch_tilt": DutchTiltMotion.new(),
		"reset": ResetMotion.new(),
	}


func execute_motion(motion_data: Dictionary, target_bench_index: int = -1) -> void:
	if not _resolve_camera():
		Log.warn("CameraDirector", "No current Camera3D; skipping camera motion.")
		motion_completed.emit()
		return

	if _active_context != null:
		_active_context.cancel()

	var easing := str(motion_data.get("easing", "ease-in-out"))
	var ctx := CameraMotionContext.new(_camera, _bench_camera, get_tree())
	ctx.bench_index = target_bench_index
	ctx.duration = float(motion_data.get("duration", 1.0))
	ctx.ease_type = _parse_ease(easing)
	ctx.trans_type = _parse_trans(easing)
	ctx.rest_fov = _rest_fov
	ctx.rest_position = _rest_position
	_active_context = ctx

	var motion: CameraMotion = _motions.get(str(motion_data.get("type", "none")))
	if motion == null:
		motion = _motions["none"]
	await motion.execute(ctx)

	# Reported only for the motion that is still current. Without this a
	# superseded one announces the motion that replaced it, and the caller
	# waiting on the signal unblocks early.
	if ctx.is_cancelled():
		return
	if _active_context == ctx:
		_active_context = null
	motion_completed.emit()


## Autoload _ready() runs while the main scene is current, and that is the start
## menu, which has no Camera3D - so latching one at startup left every motion a
## no-op for the whole session. The reference would dangle again after each
## change_scene_to_file, so resolve per call instead.
##
## The rest pose is re-captured whenever a different camera comes into view.
func _resolve_camera() -> bool:
	var cam: Camera3D = get_viewport().get_camera_3d()
	if cam == null:
		_camera = null
		_bench_camera = null
		return false
	if cam != _camera:
		_camera = cam
		_rest_fov = cam.fov
		_rest_position = cam.global_position
		_bench_camera = cam if cam.has_method("jump_to_bench") else null
	return true


func _parse_ease(easing: String) -> Tween.EaseType:
	match easing:
		"ease-in":
			return Tween.EASE_IN
		"ease-out":
			return Tween.EASE_OUT
		_:
			return Tween.EASE_IN_OUT


func _parse_trans(easing: String) -> Tween.TransitionType:
	if easing == "linear":
		return Tween.TRANS_LINEAR
	return Tween.TRANS_CUBIC
