extends CameraMotion
## Back to the fov the camera was found with, and level. The rest pose is
## re-read whenever a different camera becomes current, so this returns to what
## the trial authored rather than to whatever a preceding zoom left behind.


func execute(ctx: CameraMotionContext) -> void:
	var t := ctx.tween()
	t.set_parallel(true)
	t.tween_property(ctx.camera, "fov", ctx.rest_fov, ctx.duration)
	t.tween_property(ctx.camera, "rotation:z", 0.0, ctx.duration)
	await ctx.wait(ctx.duration)
