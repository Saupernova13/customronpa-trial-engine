# Design patterns in the Godot engine

Applying named design patterns (Gang of Four, as catalogued at
refactoring.guru) to `freestyle-dangan-trial/scripts/`, where doing so
removes duplication, shrinks bug surface, or makes something testable that
is not testable today.

## The bar

A pattern earns its place here only when it buys one of three things:

1. **Duplication removed** — the same logic is written more than once, and
   one of the copies can drift from the others.
2. **Bug surface shrunk** — a correctness-critical step is currently the
   caller's responsibility to remember, and the pattern makes it the
   structure's responsibility instead.
3. **Testability gained** — a behaviour can only be exercised today through
   a heavyweight collaborator (a live `Camera3D`, the whole director), and
   the pattern lets it be tested alone.

A pattern that buys none of those is not applied. GDScript is not Java: a
`Dictionary` of `Callable`s already *is* Strategy, and rewriting one into a
class hierarchy to make the pattern's name visible in the file tree costs
files and indirection for nothing. Several such rewrites were considered and
rejected; they are listed under "Deliberately not done".

## What is already a pattern

These are patterns in the codebase today, in GDScript's idiom. They are
named here so a future reader does not "introduce" what is already present.

| Pattern | Where | Form it takes |
| --- | --- | --- |
| Facade | `core/trial_loader.gd` | Delegates to `TrialArchive` and `CharacterLibrary`; self-documented as a facade |
| Flyweight / Proxy | `config/resource_registry.gd`, `core/trial/character_library.gd`, `core/audio_manager.gd` | Keyed caches in front of `load()`, image decode, audio decode |
| Template Method | `minigames/minigame_base.gd` | `initialize` / `start` / `validate_data` / `cleanup`, subclasses call `super` |
| Observer | throughout | Godot signals |
| Singleton | `project.godot` autoloads | 12 of them |
| Mediator | `game/trial_room_manager.gd` | Composition root wiring director to stage, dialogue box and runner |
| Adapter | `core/trial/model/json_read.gd` | Untyped JSON `Variant` to typed reads |
| Strategy (as a table) | `_line_handlers`, `_motions`, `_effects`, `_HUD_SPECS` | `Dictionary` of `Callable` |

## The eight refactors

Each is one GitHub issue, one branch, one pull request. Ordering is forced
only where noted; the rest are independent.

### 1. Factory Method — `MinigameCatalog`

**Problem.** `MinigameRunner.MINIGAME_SCRIPTS` is the normative `gameType`
registry, but `TrialValidator._warn_unknown_game_types` reaches *up* into
it. The validator is a data-layer `RefCounted`; the runner is a scene-layer
`Node` that instantiates overlays and drives `ScriptDirector`. The data
layer depending on the scene layer is backwards, and it is the reason the
validator cannot be exercised without the runner's whole dependency cone.

Separately, `MinigameRunner._validation_errors` builds a "probe" instance
purely to call `validate_data()` on it, then must remember to `free()` it —
a leak if an early return is ever added between the two.

**Change.** Extract `scripts/core/trial/minigame_catalog.gd`: the
`gameType → script path` table plus `create(game_type) -> MinigameBase` and
`validation_errors(data) -> Array[String]`. `MinigameRunner` and
`TrialValidator` both depend on the catalog; neither depends on the other.
The probe's lifetime lives inside `validation_errors`, where no future
caller can forget it.

**Buys.** Bug surface (probe lifetime), testability (validator without the
scene layer), and it removes an inverted dependency.

**Blocks.** Refactor 2.

### 2. Composite — validation rules

**Problem.** `TrialValidator.validate()` is a 60-line static function
running five unrelated structural checks; `_dangling_references()` is
another 60 running three more. Whether a given problem is fatal
(`errors.append`) or advisory (`push_warning`) is decided ad hoc at each
site, and the two mechanisms are unrelated — so a caller cannot ask for the
warnings, and a test cannot assert on them without capturing engine output.
The file's own docstring states that it "can drift from the schema without
CI noticing".

**Change.** One rule per structural concern, each implementing
`check(data: Dictionary, report: ValidationReport) -> void`; the validator
composes them and runs them in order. `ValidationReport` carries both
severities, so "fatal" becomes a property of the finding rather than a
choice of which function to call. `validate()` keeps its current signature
and semantics for callers.

**Buys.** Testability (a rule at a time), duplication (the four dangling-id
scans share one shape), and it makes the error/warning split declarative.

**Not Chain of Responsibility**, which this was first written down as. A chain
means each handler decides whether to handle the request and whether to pass it
on. Every rule here runs unconditionally and none can stop a later one, so the
composite is the whole pattern; naming the chain as well would be a label with
nothing behind it.

**Depends on** refactor 1.

### 3. Command — camera motions

**Problem.** `camera_director.gd` is 321 lines. Thirty motions are forced
through one signature, `(bench_index, duration, ease_type, trans_type)`, in
which most handlers leave most parameters `_`-prefixed and unused. Nine are
the same tween body with a different target property. Worst: the
supersede guard —

```gdscript
var generation := _motion_generation
await ...
_finish_motion(generation)
```

— is copy-pasted into four handlers, and a fifth that forgets it reports
`motion_completed` for the motion that replaced it. That is exactly the bug
the surrounding comment says was already fixed once.

