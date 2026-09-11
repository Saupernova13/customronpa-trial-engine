extends CameraMotion
## zoom_in and zoom_out: tween the field of view to a fixed target.

var _target_fov: float


func _init(target_fov: float) -> void:
	_target_fov = target_fov


func execute(ctx: CameraMotionContext) -> void:
	ctx.tween().tween_property(ctx.camera, "fov", _target_fov, ctx.duration)
	await ctx.wait(ctx.duration)
