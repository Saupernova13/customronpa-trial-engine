extends CameraMotion
## Fade out and back in over the cut. Touches the overlay, never the camera, so
## being superseded costs nothing beyond not reporting completion.


func execute(ctx: CameraMotionContext) -> void:
	await ScreenEffects.cross_dissolve(ctx.duration)
