extends CameraMotion
## Cut in on the speaker, punch the fov, then rattle: 60% zoom, 40% shake.

const PUNCH_FOV := 20.0
const SHAKE_INTENSITY := 0.015

const ShakeMotion := preload("res://scripts/camera/motions/shake_motion.gd")


func execute(ctx: CameraMotionContext) -> void:
	ctx.jump_to_bench(true)

	var zoom_seconds := ctx.duration * 0.6
	var t := ctx.tween()
	t.set_ease(Tween.EASE_OUT)
	t.set_trans(Tween.TRANS_BACK)
	t.tween_property(ctx.camera, "fov", PUNCH_FOV, zoom_seconds)
	await ctx.wait(zoom_seconds)
	if ctx.is_abandoned():
		return

	# The second half used to be reached through the tween's `finished`
	# callback, which a kill suppresses - so a superseded dramatic zoom was
	# half-cancelled, and a completed one started a shake that captured its own
	# supersede generation rather than this motion's.
	await ShakeMotion.new(SHAKE_INTENSITY).execute(_tail(ctx))


## The same context with the shake's share of the duration.
func _tail(ctx: CameraMotionContext) -> CameraMotionContext:
	ctx.duration = ctx.duration * 0.4
	return ctx
