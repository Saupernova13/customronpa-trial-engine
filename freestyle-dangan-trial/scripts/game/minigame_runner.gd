class_name MinigameRunner
extends Node
## Runs a trial's minigame line: title card, then a replay loop where only
## success advances. Hides the conversation UI and reports to ScriptDirector.

## Three of the eight minigames never damage the influence gauge, so for them a
## round that cannot be won - a time limit shorter than the game takes, a stub
## that always overruns - replays forever, and the settings menu has no quit.
const MAX_ATTEMPTS := 5

## Long enough to read, and the same beat the stub minigames already use.
const UNSUPPORTED_NOTICE_SECONDS := 3.0

var _attempts: int = 0
var _conversation_ui: CanvasItem
var _roaming_text: CanvasItem
var _dialogue_label: Node
## Null until the conversation UI is hidden; see _hide_conversation_ui.
var _hidden_ui: UiVisibilitySnapshot = null

func setup(conversation_ui: Node, roaming_text: Node, dialogue_label: Node) -> void:
	_conversation_ui = conversation_ui as CanvasItem
	_roaming_text = roaming_text as CanvasItem
	_dialogue_label = dialogue_label

func run(minigame: MinigameData) -> void:
	if not MinigameCatalog.has_type(minigame.game_type):
		await _skip_unsupported_type(minigame)
		return

	# Before the conversation UI is hidden and before the title card, so a
	# minigame that cannot be played is never presented as one.
	var errors: Array[String] = MinigameCatalog.validation_errors(minigame)
	if not errors.is_empty():
		_skip_unplayable(minigame, errors)
		return

	if _dialogue_label:
		_dialogue_label.text = ""
	_hide_conversation_ui()

	# Once per minigame line, never per attempt. Five minigames used to reset in
	# their own start(), so every replay refilled the only thing that can end
	# the loop and game-over was unreachable for six of the eight.
	InfluenceGauge.reset()
	_attempts = 0

	# The title card plays once; every attempt gets its own result card.
	var title_card = ResourceRegistry.instantiate("minigame_title_card")
	add_child(title_card)
	title_card.show_title(minigame.game_type, minigame.name)
	await title_card.card_finished

	_start_attempt(minigame)

func _start_attempt(minigame_data: MinigameData) -> void:
	_attempts += 1
	var minigame: MinigameBase = MinigameCatalog.create(minigame_data.game_type)
	if minigame == null:
		_abort(minigame_data.game_type)
		return
	add_child(minigame)
	minigame.initialize(minigame_data)
	minigame.minigame_completed.connect(func(success, data):
		minigame.cleanup()
		minigame.queue_free()

		# An emptied gauge is a hard fail: the game-over screen takes over.
		if not success and data.get("reason", "") == "influence_depleted":
			return

		var result_card = ResourceRegistry.instantiate("minigame_result_card")
		add_child(result_card)
		result_card.show_result(success, data.get("failComment", ""))
		await result_card.card_finished

		if success:
			_restore_conversation_ui()
			ScriptDirector.on_minigame_finished()
		elif _attempts >= MAX_ATTEMPTS:
			_give_up(minigame_data.game_type)
		else:
			_start_attempt(minigame_data)
	)
	ScriptDirector.on_minigame_started(minigame)
	minigame.start()

## An authoring error must not be a soft-lock. Four minigames spin on empty
## data - nothing spawns, nothing can be hit, the timer expires, the attempt
## replays identically - and the diagnostics they do emit are Log.info, which
## is below the release threshold and so reaches no player.
func _skip_unplayable(minigame_data: MinigameData, errors: Array[String]) -> void:
	var detail := ", ".join(errors)
	Log.error(
		"MinigameRunner",
		"Skipping unplayable '%s': %s" % [minigame_data.game_type, detail]
	)
	MobileToast.show_message(
		get_tree().root,
		"Minigame '%s' has no playable data (%s); skipping." % [minigame_data.name, detail],
		true,
		6.0
	)
	ScriptDirector.on_minigame_finished()

## The UI is already hidden and ScriptDirector is parked in MINIGAME_LOADING by
## this point, so bailing out silently freezes the trial with no way back. Put
## the UI back and report a pass so the script moves on past the broken line.
func _abort(game_type: String) -> void:
	_restore_conversation_ui()
	MobileToast.show_message(
		get_tree().root, "Minigame '%s' failed to load; skipping." % game_type, true, 5.0
	)
	ScriptDirector.on_minigame_finished()

## Losing the trial is a worse outcome than being unable to leave it: the
## game-over screen at least offers retry and return-to-menu, and an unwinnable
## attempt otherwise leaves killing the process as the only way out. Emptying
## the gauge routes through the same path a normal defeat takes.
func _give_up(game_type: String) -> void:
	Log.warn(
		"MinigameRunner",
		"'%s' failed %d times; ending the trial." % [game_type, _attempts]
	)
	InfluenceGauge.take_damage_raw(InfluenceGauge.current_influence)

## Told to the player, not only to the log. This used to pause for a second and
## call on_minigame_finished(), so the trial advanced as though the player
## had won - and Log.warn goes to push_warning, which a player on Android never
## sees. The three stub minigames already announce themselves through this
## overlay; a type this build cannot play deserves the same honesty.
##
## It still reports a pass, because the alternative replays an unplayable
## minigame to the attempt cap and ends the trial. Advancing is the only
## recovery; being quiet about it was the bug.
func _skip_unsupported_type(minigame: MinigameData) -> void:
	Log.error(
		"MinigameRunner",
		(
			"Unsupported minigame type '%s' (gameId %s); skipping"
			% [minigame.game_type, minigame.game_id]
		)
	)
	var overlay = ResourceRegistry.instantiate("stub_minigame_overlay")
	if overlay:
		add_child(overlay)
		overlay.set_title("UNSUPPORTED", Color(1.0, 0.4, 0.3))
		overlay.set_subtitle(
			"This trial uses a minigame type ('%s') that this version cannot play - skipping."
			% minigame.game_type
		)
		await get_tree().create_timer(UNSUPPORTED_NOTICE_SECONDS).timeout
		overlay.queue_free()
	ScriptDirector.on_minigame_finished()

func _hide_conversation_ui() -> void:
	# The roaming text belongs to the dialogue presentation, so it hides too.
	_hidden_ui = UiVisibilitySnapshot.hide_all([_conversation_ui, _roaming_text])

## A no-op when nothing was hidden. The paths that return before the hide -
## an unsupported type, unplayable data - never reach this, and putting back
## what was never taken should not make anything appear.
func _restore_conversation_ui() -> void:
	if _hidden_ui == null:
		return
	_hidden_ui.restore()
	_hidden_ui = null
