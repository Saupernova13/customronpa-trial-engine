extends Node
## Full-screen per-line effects: flash, fade, overlay text, shader filters.
## Rects, materials and animations are scene-owned in
## scenes/ui/screen_effects_overlay.tscn. Clips are authored one second long and
## stretched to the requested duration via `speed_scale`. Each rect owns an
## AnimationPlayer, so two effects on one line don't cancel.
##
## Camera effects (screen_shake, fov_pulse) stay in code: they need runtime
## Camera3D positions.

var _flash_rect: ColorRect
var _fade_rect: ColorRect
var _overlay_label: Label

# One mode-switched rect, driven by shaders/screen_filter.gdshader.
var _filter_rect: ColorRect
var _filter_material: ShaderMaterial

var _flash_anim: AnimationPlayer
var _fade_anim: AnimationPlayer
var _label_anim: AnimationPlayer
var _filter_anim: AnimationPlayer

const FILTER_MODES := {
	"grayscale": 0,
	"sepia": 1,
	"invert": 2,
	"scanlines": 3,
	"distortion": 4,
	"blur": 5,
}

var _effects: Dictionary = {}

func _ready():
	# The scene orders FilterRect below Flash/Fade/Label deliberately, so a
	# filter stays under the flash and fade layers rather than tinting them.
	var overlay := ResourceRegistry.instantiate("screen_effects_overlay")
	add_child(overlay)
	_flash_rect = overlay.get_node("%FlashRect")
	_fade_rect = overlay.get_node("%FadeRect")
	_overlay_label = overlay.get_node("%OverlayLabel")
	_filter_rect = overlay.get_node("%FilterRect")
	_filter_material = _filter_rect.material
	_flash_anim = overlay.get_node("%FlashAnimator")
	_fade_anim = overlay.get_node("%FadeAnimator")
	_label_anim = overlay.get_node("%LabelAnimator")
	_filter_anim = overlay.get_node("%FilterAnimator")

	_register_effects()

## Editor effect names and aliases -> handlers taking
## (intensity: float, duration: float, color: Color). A duration <= 0.0 means
## "use this effect's default". A new effect only needs an entry here.
func _register_effects() -> void:
	_register(["screen_shake", "shake"],
		func(i: float, d: float, _c: Color): screen_shake(d if d > 0.0 else 0.5, i * 0.04))
	_register(["white_flash", "flash"],
		func(_i: float, d: float, c: Color): color_flash(c, d if d > 0.0 else 0.3))
	# A per-line fade must resolve itself: out, hold, back in.
	_register(["screen_fade_black", "fade_black"],
		func(_i: float, d: float, _c: Color): fade_pulse(Color.BLACK, d if d > 0.0 else 1.0))
	_register(["screen_fade_white", "fade_white"],
		func(_i: float, d: float, _c: Color): fade_pulse(Color.WHITE, d if d > 0.0 else 1.0))
	_register(["pulse"],
		func(i: float, d: float, _c: Color): fov_pulse(i, d if d > 0.0 else 0.5))
	_register(["objection_overlay", "objection"],
		func(_i: float, _d: float, _c: Color): show_overlay_text("No, that's wrong!", Color(1.0, 0.3, 0.1), 1.5))
	_register(["blood_splatter"],
		func(_i: float, d: float, _c: Color): red_flash(d if d > 0.0 else 0.4))
	_register(["evidence_popup"],
		func(_i: float, _d: float, _c: Color): show_overlay_text("Evidence!", Color(0.3, 0.7, 1.0), 1.0))
	_register(["glitch_effect", "glitch"],
		func(_i: float, d: float, _c: Color): glitch_flash(d if d > 0.0 else 0.3))
	_register(["vignette"],
		func(i: float, d: float, _c: Color): vignette_pulse(d if d > 0.0 else 1.0, i))
	_register(["chromatic_aberration"],
		func(_i: float, d: float, _c: Color): chromatic_flash(d if d > 0.0 else 0.4))
	_register(["impact_frame"],
		func(_i: float, d: float, _c: Color): impact_frame(d if d > 0.0 else 0.3))
	for filter_name in FILTER_MODES:
		_register([filter_name], _run_filter.bind(filter_name))

func _register(names: Array, handler: Callable) -> void:
	for effect_name in names:
		_effects[effect_name] = handler

func _run_filter(intensity: float, duration: float, _color: Color, filter_name: String) -> void:
	play_filter(filter_name, intensity, duration if duration > 0.0 else 1.5)

func play_effects(effects_data: Dictionary):
	var effects_array = effects_data.get("effects", [])
	for effect in effects_array:
		var effect_type = ""
		var intensity = 0.5
		var duration = -1.0
		var color := Color.WHITE
		if effect is String:
			effect_type = effect
		elif effect is Dictionary:
			effect_type = effect.get("type", "")
			intensity = float(effect.get("intensity", 0.5))
			duration = float(effect.get("duration", -1.0))
			var raw_color = effect.get("color", "")
			if raw_color is String and not raw_color.is_empty():
				color = Color.from_string(raw_color, Color.WHITE)

		var handler: Callable = _effects.get(effect_type, Callable())
		if handler.is_valid():
			handler.call(intensity, duration, color)

## Clips are authored one second long; stretch one to `duration`.
func _play_for(player: AnimationPlayer, anim: String, duration: float) -> void:
	player.speed_scale = 1.0 / maxf(duration, 0.01)
	player.play(anim)

