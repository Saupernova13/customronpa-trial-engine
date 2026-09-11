extends CameraMotion
## Roll over, hold, roll back. The three legs add up to the authored duration.

const TILT_RADIANS := deg_to_rad(15.0)


func execute(ctx: CameraMotionContext) -> void:
	var original_roll := ctx.camera.rotation.z
	var t := ctx.tween()
	t.tween_property(ctx.camera, "rotation:z", TILT_RADIANS, ctx.duration * 0.3)
	t.tween_interval(ctx.duration * 0.4)
	t.tween_property(ctx.camera, "rotation:z", original_roll, ctx.duration * 0.3)
	await ctx.wait(ctx.duration)
