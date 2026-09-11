class_name SpeakerPresenter
extends RefCounted
## Who the conversation UI says is talking: the name label, the portrait, and
## the sprite fallback chain behind it.
##
## Lifted out of TrialRoomManager, which is a composition root and was also
## rendering. The fallback has five outcomes, three of them added in response
## to real reported problems, and reaching any of them meant building a Node3D
## scene with a Conversation_UI instance, a bench tree and a loaded trial.
##
## Takes its UI nodes and the stage as constructor arguments. TrialLoader is
## reached as an autoload, the same way CharacterStage - its sibling
## collaborator - already reaches it; the texture cache is global state either
## way, and a second convention here would be worse than the one that exists.

## Shown when a speaking line names a character the trial does not contain.
const UNKNOWN_SPEAKER_NAME := "???"

var _name_label: Label
var _portrait_rect: TextureRect
var _stage: CharacterStage

# Keys of warnings already emitted; see _warn_once.
var _warned: Dictionary = {}


func _init(name_label: Label, portrait_rect: TextureRect, stage: CharacterStage) -> void:
	_name_label = name_label
	_portrait_rect = portrait_rect
	_stage = stage


## The speaker for a line. `char_data` may be empty, and `bench_index` may be
## -1 for someone present in the cast files but not seated; both are outcomes,
## not errors.
func present_speaker(
	char_data: Dictionary, character_id: String, bench_index: int, sprite_index: int
) -> void:
	# By id, never bench index: a sparse cast would redirect the lookup.
	# Benchless speakers fall back to the character file, then "???" - never to
	# the previous speaker's name.
	if char_data.is_empty():
		push_warning("Speaking line references unknown character: ", character_id)
		show_name(UNKNOWN_SPEAKER_NAME)
		clear_portrait()
		return

	show_name(full_name_of(char_data))

	if bench_index >= 0:
		show_portrait(bench_index, sprite_index)
		return

	# Present in character.json but not seated. The bench sprite and camera have
	# nothing to act on, and leaving the portrait alone would show the previous
	# speaker's face under this one's name.
	_warn_once("bench", "%s speaks but is not in the cast list; no portrait" % character_id)
	clear_portrait()


## Narrator lines have no speaker, so neither half of the UI may keep the
## previous one's.
func show_narrator() -> void:
	show_name("")
	clear_portrait()


func show_name(character_name: String) -> void:
	if _name_label:
		_name_label.text = character_name


func clear_portrait() -> void:
	if _portrait_rect:
		_portrait_rect.texture = null


## The portrait for whoever is on `bench_index`.
##
## Two silent fallbacks used to stack here: a missing sprite_index fell back to
## sprite 1 unlogged, and a missing sprite 1 left the portrait untouched - so
## the new speaker's name appeared over the previous speaker's face and nothing
## anywhere said so.
func show_portrait(bench_index: int, sprite_index: int = 1) -> void:
	if not _portrait_rect:
		return
	var char_data := _stage.character_at_bench(bench_index)
	var character_id: String = char_data.get("id", "")
	if character_id.is_empty():
		_portrait_rect.texture = null
		return

	var texture := TrialLoader.get_sprite_texture(character_id, sprite_index)
	if not texture and sprite_index != 1:
		# Once per pair, not per line: an author who mistypes spriteIndex never
		# learns why the emotion never changes, but a per-line warning would be
		# one per frame of dialogue.
		_warn_once("sprite", "%s has no sprite %d; using sprite 1" % [character_id, sprite_index])
		texture = TrialLoader.get_sprite_texture(character_id, 1)

	if texture:
		_portrait_rect.texture = texture
		return

	# Cleared, not left stale. A blank portrait is honest; the last speaker's
	# face under this speaker's name is not.
	_warn_once("sprite", "%s has no usable sprite; clearing the portrait" % character_id)
	_portrait_rect.texture = null


## "Name Surname", with either half allowed to be absent.
static func full_name_of(char_data: Dictionary) -> String:
	var full := str(char_data.get("name", "")) + " " + str(char_data.get("surname", ""))
	return full.strip_edges()


## Keyed so a per-line problem is reported once rather than once per frame.
func _warn_once(category: String, message: String) -> void:
	var key := "%s:%s" % [category, message]
	if _warned.has(key):
		return
	_warned[key] = true
	Log.warn("SpeakerPresenter", message)
