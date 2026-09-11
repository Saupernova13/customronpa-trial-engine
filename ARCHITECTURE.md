# Architecture

Two independent components share one data format:

```
web-ui-editor/            Browser editor: author a trial, export .drtrial
freestyle-dangan-trial/   Godot 4.7 engine: load .drtrial, play the trial
```

A `.drtrial` file is a ZIP of the trial folder the editor maintains:

```
trial-folder/
├── trial.json          # metadata, cast ids, script lines, minigames, truth bullets
├── Characters/<Name>/  # character.json + sprite_01.png … sprite_NN.png
├── Audio/              # per-line voice files; Minigames/<gameId>/ for minigame voices
└── TruthBullets/       # evidence images
```

`trial.json` is the contract between the two components. The editor writes it,
`trial_loader.gd` reads it.

## The trial.json contract

The normative definition of the format lives in
[`schema/trial.schema.json`](schema/trial.schema.json) (JSON Schema). Three
things track it, and CI cross-checks all of them against the shared fixture
trial in `freestyle-dangan-trial/tests/fixtures/minimal-trial/`:

- the editor's runtime validator (`web-ui-editor/js/core/trialSchema.js`),
  cross-checked against the schema by ajv in `tests/schema.test.js`;
- the engine's validator (`scripts/core/trial/trial_validator.gd`) and typed
  model (`scripts/core/trial/model/`), exercised by the gdUnit4 suites;
- the format version: the editor writes `metadata.version`
  (`FORMAT_VERSION` in `js/core/constants.js`), the engine checks it
  (`TrialValidator.SUPPORTED_FORMAT_MAJOR`). Both sides reject files from a
  newer major version and warn on older ones.

`Characters/<Name>/character.json` has its own normative definition in
[`schema/character.schema.json`](schema/character.schema.json), mirrored by
`web-ui-editor/js/core/characterSchema.js` and cross-checked with ajv in
`tests/characterSchema.test.js`. It carries its own `formatVersion`
(`CHARACTER_FORMAT_VERSION`), tracked separately from the trial's: the two
files change shape independently. The engine reads only `id`, `name` and
`surname` from it, as an untyped Dictionary.

To change the format: update the schema, then the editor validator/writer
and its tests, then the engine validator/model and its tests, then the
fixture. Bump the minor version for additive changes, the major for breaking
ones. A change that lands on only one side fails the other side's CI.

## Web editor

Framework-free ES modules bundled with Vite. See
[web-ui-editor/README.md](web-ui-editor/README.md) for the module map,
conventions, and dev workflow — that document is kept current.

## Godot engine

GDScript, organized under `freestyle-dangan-trial/scripts/`:

```
core/       Autoload singletons (see below) + trial/ loader helpers, the
            minigame catalog and AudioStreamLoader
camera/     CameraDirector autoload, motions/ (one CameraMotion per editor
            motion name) and the bench_focus_camera rig
config/     MinigameConfig (tuning constants), ResourceRegistry (scene keys), UITheme
effects/    Spawnable effect scenes' scripts (drift popup, panel shatter, shard burst)
game/       TrialRoomManager (composition root), CharacterStage, MinigameRunner, roaming text
minigames/  MinigameBase + one script per minigame type; debate/ for shared pieces
tools/      Start-menu file picker, small editor/debug helpers
ui/         DialogueBox, HUD gauges, cards, settings menu, mobile touch HUD
```

`TrialLoader` is a thin facade: `core/trial/trial_archive.gd` does ZIP
extraction and `core/trial/character_library.gd` owns character data and the
sprite-texture cache. `TrialRoomManager` is a composition root that wires
`ScriptDirector` signals to `CharacterStage` (3D bench sprites) and
`MinigameRunner` (the minigame catalog and replay loop).

### Autoloads (project.godot)

| Autoload | Role |
| --- | --- |
| `Log` | Leveled logging (`debug`/`info`/`warn`/`error`), the first autoload registered. Everything below the threshold is dropped: `DEBUG` in a debug build, `WARN` in a release build, overridable with `DANGAN_LOG_LEVEL` (`DANGAN_VERBOSE=1` still means `debug`). Contributors log through this, not `print()`. |
| `TrialLoader` | Extracts `.drtrial`, parses `trial.json`, caches character data and sprite textures. Sync path for direct scene launch, threaded async path behind the loading screen. |
| `ScriptDirector` | State machine that walks script lines (speaking / narrator / minigame) and emits signals the trial room reacts to. |
| `AudioManager` | Voice line playback. |
| `InputManager` | Central input → signals (advance, skip, settings, focus). |
| `InfluenceGauge` / `ConcentrateGauge` | Player health / slow-time meters (state only; UI scenes bind to them). |
| `TruthBulletManager` | Evidence available to the current minigame. |
| `CameraDirector` | Executes per-line camera motions from script data. One at a time: a new motion cancels the running one through its `CameraMotionContext`, which covers the motions that await as well as the ones that tween. |
| `ScreenEffects` | Full-screen effects requested by script lines. |
| `Settings` | User preferences persisted to `user://`. |
| `GameRandom` | Seeded RNG streams so a session is reproducible (`DANGAN_SEED` env var). |

### Flow

1. `start_menu.tscn` → `TrialFilePicker` selects a `.drtrial` →
   `loading_screen.tscn` drives `TrialLoader.load_trial_async()`.
