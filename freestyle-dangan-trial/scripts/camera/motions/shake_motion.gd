extends CameraMotion
## Hands the camera to ScreenEffects for the duration.
##
## The shake writes global_position every frame from an origin captured when it
## started, so it is the motion that most needs to stop when superseded - and
## the one that could not. It is passed the context's cancellation check, and
## ScreenEffects returns without restoring when it fires: the camera belongs to
## whatever replaced this.

const DEFAULT_INTENSITY := 0.02

var _intensity: float


func _init(intensity: float = DEFAULT_INTENSITY) -> void:
	_intensity = intensity


func execute(ctx: CameraMotionContext) -> void:
	await ScreenEffects.screen_shake(ctx.duration, _intensity, ctx.is_abandoned)
