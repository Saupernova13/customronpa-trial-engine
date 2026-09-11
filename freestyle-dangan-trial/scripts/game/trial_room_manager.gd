extends Node3D
## Composition root for the trial room: loads the trial and wires
## ScriptDirector's flow signals to CharacterStage, SpeakerPresenter, the
## DialogueBox and MinigameRunner. Owns the game-over hand-off.
##
## Deciding WHETHER to present a speaker is mediation and stays here; the
## presenting itself is SpeakerPresenter's.

@onready var trial_posts = $Trial_Posts/Trial_Benches
@onready var camera = get_node_or_null("../Camera3D")

## Conversation_UI is an instanced scene, so its children register their unique
## names against it rather than against this scene's root - %Label_Center_Name
## resolves from here only through this anchor. Reaching it is the one path
## left; everything inside it is re-nestable in the editor without touching
## this file.
@onready var conversation_ui: Node = get_node_or_null("../UI/Conversation_UI")

var dialogue_label: RichTextLabel

var trial_file_path: String = "user://trial.drtrial"

var _stage: CharacterStage
var _presenter: SpeakerPresenter
var _dialogue_box: Node
var _minigame_runner: MinigameRunner

func _ready():
	await get_tree().process_frame

	var name_label := _resolve_conversation_ui()
	_stage = CharacterStage.new(trial_posts)
	_presenter = SpeakerPresenter.new(name_label, _portrait_rect(), _stage)

	_dialogue_box = preload("res://scripts/ui/dialogue_box.gd").new()
	add_child(_dialogue_box)
	# The name label and portrait are the presenter's; DialogueBox takes only
	# the text. It would otherwise clear both on every narrator line, which is
	# a second owner for two nodes that now have one.
	_dialogue_box.setup(dialogue_label)
	_dialogue_box.typewriter_started.connect(ScriptDirector.notify_typewriter_started)
	_dialogue_box.typewriter_finished.connect(ScriptDirector.notify_typewriter_finished)
	ScriptDirector.typewriter_skip_requested.connect(func():
		if _dialogue_box:
			_dialogue_box.skip_typewriter()
	)

	_minigame_runner = MinigameRunner.new()
	add_child(_minigame_runner)
	_minigame_runner.setup(
		conversation_ui,
		get_node_or_null("../Path2D_RoamingText"),
		dialogue_label)

	add_to_group("trial_room")

	# Must precede loading: start_trial() emits line 0's signals synchronously,
	# so an unconnected listener opens the trial on a blank box.
	ScriptDirector.line_started.connect(_on_line_started)
	ScriptDirector.dialogue_displayed.connect(_on_dialogue_displayed)
	ScriptDirector.narrator_displayed.connect(_on_narrator_displayed)
	ScriptDirector.minigame_requested.connect(_on_minigame_requested)
	ScriptDirector.trial_ended.connect(_on_trial_ended)
	InfluenceGauge.influence_depleted.connect(_on_game_over)

	_load_and_display_trial()

func _load_and_display_trial():
	if TrialLoader.loaded_async:
		# The loading screen already loaded it; go straight to scene setup.
		_setup_trial_room()
		return

	# Synchronous fallback, for a direct launch out of the editor.
	if TrialLoader.has_meta("pending_trial_path"):
		trial_file_path = TrialLoader.get_meta("pending_trial_path")
		TrialLoader.remove_meta("pending_trial_path")

	if not TrialLoader.load_trial(trial_file_path):
		var msg := (TrialLoader.last_load_error
			if not TrialLoader.last_load_error.is_empty()
			else "Failed to load trial.")
		push_error(msg)
		MobileToast.show_message(get_tree().root, msg, true, 5.0)
		await get_tree().create_timer(1.0).timeout
		get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
		return

	_setup_trial_room()

func _setup_trial_room() -> void:
	_stage.populate(TrialLoader.get_character_ids())
	if dialogue_label:
		dialogue_label.text = ""
	ScriptDirector.start_trial()

## Named lookups, so re-nesting or renaming a container inside conversation_ui
## cannot break these. A missing node warns instead of erroring, which a
## hard-coded path could not do.
## Returns the name label, which the presenter takes; the portrait rect comes
## back through _portrait_rect() and the dialogue label is kept as a field,
## because MinigameRunner and the trial-complete message both write to it.
func _resolve_conversation_ui() -> Label:
	if conversation_ui == null:
		push_warning("TrialRoomManager: Conversation_UI not found; dialogue will not display.")
		return null
	dialogue_label = _require_ui_node("%RichTextLabel_Bottom_Speech") as RichTextLabel
	return _require_ui_node("%Label_Center_Name") as Label

