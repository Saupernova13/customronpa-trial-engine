@abstract
class_name CameraMotion
extends RefCounted
## One camera move, as an object the director can run and cancel.
##
## These carry state - a running tween, a loop part way through its duration -
## which is exactly what a Dictionary of Callables had nowhere to put. The
## supersede guard was therefore copy-pasted into four handlers, and the
## handlers that awaited rather than tweened were not cancellable at all.
##
## A motion returns when it is done or when its context is cancelled. It must
## not emit anything; the director decides whether a finished motion is still
## the current one.
##
## Motions are stateless between runs and are built once into the director's
## table, so `execute` must keep everything per-run in its own locals or on the
## context.


@abstract func execute(ctx: CameraMotionContext) -> void
