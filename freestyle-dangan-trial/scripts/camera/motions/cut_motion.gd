extends CameraMotion
## A hard cut to the speaker's bench. Instant by definition, so it ignores the
## authored duration.


func execute(ctx: CameraMotionContext) -> void:
	ctx.jump_to_bench(false)
