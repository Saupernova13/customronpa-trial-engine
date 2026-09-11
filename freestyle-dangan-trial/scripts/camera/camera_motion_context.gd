class_name CameraMotionContext
extends RefCounted
## Everything one camera motion is allowed to touch, plus the one thing that
## can stop it.
##
## The director hands a fresh context to each motion and cancels the previous
## one. That is the whole cancellation mechanism, and it lives here rather than
## in the motions so that a motion cannot forget to be cancellable.
##
## Cancellation used to be `_active_tween.kill()` and nothing else, so it
## reached only the motions that drive a Tween. The three that await instead -
## shake, cross_dissolve, and the shake half of dramatic_zoom - were not
## cancellable at all: a superseded shake went on writing global_position from
## a pre-supersede origin for its full duration and then restored the camera to
## it, discarding wherever the new motion had moved to.

var camera: Camera3D
## The bench rig, when the current camera is one. Null in the start menu, in
## tests, and anywhere else a plain Camera3D is current.
var bench_camera: Node
var bench_index: int
var duration: float
var ease_type: Tween.EaseType
var trans_type: Tween.TransitionType
## The fov and position the camera was found with, so `reset` returns to what
## the trial authored rather than to whatever a preceding zoom left behind.
var rest_fov: float
var rest_position: Vector3

var _tree: SceneTree
var _cancelled: bool = false
var _tweens: Array[Tween] = []


func _init(p_camera: Camera3D, p_bench_camera: Node, p_tree: SceneTree) -> void:
	camera = p_camera
	bench_camera = p_bench_camera
	_tree = p_tree


## Bound to the camera, so freeing it with its scene kills the tween too.
## Registered here, so cancel() reaches it without the motion doing anything.
func tween() -> Tween:
	var t := camera.create_tween()
	t.set_ease(ease_type)
	t.set_trans(trans_type)
	_tweens.append(t)
	return t


## True once a newer motion has taken the camera. Something that awaits must
## check this afterwards and stop writing - without restoring anything, since
## the camera now belongs to the motion that replaced it.
func is_cancelled() -> bool:
	return _cancelled


## Also true when the camera has gone: a scene change mid-motion frees it, and
## the transform a motion was about to restore belongs to a room that no longer
## exists.
func is_abandoned() -> bool:
	return _cancelled or not is_instance_valid(camera)


func cancel() -> void:
	_cancelled = true
	for t in _tweens:
		if t != null and t.is_valid():
			t.kill()
	_tweens.clear()


## Waits out a motion's own duration, returning the moment it is superseded.
##
## Deliberately not `await tween.finished`: killing a Tween suppresses that
## signal, so a cancelled motion awaiting it would never resume and its
## coroutine - and the director's, which awaits the motion - would be stranded
## holding the camera.
func wait(seconds: float) -> void:
	if seconds <= 0.0 or _tree == null:
		return
	var timer := _tree.create_timer(seconds)
	while timer.time_left > 0.0:
		if is_abandoned():
			return
		await _tree.process_frame


## True when a bench jump is possible and asked for. The index is -1 for a line
## that names no speaker.
func can_jump_to_bench() -> bool:
	return bench_camera != null and bench_index >= 0


func jump_to_bench(smooth: bool) -> void:
	if can_jump_to_bench():
		bench_camera.jump_to_bench(bench_index, smooth)
