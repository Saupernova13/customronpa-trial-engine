extends Node
## Drives the trial script: walks the lines, tracks high-level state, and
## coordinates pause, settings and auto-skip. Reacts to InputManager's signals
## rather than running its own _input().

## What each state permits is state_steps_script() and state_is_pausable()
## below, not a comparison at each call site. MINIGAME_LOADING and
## MINIGAME_RESULT are assigned and never compared against anywhere, which used
## to need a paragraph of explanation; they answer false to stepping the script,
## which is the whole reason they exist.
enum State {
	IDLE,
	DIALOGUE,
	WAITING_FOR_ADVANCE,
	MINIGAME_LOADING,
	MINIGAME_ACTIVE,
	MINIGAME_RESULT,
	PAUSED,
	TRIAL_COMPLETE
}

signal line_started(line: ScriptLine)
signal dialogue_displayed(character_id: String, text: String)
signal narrator_displayed(text: String)
signal minigame_requested(minigame: MinigameData)
signal trial_ended
signal typewriter_skip_requested

var current_state: State = State.IDLE
var is_typewriter_active: bool = false

## The walk itself: the line array, the index, and which types nothing plays.
## ScriptCursor owns all three, so the two properties below are the names the
## rest of the engine and the tests already use, forwarded to it.
var _cursor := ScriptCursor.new()

var script_lines: Array[ScriptLine]:
	get: return _cursor.lines
	set(value): _cursor.lines = value

var current_line_index: int:
	get: return _cursor.index
	set(value): _cursor.index = value

var _active_minigame: Node = null
var _settings_menu: Node = null
var _auto_advance_timer: float = 0.0
var _pre_pause_state: State = State.IDLE
# Number of outstanding pause_trial() calls; see pause_trial().
var _pause_depth: int = 0
var _skip_held: bool = false
var _skip_timer: float = 0.0

## Script line-type dispatch. New line types plug in here.
var _line_handlers: Dictionary = {}

func _ready():
	# Each handler returns whether it took the line; see advance_to_next_line.
	_line_handlers = {
		ScriptLine.TYPE_SPEAKING: _handle_speaking_line,
		ScriptLine.TYPE_NARRATOR: _handle_narrator_line,
		ScriptLine.TYPE_MINIGAME: _handle_minigame_line,
	}
	# The handler table IS the set of playable types, so the cursor reads it
	# rather than keeping a second list that could fall out of step.
	_cursor = ScriptCursor.new(_line_handlers.keys())
	InputManager.advance_pressed.connect(_on_advance_input)
	InputManager.settings_toggle_requested.connect(_on_settings_toggle_requested)
	InputManager.skip_held_changed.connect(_on_skip_held_changed)

## Everything transient this autoload carries. It survives
## reload_current_scene() and change_scene_to_file(), so state left behind by
## the previous run reaches the next one: a player who died mid-typewriter
## retried with is_typewriter_active still true, and their first advance press
## was eaten as a typewriter skip; one who died holding CTRL kept
## fast-forwarding into the reloaded scene.
func reset() -> void:
	is_typewriter_active = false
	_active_minigame = null
	_settings_menu = null
	_auto_advance_timer = 0.0
	_skip_held = false
	_skip_timer = 0.0
	_pause_depth = 0
	_pre_pause_state = State.IDLE
	_cursor.rewind()
	_transition_to(State.IDLE)

func start_trial():
	reset()
	script_lines = TrialLoader.get_script_lines()
	if script_lines.is_empty():
		Log.warn("ScriptDirector", "No script lines found")
		return

	Log.info("ScriptDirector", "Starting trial with %d lines" % script_lines.size())
	_transition_to(State.DIALOGUE)
	advance_to_next_line()

func _transition_to(new_state: State):
	current_state = new_state

# ---------------------------------------------------------------------------
# What a state permits
#
# Asked, never compared. "May the script be stepped forward from here?" was
# written out three times - in _on_advance_input and in both branches of
# _process - so a fourth caller had to know to ask it a fourth time, and the
# states that exist only to answer no needed a comment to say so.
# ---------------------------------------------------------------------------

## Whether player input or a timer may move to the next line.
##
## Only while the current line has been presented and is waiting. Every
## minigame state answers false, so input cannot step the script out from under
## a minigame or the result card that follows it; PAUSED answers false for the
## same reason, which is why _on_advance_input needs no separate pause guard.
static func state_steps_script(state: State) -> bool:
	return state == State.WAITING_FOR_ADVANCE

## Whether pausing this state is meaningful.
##
## IDLE and TRIAL_COMPLETE are not: there is nothing to come back to, and
## recording PAUSED over either would lose the only state that means anything.
static func state_is_pausable(state: State) -> bool:
	return state != State.IDLE and state != State.TRIAL_COMPLETE

## Walks forward until a handler takes a line, or the script runs out. The
## stepping is the cursor's; what is left here is what to do with each line.
##
## Every line the walk passes is announced, skipped ones included: listeners key
## their per-line effects off line_started, and skipping quietly is not the same
## as never mentioning the line.
func advance_to_next_line():
	while _cursor.advance():
		var line: ScriptLine = _cursor.current()
		line_started.emit(line)

		if not _cursor.current_is_playable():
			continue
		# Handlers return false when they could not play the line, and the walk
		# moves on to the next one.
		if _line_handlers[line.type].call(line):
			_report_skipped_types()
			return

	_report_skipped_types()
	Log.info("ScriptDirector", "End of script reached")
	_transition_to(State.TRIAL_COMPLETE)
	trial_ended.emit()

