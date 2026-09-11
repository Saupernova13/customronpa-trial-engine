extends CameraMotion
## A smooth move to the speaker's bench, held for the authored duration.
##
## "pan" and "tracking" are this same motion; they were two identical handlers.
## The bench rig owns the interpolation, so there is nothing to tween here -
## only the wait, which is what makes the motion take the time it was given.


func execute(ctx: CameraMotionContext) -> void:
	ctx.jump_to_bench(true)
	await ctx.wait(ctx.duration)
