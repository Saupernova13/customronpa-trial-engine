extends Node
## User preferences, declared once each and persisted to user://.
##
## Every setting used to be written out four times: a DEFAULT_ constant, a
## property with its own clamp, a typed read in _load_settings(), and a
## set_value in _save_settings(). Six settings meant two dozen places holding a
## section name, a key name or a bound - and a setting added to the first three
## but not the fourth read its default on every launch while reporting nothing,
## because the file loads fine, the key is simply absent, and the reader
## returns the fallback exactly as designed.
##
## SPECS is the single declaration; load and save iterate it. The properties
## stay, because they are the public API settings_menu binds to, but their
## bounds come from the spec rather than restating it.

const SAVE_PATH = "user://settings.cfg"

## Typewriter presets, addressed by text_speed. One row per speed, so a new one
## cannot reach the speed lookup and miss the name lookup - those were two
## parallel match statements over the same int, free to disagree.
const TEXT_SPEEDS := [
	{"name": "Slow", "chars_per_second": 15.0},
	{"name": "Normal", "chars_per_second": 30.0},
	{"name": "Fast", "chars_per_second": 60.0},
	# Not a speed so much as "no typewriter": DialogueBox reveals the whole
	# line at once at anything this large.
	{"name": "Instant", "chars_per_second": 999.0},
]

## Stated once, so a per-key fallback and the initial value cannot drift apart.
const DEFAULT_TEXT_SPEED := 1
const DEFAULT_VOICE_VOLUME := 1.0
const DEFAULT_AUTO_ADVANCE := false
const DEFAULT_AUTO_ADVANCE_DELAY := 2.0
const DEFAULT_SCREEN_SHAKE := 1.0
const DEFAULT_UI_SCALE := 1.0

## One row per setting: where it lives in the file, what it is, what it
## defaults to and what bounds it. Adding a setting means adding a row and a
## property; load and save follow on their own.
##
## text_speed's bound is pinned to TEXT_SPEEDS.size() by test_settings_spec,
## because GDScript will not let a const call size().
const SPECS := {
	"text_speed":
	{"section": "gameplay", "type": TYPE_INT, "default": DEFAULT_TEXT_SPEED, "min": 0, "max": 3},
	"voice_volume":
	{
		"section": "audio",
		"type": TYPE_FLOAT,
		"default": DEFAULT_VOICE_VOLUME,
		"min": 0.0,
		"max": 1.0,
	},
	"auto_advance": {"section": "gameplay", "type": TYPE_BOOL, "default": DEFAULT_AUTO_ADVANCE},
	"auto_advance_delay":
	{
		"section": "gameplay",
		"type": TYPE_FLOAT,
		"default": DEFAULT_AUTO_ADVANCE_DELAY,
		"min": 0.5,
		"max": 6.0,
	},
	"screen_shake_intensity":
	{
		"section": "gameplay",
		"type": TYPE_FLOAT,
		"default": DEFAULT_SCREEN_SHAKE,
		"min": 0.0,
		"max": 2.0,
	},
	# Bounded so the UI can go neither off-screen nor illegibly small.
	"ui_scale":
	{
		"section": "display",
		"type": TYPE_FLOAT,
		"default": DEFAULT_UI_SCALE,
		"min": 0.75,
		"max": 2.0,
	},
}

## Long enough to collapse a slider drag, short enough that a player who quits
## straight after a change almost never outruns it - and flush_pending_save
## covers the case where they do.
const SAVE_DEBOUNCE_SECONDS := 0.5

var text_speed: int = DEFAULT_TEXT_SPEED:
	set(val):
		text_speed = _bounded_int("text_speed", val)
		_apply_and_save()

var voice_volume: float = DEFAULT_VOICE_VOLUME:
	set(val):
		voice_volume = _bounded_float("voice_volume", val)
		_apply_and_save()

var auto_advance: bool = DEFAULT_AUTO_ADVANCE:
	set(val):
		auto_advance = val
		_apply_and_save()

var auto_advance_delay: float = DEFAULT_AUTO_ADVANCE_DELAY:
	set(val):
		auto_advance_delay = _bounded_float("auto_advance_delay", val)
		_apply_and_save()

var screen_shake_intensity: float = DEFAULT_SCREEN_SHAKE:
	set(val):
		screen_shake_intensity = _bounded_float("screen_shake_intensity", val)
		_apply_and_save()

var ui_scale: float = DEFAULT_UI_SCALE:
	set(val):
		ui_scale = _bounded_float("ui_scale", val)
		_apply_and_save()