## One message per run of skipped lines rather than one per line. A block of
## unknown types is a single authoring or version problem, and push_warning is
## expensive enough that a thousand of them cost far more than the skipping.
func _report_skipped_types() -> void:
	var types := _cursor.take_skipped_types()
	if types.is_empty():
		return
	Log.warn("ScriptDirector", "Skipped lines with unknown types: %s" % ", ".join(types))

func _handle_speaking_line(line: ScriptLine) -> bool:
	_transition_to(State.DIALOGUE)
	_play_line_audio(line)
	dialogue_displayed.emit(line.character_id, line.dialogue)
	_transition_to(State.WAITING_FOR_ADVANCE)
	return true

func _handle_narrator_line(line: ScriptLine) -> bool:
	_transition_to(State.DIALOGUE)
	# Narrator lines carry audio too, for SFX and narration VO.
	_play_line_audio(line)
	narrator_displayed.emit(line.display_text())
	_transition_to(State.WAITING_FOR_ADVANCE)
	return true

func _play_line_audio(line: ScriptLine) -> void:
	if not line.audio_file.is_empty():
		if AudioManager.is_voice_playing():
			AudioManager.stop_voice()
		AudioManager.play_voice_line(line.audio_file)

func _handle_minigame_line(line: ScriptLine) -> bool:
	if line.minigame_id.is_empty():
		Log.warn("ScriptDirector", "Minigame line missing minigameId, skipping")
		return false

	var minigame: MinigameData = (
		TrialLoader.manifest.find_minigame(line.minigame_id) if TrialLoader.manifest else null
	)
	if minigame == null:
		Log.warn("ScriptDirector", "Minigame not found: %s, skipping" % line.minigame_id)
		return false

	_transition_to(State.MINIGAME_LOADING)
	minigame_requested.emit(minigame)
	return true

func on_minigame_started(minigame_node: Node):
	_active_minigame = minigame_node
	_transition_to(State.MINIGAME_ACTIVE)

## Takes no result. The director does not branch on success - MinigameRunner
## owns the retry and skip paths - and it used to accept a `success` only to
## re-emit it on a signal nothing listened to. Every caller passed `true`.
func on_minigame_finished():
	_active_minigame = null
	_transition_to(State.MINIGAME_RESULT)
	# Long enough for the result card to be read.
	await get_tree().create_timer(MinigameConfig.MINIGAME_RESULT_PAUSE).timeout
	_transition_to(State.DIALOGUE)
	advance_to_next_line()

func notify_typewriter_started():
	is_typewriter_active = true

func notify_typewriter_finished():
	is_typewriter_active = false
	_auto_advance_timer = 0.0

# ---------------------------------------------------------------------------
# Input reactions
# ---------------------------------------------------------------------------
func _on_advance_input() -> void:
	if not state_steps_script(current_state):
		return
	if is_typewriter_active:
		typewriter_skip_requested.emit()
	else:
		advance_to_next_line()
	get_viewport().set_input_as_handled()

func _on_settings_toggle_requested() -> void:
	_toggle_settings_menu()
	get_viewport().set_input_as_handled()

func _on_skip_held_changed(held: bool) -> void:
	_skip_held = held
	_skip_timer = 0.0
	if held:
		_auto_advance_timer = 0.0

# ---------------------------------------------------------------------------
# Pause / settings
# ---------------------------------------------------------------------------
## Counted, because the two things that pause can overlap: the settings menu
## can be opened on top of the game-over screen, which has already paused.
## Without the count the inner pause would record PAUSED as the state to return
## to, losing the real one, and closing the menu would unpause a trial that is
## meant to stay stopped.
func pause_trial():
	_pause_depth += 1
	if _pause_depth > 1:
		return
	if state_is_pausable(current_state):
		_pre_pause_state = current_state
		_transition_to(State.PAUSED)
	_set_minigame_paused(true)

func resume_trial():
	if _pause_depth == 0:
		return
	_pause_depth -= 1
	if _pause_depth > 0:
		return
	if current_state == State.PAUSED:
		_transition_to(_pre_pause_state)
	_set_minigame_paused(false)

## The whole point of pausing. Without this a 60s Nonstop Debate keeps
## spawning panels and counting down behind the settings menu, and can fail
## while the menu is still open.
func _set_minigame_paused(paused: bool) -> void:
	if not is_instance_valid(_active_minigame):
		return
	if paused:
		_active_minigame.pause()
	else:
		_active_minigame.resume()

func get_current_line() -> ScriptLine:
	return _cursor.current()

func _process(delta):
	if _skip_held and state_steps_script(current_state):
		_skip_timer += delta
		if _skip_timer >= MinigameConfig.SKIP_INTERVAL:
			_skip_timer = 0.0
			if is_typewriter_active:
				typewriter_skip_requested.emit()
			else:
				advance_to_next_line()
		return

	if (
		Settings
		and Settings.auto_advance
		and state_steps_script(current_state)
		and not is_typewriter_active
	):
		_auto_advance_timer += delta
		if _auto_advance_timer >= Settings.auto_advance_delay:
			_auto_advance_timer = 0.0
			advance_to_next_line()

func _toggle_settings_menu():
	if _settings_menu:
		# Actually toggle. _on_settings_toggle_requested marks the event handled
		# whatever happens here, so returning early left the menu with no
		# keyboard exit at all - and the mobile HUD's settings button, which
		# routes through the same signal, equally inert on a second tap.
		_settings_menu.close()
		return

	pause_trial()

	_settings_menu = ResourceRegistry.instantiate("settings_menu")
	add_child(_settings_menu)
	_settings_menu.open()
	_settings_menu.closed.connect(func():
		_settings_menu = null
		resume_trial()
	)