func _portrait_rect() -> TextureRect:
	if conversation_ui == null:
		return null
	return _require_ui_node("%TextureRect_Speaker_Portrait") as TextureRect

func _require_ui_node(unique_name: String) -> Node:
	var node := conversation_ui.get_node_or_null(unique_name)
	if node == null:
		push_warning("TrialRoomManager: %s not found in conversation_ui.tscn" % unique_name)
	return node

func _on_line_started(line: ScriptLine):
	if line.type == ScriptLine.TYPE_SPEAKING:
		_present_speaking_line(line)

	if not line.special_effects.is_empty():
		ScreenEffects.play_effects(line.special_effects)

## Resolves who is speaking and where they sit, then hands the name and
## portrait to the presenter and moves the 3D scene itself. Deciding what to
## present is mediation; presenting it is not.
func _present_speaking_line(line: ScriptLine) -> void:
	var character_id := line.character_id
	var sprite_index := line.sprite_index

	# By id, never bench index: a sparse cast would redirect the lookup.
	# Benchless speakers fall back to the character file, then "???" - never to
	# the previous speaker's name.
	var bench_index: int = _stage.find_bench(character_id)
	var char_data: Dictionary = _stage.character_at_bench(bench_index)
	if char_data.is_empty():
		char_data = TrialLoader.load_character(character_id)

	_presenter.present_speaker(char_data, character_id, bench_index, sprite_index)

	if char_data.is_empty() or bench_index < 0:
		return

	# Hard cut, never a pan.
	if camera and camera.has_method("jump_to_bench"):
		camera.jump_to_bench(bench_index, false)
	var camera_motion := line.camera_motion
	if not camera_motion.is_empty() and camera_motion.get("type", "none") != "none":
		CameraDirector.execute_motion(camera_motion, bench_index)

	_stage.update_sprite(bench_index, character_id, sprite_index)

func _on_dialogue_displayed(_character_id: String, _text: String):
	if _dialogue_box:
		_dialogue_box.display_speaking_line(ScriptDirector.get_current_line())

func _on_narrator_displayed(_text: String):
	_presenter.show_narrator()
	if _dialogue_box:
		_dialogue_box.display_narrator_line(ScriptDirector.get_current_line())

func _on_minigame_requested(minigame: MinigameData):
	_minigame_runner.run(minigame)

func _on_trial_ended():
	if dialogue_label:
		dialogue_label.text = "[Trial Complete]"
	_presenter.show_name("")

# ---------------------------------------------------------------------------
# Called by the bench-focus camera (player free-look) and MinigameBase.
# ---------------------------------------------------------------------------
func on_bench_focused(bench_index: int):
	# The camera's _ready() can beat this manager's. Ignoring focus until _stage
	# exists is safe: the first dialogue line sets the speaker anyway.
	if _stage == null:
		return

	if (
		ScriptDirector.current_state == ScriptDirector.State.WAITING_FOR_ADVANCE
		or ScriptDirector.current_state == ScriptDirector.State.DIALOGUE
	):
		return

	var char_data: Dictionary = _stage.character_at_bench(bench_index)
	if not char_data.is_empty():
		_presenter.show_name(SpeakerPresenter.full_name_of(char_data))
		_presenter.show_portrait(bench_index)

func find_character_position(character_id: String) -> int:
	return _stage.find_bench(character_id)

func _on_game_over():
	# Before the screen is shown, not in the exit handlers. Dying while
	# slow-time was active used to play the whole game-over sequence in slow
	# motion, because the scale was only restored on the way out.
	TimeScale.release_all()
	ScriptDirector.pause_trial()
	if dialogue_label:
		dialogue_label.text = ""
	_presenter.show_narrator()

	var game_over_screen = ResourceRegistry.instantiate("game_over_screen")
	add_child(game_over_screen)
	game_over_screen.show_game_over()

	# Both gauges, not just influence: retrying with an empty concentrate gauge
	# meant no slow-time for the retry, with nothing said. The autoloads outlive
	# the scene change, so anything not reset here carries into the next run -
	# ScriptDirector.reset() runs from start_trial() on the way in.
	game_over_screen.retry_requested.connect(func():
		TimeScale.release_all()
		InfluenceGauge.reset()
		ConcentrateGauge.reset()
		get_tree().reload_current_scene()
	)
	game_over_screen.return_to_menu.connect(func():
		TimeScale.release_all()
		InfluenceGauge.reset()
		ConcentrateGauge.reset()
		get_tree().change_scene_to_file("res://scenes/start_menu.tscn")
	)
