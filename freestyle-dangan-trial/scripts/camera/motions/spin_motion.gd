extends CameraMotion
## A full revolution that ends where it started.
##
## The reset is only applied if the spin was allowed to finish. Under the old
## tween-only cancellation a killed spin suppressed its `finished` callback, so
## the camera was left at whatever partial angle it had reached and the next
## relative rotation stacked on top of that.


func execute(ctx: CameraMotionContext) -> void:
	var start_rotation := ctx.camera.rotation.y
	ctx.tween().tween_property(
		ctx.camera, "rotation:y", start_rotation + TAU, ctx.duration
	)
	await ctx.wait(ctx.duration)
	if ctx.is_abandoned():
		return
	ctx.camera.rotation.y = start_rotation