**Change.** A `CameraMotion` command with `execute(ctx: CameraContext)`;
the director builds the context, owns cancellation and generation
bookkeeping in one place, and awaits the command. Parameterised families
(rotate, translate, dolly, zoom) become one command configured by data
rather than nine `bind()`s.

**Buys.** Duplication (nine bodies to one, four guards to zero), bug
surface (the guard is structural, not remembered), testability (a motion
without a live `Camera3D`).

### 4. Iterator — `ScriptCursor`

**Problem.** `ScriptDirector.advance_to_next_line()` owns the index, the
`while true` walk, the unknown-type skip, and the batched skip report, all
inline. None of it can be tested without starting a trial.

**Change.** `ScriptCursor` owns `script_lines` and `current_line_index` and
yields the next *playable* line, collecting skipped types as it goes. The
director asks it for a line and plays it.

**Buys.** Testability, and it shrinks refactor 5's diff.

**Blocks.** Refactor 5.

### 5. State — `ScriptDirector`

**Problem.** The class docstring spends a full paragraph explaining that
`MINIGAME_LOADING` and `MINIGAME_RESULT` are assigned and never compared
against, and exist only so that three separate `WAITING_FOR_ADVANCE` guards
evaluate false. The question "may player input step the script right now?"
is therefore answered in three places — `_on_advance_input`, the
hold-to-skip branch of `_process`, and the auto-advance branch — and a
fourth caller would have to know to ask it a fourth time.

**Change.** Each state answers for itself: `accepts_advance()`,
`auto_advances()`, `ticks_skip()`. `pause_trial()`/`resume_trial()` keep
their counted-depth semantics, with the pre-pause state held by the state
machine rather than in a loose field. Implemented strangler-style: the new
structure lands beside the enum, call sites migrate, the enum's guards are
deleted last.

**Buys.** Duplication (three guards to one question), and it deletes a
docstring that exists only to apologise for the current shape.

**Depends on** refactor 4. This is the highest-risk change in the set; the
existing `test_script_director_*` suites are the safety net and are extended
before anything moves.

### 6. Memento — UI visibility

**Problem.** `MinigameRunner` saves `_conversation_ui_was_visible` and
`_roaming_text_was_visible` before hiding two `CanvasItem`s and restores
them afterwards — two fields, two capture sites, two restore sites, and a
third hidden node would need a fourth field.

**Change.** `UiVisibilitySnapshot.capture(nodes)` / `.restore()`.

**Buys.** Duplication, and it scales to a third node without new fields.

### 7. Strategy / spec table — `Settings`

**Problem.** Every setting is declared in four places: a `DEFAULT_*`
constant, a property with a clamp, a typed read in `_load_settings()`, and a
`config.set_value` in `_save_settings()`. Adding one means four edits and
forgetting the fourth silently stops it persisting. Separately,
`get_typewriter_speed()` and `get_text_speed_name()` are parallel `match`
statements over the same int, free to disagree.

**Change.** One spec row per setting — section, key, type, default, clamp —
driving load and save. The text-speed presets become one table of
(speed, name) that both accessors read.

**Buys.** Duplication, and it removes a four-site drift risk.

### 8. Extract `SpeakerPresenter`

**Problem.** `TrialRoomManager` is documented as a composition root, and is
one — but it also owns speaker presentation (`_present_speaking_line`,
`_set_portrait`, `_set_name`, `_warn_once`, the sprite-fallback chain) and
the game-over hand-off, at 276 lines. A Mediator that also renders is not a
Mediator.

**Change.** Move name/portrait/sprite-fallback presentation to
`game/speaker_presenter.gd`. `TrialRoomManager` keeps wiring and lifecycle.

**Buys.** Testability (the sprite-fallback chain without a trial room), and
it makes the existing Mediator honest.

## Deliberately not done

- **Class-per-screen-effect (Command).** `ScreenEffects._effects` is twenty
  one-line lambdas. Twenty classes would be twenty files to express what
  twenty lines already express, with no duplication removed.
- **Builder for `setup_standard_ui`.** Five HUD components from a flat
  list. A fluent builder is ceremony; the one real wart — the
  `TIMER_DISPLAY` special case inside the loop — does not need a pattern to
  fix and is not worth a PR of its own.
- **Converting `_line_handlers` / `_HUD_SPECS` to class hierarchies.** They
  are already Strategy. Renaming the mechanism changes nothing.
- **Bridge, Decorator, Visitor, Prototype, Abstract Factory.** No site in
  the engine has the shape these solve. Visitor was considered for the
  validator and rejected: the rules do not dispatch on node type, they
  scan a `Dictionary`, so Composite fits and Visitor does not.

## Verification

Every refactor is behaviour-preserving unless its issue says otherwise, and
each pull request must pass, locally before the commit and in CI after:

- `gdlint scripts tests` from `freestyle-dangan-trial/`
- the full gdUnit4 suite:
  `bash addons/gdUnit4/runtest.sh -a res://tests/unit --headless --ignoreHeadlessMode`
  — 246 tests across 38 suites at the time of writing, and a refactor that
  reduces that count without its issue saying so is a regression, not a
  simplification.

New tests are written before the refactor they cover, and they must fail
against the pre-refactor code for the reason claimed.

## Documentation

`ARCHITECTURE.md` names `MinigameRunner.MINIGAME_SCRIPTS`,
`ResourceRegistry.SCENES` and the seven-step "Adding a minigame" list. The
catalog refactor moves the first of those, so that document is updated in
the same pull request rather than left to drift.
