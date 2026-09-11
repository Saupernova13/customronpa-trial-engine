extends GdUnitTestSuite
## The settings spec is the single declaration, and load and save follow it.
##
## Each setting used to be written out four times - a default constant, a
## property with its own clamp, a typed read, and a set_value. A setting added
## to the first three but not the fourth read its default on every launch and
## reported nothing: the file loads fine, the key is simply absent, and the
## reader returns the fallback exactly as designed. There was no test, warning
## or lint that could catch it. This suite is that check.

const BACKUP_PATH := "user://gdunit_settings_spec_backup.cfg"

var _had_backup: bool = false


## The autoload reads a fixed path, so the real file is set aside and restored
## rather than worked around.
func before_test() -> void:
	_had_backup = FileAccess.file_exists(Settings.SAVE_PATH)
	if _had_backup:
		DirAccess.copy_absolute(Settings.SAVE_PATH, BACKUP_PATH)


func after_test() -> void:
	if _had_backup:
		DirAccess.copy_absolute(BACKUP_PATH, Settings.SAVE_PATH)
		DirAccess.remove_absolute(BACKUP_PATH)
	else:
		DirAccess.remove_absolute(Settings.SAVE_PATH)
	Settings._ready()


# ---------------------------------------------------------------------------
# The spec describes the properties that exist
# ---------------------------------------------------------------------------
func test_every_spec_key_is_a_real_property() -> void:
	var names := {}
	for property in Settings.get_property_list():
		names[property["name"]] = true
	for key in Settings.SPECS:
		assert_bool(names.has(key)).override_failure_message(
			"SPECS declares '%s', which is not a property" % key
		).is_true()


func test_every_spec_row_is_complete() -> void:
	for key in Settings.SPECS:
		var spec: Dictionary = Settings.SPECS[key]
		for field in ["section", "type", "default"]:
			assert_bool(spec.has(field)).override_failure_message(
				"'%s' has no %s" % [key, field]
			).is_true()
		# Bounds come in pairs or not at all; a lone one would clamp against a
		# missing value.
		assert_bool(spec.has("min")).override_failure_message(
			"'%s' declares only one bound" % key
		).is_equal(spec.has("max"))


func test_every_default_matches_its_property_type() -> void:
	for key in Settings.SPECS:
		var spec: Dictionary = Settings.SPECS[key]
		assert_int(typeof(spec["default"])).override_failure_message(
			"'%s' defaults to a %s but is declared %s"
			% [key, type_string(typeof(spec["default"])), type_string(spec["type"])]
		).is_equal(spec["type"])


func test_a_default_sits_inside_its_own_bounds() -> void:
	for key in Settings.SPECS:
		var spec: Dictionary = Settings.SPECS[key]
		if not spec.has("min"):
			continue
		var value := float(spec["default"])
		assert_bool(value >= float(spec["min"]) and value <= float(spec["max"])) \
			.override_failure_message("'%s' defaults outside its own bounds" % key) \
			.is_true()


# ---------------------------------------------------------------------------
# Load and save are derived from it
# ---------------------------------------------------------------------------
func test_every_spec_key_round_trips_through_the_file() -> void:
	# The failure this catches: a setting wired into load but not save reads
	# its default on every launch, silently.
	Settings._ready()
	var written := {}
	for key in Settings.SPECS:
		var spec: Dictionary = Settings.SPECS[key]
		var value: Variant = _other_value_for(spec)
		Settings.set(key, value)
		written[key] = Settings.get(key)
	Settings.flush_pending_save()

	var config := ConfigFile.new()
	assert_int(config.load(Settings.SAVE_PATH)).is_equal(OK)
	for key in Settings.SPECS:
		var section: String = Settings.SPECS[key]["section"]
		assert_that(config.get_value(section, key)).override_failure_message(
			"'%s' did not reach the file" % key
		).is_equal(written[key])


func test_a_saved_value_comes_back_on_the_next_load() -> void:
	Settings._ready()
	for key in Settings.SPECS:
		Settings.set(key, _other_value_for(Settings.SPECS[key]))
	var expected := {}
	for key in Settings.SPECS:
		expected[key] = Settings.get(key)
	Settings.flush_pending_save()

	Settings._ready()
	for key in Settings.SPECS:
		assert_that(Settings.get(key)).override_failure_message(
			"'%s' did not survive a reload" % key
		).is_equal(expected[key])


func test_a_wrong_type_still_costs_only_that_key() -> void:
	var config := ConfigFile.new()
	config.set_value("gameplay", "text_speed", "instant")
	config.set_value("audio", "voice_volume", 0.25)
	assert_int(config.save(Settings.SAVE_PATH)).is_equal(OK)

	Settings._ready()

	assert_int(Settings.text_speed).is_equal(Settings.DEFAULT_TEXT_SPEED)
	assert_float(Settings.voice_volume).is_equal_approx(0.25, 0.001)


# ---------------------------------------------------------------------------
# Bounds and presets
# ---------------------------------------------------------------------------
func test_a_value_outside_the_bounds_is_clamped_to_them() -> void:
	Settings._ready()
	for key in Settings.SPECS:
		var spec: Dictionary = Settings.SPECS[key]
		if not spec.has("min"):
			continue
		Settings.set(key, float(spec["max"]) + 100.0)
		assert_that(float(Settings.get(key))).override_failure_message(
			"'%s' accepted a value above its maximum" % key
		).is_equal(float(spec["max"]))
		Settings.set(key, float(spec["min"]) - 100.0)
		assert_that(float(Settings.get(key))).override_failure_message(
			"'%s' accepted a value below its minimum" % key
		).is_equal(float(spec["min"]))


func test_the_text_speed_bound_matches_the_number_of_presets() -> void:
	# A fifth preset added without widening the bound would be unreachable; a
	# widened bound without the preset would index past the end.
	assert_int(int(Settings.SPECS["text_speed"]["max"])).is_equal(Settings.TEXT_SPEEDS.size() - 1)
	assert_int(int(Settings.SPECS["text_speed"]["min"])).is_equal(0)


func test_every_preset_has_both_a_speed_and_a_name() -> void:
	# These were two parallel match statements over the same int, free to
	# disagree: a fifth speed added to one and not the other fell through to
	# "Normal" at 30 chars per second, silently.
	for preset in Settings.TEXT_SPEEDS:
		assert_bool(preset.has("name")).is_true()
		assert_bool(preset.has("chars_per_second")).is_true()


func test_the_speed_and_the_name_come_from_the_same_row() -> void:
	Settings._ready()
	for i in range(Settings.TEXT_SPEEDS.size()):
		Settings.text_speed = i
		var preset: Dictionary = Settings.TEXT_SPEEDS[i]
		assert_float(Settings.get_typewriter_speed()).is_equal(float(preset["chars_per_second"]))
		assert_str(Settings.get_text_speed_name()).is_equal(str(preset["name"]))


## A value distinguishable from the default, so a setting that never reaches
## the file cannot pass by accident.
func _other_value_for(spec: Dictionary) -> Variant:
	match int(spec["type"]):
		TYPE_BOOL:
			return not bool(spec["default"])
		TYPE_INT:
			return int(spec["max"]) if int(spec["default"]) != int(spec["max"]) else int(spec["min"])
		_:
			var mid := (float(spec["min"]) + float(spec["max"])) * 0.5
			return mid if not is_equal_approx(mid, float(spec["default"])) else float(spec["min"])
