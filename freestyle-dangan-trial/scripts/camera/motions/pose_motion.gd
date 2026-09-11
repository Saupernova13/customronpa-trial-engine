extends CameraMotion
## Move and rotate together to a pose: overhead and low_angle.
##
## The two differ only in whether the pose is where the camera should end up or
## how far it should shift from wherever it is, so they are built through the
## named constructors below rather than by passing a flag.

var _position: Vector3
var _rotation: Vector3
var _relative: bool


## overhead: a fixed vantage, wherever the camera was.
static func at(target_position: Vector3, target_rotation: Vector3) -> CameraMotion:
	var motion := new()
	motion._position = target_position
	motion._rotation = target_rotation
	motion._relative = false
	return motion


## low_angle: a shift from the current pose, in world space.
static func shifted_by(position_delta: Vector3, rotation_delta: Vector3) -> CameraMotion:
	var motion := new()
	motion._position = position_delta
	motion._rotation = rotation_delta
	motion._relative = true
	return motion


func execute(ctx: CameraMotionContext) -> void:
	var target_position := _position
	var target_rotation := _rotation
	if _relative:
		target_position += ctx.camera.global_position
		target_rotation += ctx.camera.rotation

	var t := ctx.tween()
	t.set_parallel(true)
	t.tween_property(ctx.camera, "global_position", target_position, ctx.duration)
	t.tween_property(ctx.camera, "rotation", target_rotation, ctx.duration)
	await ctx.wait(ctx.duration)
