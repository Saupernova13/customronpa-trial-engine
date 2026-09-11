extends CameraMotion
## "none" and "split_screen": nothing to do, report immediately.
##
## split_screen is authorable in the editor but has no implementation; it lands
## here rather than falling through to the unknown-type default so that adding
## one later has an obvious home.


func execute(_ctx: CameraMotionContext) -> void:
	pass
