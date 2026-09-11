extends GdUnitTestSuite
## Two silent fallbacks stacked: a missing spriteIndex fell back to sprite 1
## unlogged, and a missing sprite 1 left the portrait untouched - so the new
## speaker's name appeared over the previous speaker's face, and nothing
## anywhere said so. The author could not reproduce it, because their local
## build had the sprite cached.
##
## These used to build a TrialRoomManager, because the fallback lived on it.
## SpeakerPresenter is a RefCounted that takes its two Controls and the stage,
## so the whole chain is reachable without a trial room.

const PRESENT := "FC_PRESENT"
const ABSENT := "FC_ABSENT"


func _presenter() -> SpeakerPresenter:
	return SpeakerPresenter.new(
		auto_free(Label.new()),
		auto_free(TextureRect.new()),
		CharacterStage.new(auto_free(Node3D.new()))
	)


func _seat(presenter: SpeakerPresenter, bench: int, character_id: String) -> void:
	presenter._stage._by_bench[bench] = {"id": character_id}


func _store_sprite(character_id: String, sprite_index: int) -> ImageTexture:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.RED)
	var texture := ImageTexture.create_from_image(image)
	TrialLoader.characters.store_texture(character_id, sprite_index, texture)
	return texture


func before_test() -> void:
	TrialLoader.characters.clear()


func after_test() -> void:
	TrialLoader.characters.clear()


# ---------------------------------------------------------------------------
# The sprite fallback chain
# ---------------------------------------------------------------------------
func test_the_requested_sprite_is_used_when_it_exists() -> void:
	var expected := _store_sprite(PRESENT, 3)
	var presenter := _presenter()
	_seat(presenter, 0, PRESENT)

	presenter.show_portrait(0, 3)

	assert_object(presenter._portrait_rect.texture).is_same(expected)


func test_a_missing_index_falls_back_to_sprite_one() -> void:
	var first := _store_sprite(PRESENT, 1)
	var presenter := _presenter()
	_seat(presenter, 0, PRESENT)

	presenter.show_portrait(0, 7)

	assert_object(presenter._portrait_rect.texture).is_same(first)


func test_no_usable_sprite_clears_the_portrait_rather_than_keeping_the_last_one() -> void:
	# The reported failure, stated directly.
	var previous := _store_sprite(PRESENT, 1)
	var presenter := _presenter()
	_seat(presenter, 0, PRESENT)
	presenter.show_portrait(0, 1)
	assert_object(presenter._portrait_rect.texture).is_same(previous)

	_seat(presenter, 1, ABSENT)
	presenter.show_portrait(1, 1)

	assert_object(presenter._portrait_rect.texture).is_null()


func test_an_empty_bench_clears_the_portrait_too() -> void:
	var previous := _store_sprite(PRESENT, 1)
	var presenter := _presenter()
	_seat(presenter, 0, PRESENT)
	presenter.show_portrait(0, 1)
	assert_object(presenter._portrait_rect.texture).is_same(previous)

	# Bench 5 has nobody on it.
	presenter.show_portrait(5, 1)

	assert_object(presenter._portrait_rect.texture).is_null()


func test_a_repeated_problem_is_reported_once() -> void:
	# Otherwise a missing sprite warns on every line that character speaks.
	var presenter := _presenter()
	_seat(presenter, 0, ABSENT)

	presenter._warn_once("sprite", "same message")
	presenter._warn_once("sprite", "same message")
	presenter._warn_once("sprite", "a different message")

	assert_int(presenter._warned.size()).is_equal(2)


# ---------------------------------------------------------------------------
# The other outcomes of presenting a speaker, which needed a whole trial room
# before and so were never covered
# ---------------------------------------------------------------------------
func test_an_unknown_character_gets_a_placeholder_name_and_no_portrait() -> void:
	var previous := _store_sprite(PRESENT, 1)
	var presenter := _presenter()
	_seat(presenter, 0, PRESENT)
	presenter.show_portrait(0, 1)
	assert_object(presenter._portrait_rect.texture).is_same(previous)

	presenter.present_speaker({}, "CH_NOBODY", -1, 1)

	assert_str(presenter._name_label.text).is_equal(SpeakerPresenter.UNKNOWN_SPEAKER_NAME)
	assert_object(presenter._portrait_rect.texture).is_null()


func test_a_speaker_who_is_not_seated_keeps_their_name_and_loses_the_portrait() -> void:
	# Present in character.json but not in the cast list. The previous
	# speaker's face under this one's name was the bug.
	var previous := _store_sprite(PRESENT, 1)
	var presenter := _presenter()
	_seat(presenter, 0, PRESENT)
	presenter.show_portrait(0, 1)
	assert_object(presenter._portrait_rect.texture).is_same(previous)

	presenter.present_speaker({"name": "Kyoko", "surname": "Kirigiri"}, "CH_KYOKO", -1, 1)

	assert_str(presenter._name_label.text).is_equal("Kyoko Kirigiri")
	assert_object(presenter._portrait_rect.texture).is_null()


func test_a_seated_speaker_gets_both() -> void:
	var expected := _store_sprite(PRESENT, 2)
	var presenter := _presenter()
	_seat(presenter, 4, PRESENT)

	presenter.present_speaker({"name": "Makoto", "surname": "Naegi"}, PRESENT, 4, 2)

	assert_str(presenter._name_label.text).is_equal("Makoto Naegi")
	assert_object(presenter._portrait_rect.texture).is_same(expected)


func test_a_narrator_line_clears_both_halves() -> void:
	var presenter := _presenter()
	_store_sprite(PRESENT, 1)
	_seat(presenter, 0, PRESENT)
	presenter.present_speaker({"name": "Makoto", "surname": "Naegi"}, PRESENT, 0, 1)

	presenter.show_narrator()

	assert_str(presenter._name_label.text).is_empty()
	assert_object(presenter._portrait_rect.texture).is_null()


func test_a_half_named_character_gets_no_stray_space() -> void:
	assert_str(SpeakerPresenter.full_name_of({"name": "Monokuma"})).is_equal("Monokuma")
	assert_str(SpeakerPresenter.full_name_of({"surname": "Kirigiri"})).is_equal("Kirigiri")
	assert_str(SpeakerPresenter.full_name_of({})).is_empty()


func test_missing_ui_nodes_are_survivable() -> void:
	# _resolve_conversation_ui warns and returns null rather than erroring, so
	# the presenter is handed nulls on a broken scene and must not add a crash
	# to a problem that has already been reported.
	var presenter := SpeakerPresenter.new(null, null, CharacterStage.new(auto_free(Node3D.new())))
	presenter.present_speaker({"name": "Makoto"}, PRESENT, 0, 1)
	presenter.show_narrator()
	presenter.show_portrait(0, 1)