var _suppress_save: bool = false
var _save_timer: Timer = null


func _ready():
	_load_settings()
	# Cleared here rather than at the end of _load_settings(). A runtime type
	# error inside a setter aborts the enclosing function and returns to its
	# caller, so a single bad value used to leave this true and suppress every
	# save for the rest of the process.
	_suppress_save = false
	_apply_all()


static func _bounded_int(key: String, value: int) -> int:
	var spec: Dictionary = SPECS[key]
	return clampi(value, int(spec["min"]), int(spec["max"]))


static func _bounded_float(key: String, value: float) -> float:
	var spec: Dictionary = SPECS[key]
	return clampf(value, float(spec["min"]), float(spec["max"]))


func _load_settings():
	var config := ConfigFile.new()
	var err := config.load(SAVE_PATH)
	if err == ERR_FILE_NOT_FOUND:
		# First run. The defaults stand and the next change writes the file.
		return
	if err != OK:
		Log.warn(
			"Settings",
			"Could not read %s (%s); using defaults." % [SAVE_PATH, error_string(err)]
		)
		return

	_suppress_save = true
	for key in SPECS:
		set(key, _read(config, key))
	_suppress_save = false


## Type-checked per key: ConfigFile stores arbitrary Variants, and a
## hand-edited or half-written file must cost one setting, not all of them.
func _read(config: ConfigFile, key: String) -> Variant:
	var spec: Dictionary = SPECS[key]
	var fallback: Variant = spec["default"]
	var value: Variant = config.get_value(spec["section"], key, fallback)
	match int(spec["type"]):
		TYPE_BOOL:
			if value is bool:
				return value
		TYPE_INT:
			if value is int or value is float:
				return int(value)
		TYPE_FLOAT:
			if value is int or value is float:
				return float(value)
	_warn_bad_value(str(spec["section"]), key, value)
	return fallback


## ConfigFile.save() is not atomic, so a crash mid-write leaves a file that
## parses but holds the wrong types. The player cannot be expected to find it.
func _warn_bad_value(section: String, key: String, value: Variant) -> void:
	Log.warn(
		"Settings",
		"%s/%s in %s is a %s; using the default." % [
			section, key, SAVE_PATH, type_string(typeof(value))
		]
	)


func _save_settings():
	var config = ConfigFile.new()
	for key in SPECS:
		config.set_value(SPECS[key]["section"], key, get(key))
	# A read-only or full user:// would otherwise mean settings never persist,
	# with nothing said about it at any level.
	var err := config.save(SAVE_PATH)
	if err != OK:
		Log.warn("Settings", "Could not write %s: %s" % [SAVE_PATH, error_string(err)])


## Applying is immediate so the UI stays responsive; only the write is
## debounced. settings_menu wires slider.value_changed straight to these
## setters, so one drag of the volume slider used to write user://settings.cfg
## dozens of times a second - real flash wear on Android, and avoidable frame
## cost during an interaction that should be smooth.
func _apply_and_save():
	if _suppress_save:
		return
	_apply_all()
	_schedule_save()


func _schedule_save() -> void:
	if _save_timer == null:
		_save_timer = Timer.new()
		_save_timer.one_shot = true
		# Settings changes must land even while the tree is paused: the menu is
		# open, which is exactly when the trial is paused.
		_save_timer.process_mode = Node.PROCESS_MODE_ALWAYS
		_save_timer.timeout.connect(_save_settings)
		add_child(_save_timer)
	_save_timer.start(SAVE_DEBOUNCE_SECONDS)


## Writes anything the debounce is still holding. Quitting mid-drag would
## otherwise lose the change the player just made.
func flush_pending_save() -> void:
	if _save_timer and not _save_timer.is_stopped():
		_save_timer.stop()
		_save_settings()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		flush_pending_save()


func _apply_all():
	if AudioManager:
		AudioManager.set_voice_volume_linear(voice_volume)
	# Sits on top of the canvas_items/expand stretch, which already fills the
	# window, so the player can size the UI independently of it.
	var window := get_window()
	if window:
		window.content_scale_factor = ui_scale


func _text_speed_preset() -> Dictionary:
	return TEXT_SPEEDS[clampi(text_speed, 0, TEXT_SPEEDS.size() - 1)]


func get_typewriter_speed() -> float:
	return float(_text_speed_preset()["chars_per_second"])


func get_text_speed_name() -> String:
	return str(_text_speed_preset()["name"])
