extends CameraMotion
## Move along the camera's own axes by a fixed offset: the truck_*, pedestal_*
## and dolly_* motions.
##
## x is right, y is up, z is back - a Camera3D looks along its local -Z.
##
## The dolly offsets are the ones that look wrong, and are: dolly_in is bound
## to +z, which moves the camera backwards. That is the behaviour this replaced
## and it is preserved here deliberately, so this refactor changes nothing an
## author can see. See #282, which fixes it on its own.

var _local_offset: Vector3


func _init(local_offset: Vector3) -> void:
	_local_offset = local_offset


func execute(ctx: CameraMotionContext) -> void:
	var basis := ctx.camera.global_transform.basis
	var world_offset := (
		basis.x * _local_offset.x + basis.y * _local_offset.y + basis.z * _local_offset.z
	)
	var target := ctx.camera.global_position + world_offset
	ctx.tween().tween_property(ctx.camera, "global_position", target, ctx.duration)
	await ctx.wait(ctx.duration)