## Resolved per call, never latched: this autoload starts while the start menu is
## current and the start menu has no Camera3D, so a lookup at startup returns
## null for the rest of the session. Null when nothing is rendering a 3D view.
func _current_camera() -> Camera3D:
	return get_viewport().get_camera_3d()

## `is_abandoned` lets the caller stop this mid-shake. It matters because this
## is the one effect that writes the camera transform every frame from an
## origin captured when it started: CameraDirector cancels a superseded motion,
## and without a way to hear that, a shake kept dragging the camera back to a
## pre-supersede position for its full duration and then restored it there for
## good - discarding wherever the new motion had moved to.
##
## On abandonment it returns WITHOUT restoring, deliberately. The camera
## belongs to whatever replaced this shake; putting it back would be the bug.
func screen_shake(
	duration: float, intensity: float = 0.02, is_abandoned: Callable = Callable()
):
	var camera := _current_camera()
	if camera == null:
		Log.warn("ScreenEffects", "No current Camera3D; skipping screen shake.")
		return
	intensity *= Settings.screen_shake_intensity if Settings else 1.0
	if intensity <= 0.0:
		return
	var original_pos = camera.global_position
	# Seeded like everything else the session replays: the global RNG this used
	# is the one GameRandom does not drive.
	var rng := GameRandom.stream("screen_shake")
	var elapsed = 0.0
	while elapsed < duration:
		# A scene change mid-shake frees the camera under us, and the position
		# this was restoring belonged to a room that no longer exists.
		if not is_instance_valid(camera):
			return
		# Checked before the write, so once superseded this never touches the
		# camera again - not even for the frame it is being torn down in.
		if is_abandoned.is_valid() and is_abandoned.call():
			return
		var offset = Vector3(
			rng.randf_range(-intensity, intensity),
			rng.randf_range(-intensity, intensity),
			0.0
		)
		camera.global_position = original_pos + offset
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if is_instance_valid(camera):
		camera.global_position = original_pos

func white_flash(duration: float):
	color_flash(Color.WHITE, duration)

## Flash the screen with an arbitrary color (editor "flash" effect color picker).
func color_flash(color: Color, duration: float):
	_flash_rect.color = Color(color.r, color.g, color.b, _flash_rect.color.a)
	_play_for(_flash_anim, "flash", duration)

## Out, hold, back in, so the screen always recovers on its own.
func fade_pulse(color: Color, duration: float):
	_fade_rect.color = Color(color.r, color.g, color.b, _fade_rect.color.a)
	_fade_rect.modulate.a = 1.0
	_play_for(_fade_anim, "fade_pulse", duration)

## Used by the camera director's cut between benches.
func cross_dissolve(duration: float):
	fade_pulse(Color.BLACK, duration)
	await _fade_anim.animation_finished

## Intensity 0..1 maps to up to ~12 degrees of zoom punch.
func fov_pulse(intensity: float, duration: float):
	var camera := _current_camera()
	if camera == null:
		Log.warn("ScreenEffects", "No current Camera3D; skipping fov pulse.")
		return
	var original_fov = camera.fov
	var punch = clampf(intensity, 0.0, 1.0) * 12.0
	# Bound to the camera, so freeing it with its scene kills the tween too.
	var tween = camera.create_tween()
	tween.tween_property(camera, "fov", original_fov - punch, duration * 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(camera, "fov", original_fov, duration * 0.65) \
		.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)

func red_flash(duration: float):
	_play_for(_flash_anim, "flash_red", duration)

func show_overlay_text(text: String, color: Color, duration: float):
	_overlay_label.text = text
	_overlay_label.add_theme_color_override("font_color", color)
	_play_for(_label_anim, "overlay_text", duration)

func glitch_flash(duration: float):
	_play_for(_flash_anim, "flash_glitch", duration)

func chromatic_flash(duration: float):
	_play_for(_flash_anim, "flash_chromatic", duration)

## The clip peaks at full alpha; `intensity` scales it via the rect's modulate.
func vignette_pulse(duration: float, intensity: float = 0.5):
	_fade_rect.color = Color(0, 0, 0, _fade_rect.color.a)
	_fade_rect.modulate.a = clampf(0.15 + intensity * 0.5, 0.0, 0.8)
	_play_for(_fade_anim, "vignette_pulse", duration)

## The in/hold/out shape is the filter_pulse clip's `envelope` track;
## `intensity` sets the peak strength.
func play_filter(filter_name: String, intensity: float, duration: float):
	if not _filter_material or not FILTER_MODES.has(filter_name):
		return
	var strength = clampf(intensity, 0.0, 1.0)
	# These read as broken rather than subtle when faint.
	if filter_name in ["invert", "scanlines", "sepia", "grayscale"]:
		strength = maxf(strength, 0.6)

	_filter_material.set_shader_parameter("mode", FILTER_MODES[filter_name])
	_filter_material.set_shader_parameter("intensity", strength)
	_play_for(_filter_anim, "filter_pulse", duration)

func impact_frame(duration: float):
	_flash_rect.color = Color(1, 1, 1, _flash_rect.color.a)
	TimeScale.request(&"impact_frame", 0.1)
	await get_tree().create_timer(duration * 0.1).timeout
	# Releasing rather than assigning 1.0: focus mode or slow-time may be held
	# through the impact, and that request has to survive it.
	TimeScale.release(&"impact_frame")
	_play_for(_flash_anim, "flash", 0.2)
