class_name UiVisibilitySnapshot
extends RefCounted
## Remembers whether a set of CanvasItems was visible, so it can be put back.
##
## MinigameRunner hides the conversation UI and the roaming text for the
## duration of a minigame. That was two bool fields, two captures and two
## restores, and a third hidden node would have needed a fifth and a sixth -
## which is how the second one arrived, copied from the first.
##
## A snapshot that captured nothing restores nothing. The fields it replaces
## defaulted to true, so a restore with no preceding capture forced both nodes
## visible; that was right only by the default value, and never happened,
## because every restore path runs after a hide.

var _states: Array[Dictionary] = []


## Records each node's visibility, then hides it. Nulls in `nodes` are skipped,
## so a caller can pass an optional node without checking it first.
static func hide_all(nodes: Array) -> UiVisibilitySnapshot:
	var snapshot := UiVisibilitySnapshot.new()
	for node in nodes:
		if node == null or not is_instance_valid(node):
			continue
		var item := node as CanvasItem
		if item == null:
			continue
		snapshot._states.append({"node": item, "visible": item.visible})
		item.visible = false
	return snapshot


## Puts every captured node back as it was. A node freed in the meantime - the
## scene changed under the minigame - is skipped rather than erroring.
func restore() -> void:
	for state in _states:
		# Validity is checked before the typed read, not after: assigning a
		# freed instance to a typed local is itself the error.
		if not is_instance_valid(state["node"]):
			continue
		var item: CanvasItem = state["node"]
		item.visible = state["visible"]


## How many nodes this snapshot is holding, for tests and for reading.
func size() -> int:
	return _states.size()