2. `thh_trial_room_1.tscn` opens; `TrialRoomManager` seats the cast on benches
   and connects to `ScriptDirector` signals, then starts the script.
3. Speaking/narrator lines go through `DialogueBox` (typewriter, highlights,
   voice); camera and screen effects come from per-line script data.
4. A minigame line hands off to `MinigameRunner`, which instantiates the
   matching `MinigameBase` subclass (`MinigameCatalog.SCRIPTS`). The
   base class provides lifecycle, timers, managed signal connections, and
   standard HUD setup via `ResourceRegistry`. Success advances the script;
   failure replays the minigame; a depleted influence gauge ends in the
   game-over screen. The gauge is reset once per minigame *line*, so damage
   carries across replays of the same line, and `MinigameRunner.MAX_ATTEMPTS`
   caps the loop for the three minigames that never damage it.

### Adding a minigame

A new `gameType` string is registered in seven places. None of them validates
against another except the first two, so work down the list in order.

1. **`schema/trial.schema.json`** — add it to the `gameType` enum. That enum is
   a closed list, so a trial using an unlisted type fails schema validation
   before anything else gets a chance to run. This is the "To change the
   format" workflow above, and it comes first for the same reason.
2. **`MinigameCatalog.SCRIPTS`** (`scripts/core/trial/minigame_catalog.gd`) —
   the script path, keyed by `gameType`. This table is normative:
   `TrialValidator` warns about a type that is not in it, and
   `test_trial_manifest.gd` asserts it matches the schema enum exactly, so
   step 1 without this one fails CI. It sits in the data layer because both
   the validator and `MinigameRunner` read it, and the validator runs during
   parsing, before any scene exists.
3. **`scripts/minigames/my_game.gd`** — the `MinigameBase` subclass. Implement
   `start()`, call `_finish(success, data)`, and override `validate_data()` if
   empty or malformed authoring can make it unwinnable — `MinigameRunner`
   skips a minigame that reports errors rather than replaying it to the
   attempt cap.
4. **`ResourceRegistry.SCENES`** — any scene it instantiates. A missing entry
   is a `push_error` and then `add_child(null)`.
5. **`web-ui-editor/js/views/minigames/`** and the label in
   `js/core/constants.js` — the authoring UI (see the web UI README).

Then the polish, none of which breaks anything if skipped:

6. **`minigame_title_card.gd`** — `title_names` (without an entry the card
   reads `REBUTTAL_SHOWDOWN`, since `to_upper()` keeps the underscores) and
   `title_colors` (without one it falls back to grey).
7. **`MinigameConfig.SPAWN_INTERVALS`** — only if the minigame spawns on a
   timer; the fallback is 2.0s.

## Scene-owned UI

Editable UI is authored in `.tscn` scenes; scripts bind data and trigger
animations, they don't build node trees. This covers the settings menu, the
mobile HUD and toast, the screen-effects overlay, and the per-item minigame
pieces (Hangman slots, Debate Scrum keyword buttons, Logic Dive lanes, the
Nonstop Debate bullet preview and evidence card, the fallback file list). New UI
belongs in a scene, instantiated via `ResourceRegistry`.

What stays in code is narrower than it used to be. Effects that were once
built node by node are now scenes with their own AnimationPlayer clips: the
shatter and particle systems are `scenes/effects/*.tscn` spawned through
`ResourceRegistry`, the slow-time vignette plays `show`/`dismiss` clips from
its scene, and `ScreenEffects.cross_dissolve` delegates to the overlay's
`fade_pulse` clip. `EffectBuilders`, which this section used to name, was
deleted in `41fe39f`.

Three things genuinely stay in code, each for a reason the code states:

- **Camera effects** — `screen_shake` and `fov_pulse`. They need runtime
  `Camera3D` positions, which a clip cannot know
  (`screen_effects_manager.gd:8-9`).
- **The `roaming_text_path` curve** — it refits the live viewport, and the
  character count is data-driven. The characters themselves are
  `roaming_char.tscn` instances with a looping clip
  (`roaming_text_path.gd:2-6`).
- **Gauge fills and the typewriter** — per-frame values driven by data, not
  fixed timelines.

## UI textures

`freestyle-dangan-trial/textures/ui/` is the single runtime texture set; node
sizes are defined in scenes and never derived from texture resolution, so
swapping art never moves layout. Stretch mode is `canvas_items` with
`aspect=expand` on a 1280x720 base, so resizing the window scales the whole
canvas; the Settings "UI Scale" option (`Window.content_scale_factor`) layers
an optional extra zoom on top of that rather than being the only scale. Full
rules,
including why 9-slice sources must stay at design resolution, live in
`freestyle-dangan-trial/textures/ui/README.md`.

## Known debt

- `scenes/thh_trial_room_1.tscn` — the room the runtime actually loads
  (`loading_screen.gd`, `vbox_selector.gd`) — embeds ~97MB of mesh data. It
  stays under GitHub's hard limit but should eventually reference external
  mesh resources. The gitignored `thh_default_trial_room.tscn` is referenced
  by nothing at runtime; it is a local-only authoring asset kept out of git
  because its embedded meshes exceed GitHub's file size limit.
- A few authored fields aren't wired up yet: `characterSpotlight` (reserved for
  an unimplemented lighting effect), white-noise debate lines (disabled pending
  a layout rework). The camera motions, screen effects, highlight ranges and
  the lie/negative-bullet toggle the editor authors *are* interpreted.
