extends CameraMotion
## Rotate in place by a fixed delta: the pan_*, tilt_* and rotate_* motions.
##
## Eight authored names, one motion. They persist for the line; the next
## speaking line's bench cut resets the camera.

var _delta: Vector3


func _init(delta_radians: Vector3) -> void:
	_delta = delta_radians


func execute(ctx: CameraMotionContext) -> void:
	var target := ctx.camera.rotation + _delta
	ctx.tween().tween_property(ctx.camera, "rotation", target, ctx.duration)
	await ctx.wait(ctx.duration)
