class_name ScriptCursor
extends RefCounted
## Walks a trial's script lines, one at a time, flagging the ones nothing can
## play and collecting their types for a single report at the end of the run.
##
## Iterative by construction. The walk used to advance by calling
## advance_to_next_line() from inside itself, so recursion depth equalled the
## length of a run of unplayable lines - and TrialValidator deliberately lets
## unknown line types through with a warning, so a trial from a newer minor
## could overflow the stack instead of being stepped over.
##
## The cursor flags an unplayable line rather than hiding it: the director
## still announces every line it walks past, because listeners key per-line
## effects off that and skipping quietly is not the same as never mentioning
## the line.

## The lines being walked. Replacing them rewinds, so loading a new script does
## not inherit a position in the old one.
var lines: Array[ScriptLine] = []:
	set(value):
		lines = value
		rewind()

## The line last advanced onto; -1 before the first advance, and lines.size()
## once the walk is finished. Written directly by ScriptDirector.reset().
var index: int = -1

## Types some handler claims, as a set. Everything else is unplayable.
var _playable_types: Dictionary = {}

## Types stepped over since the last take_skipped_types(), deduplicated.
var _skipped_types: Array[String] = []


func _init(playable_types: Array = []) -> void:
	for type in playable_types:
		_playable_types[type] = true


## Back to before the first line, forgetting what the last walk skipped.
func rewind() -> void:
	index = -1
	_skipped_types.clear()


## Steps onto the next line. False when there is none, and safe to keep calling
## after that - a finished cursor must not walk its index off into the distance.
func advance() -> bool:
	if index >= lines.size():
		return false
	index += 1
	if index >= lines.size():
		return false
	if not current_is_playable():
		_note_skipped(lines[index].type)
	return true


## Null before the first advance, past the end, or at a seeked-past index.
func current() -> ScriptLine:
	if index < 0 or index >= lines.size():
		return null
	return lines[index]


func current_is_playable() -> bool:
	var line := current()
	return line != null and _playable_types.has(line.type)


## The types stepped over, and clears them. One report per walk: a block of
## unknown types is a single authoring or version problem, and push_warning is
## expensive enough that a thousand of them cost far more than the skipping.
func take_skipped_types() -> Array[String]:
	var taken := _skipped_types.duplicate()
	_skipped_types.clear()
	return taken


func _note_skipped(type: String) -> void:
	if not _skipped_types.has(type):
		_skipped_types.append(type)
