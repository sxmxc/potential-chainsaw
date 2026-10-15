# Architecture

## Application and workspace

`scenes/main.tscn` runs `GameManager`, which hosts navigation, menus, dialogs, settings, and the community service. `scenes/construction_workspace.tscn` contains the shared World, `ConstructionSession`, HUD, and authoring drawer. `ConstructionWorkspace` binds them and handles context actions; application actions travel to GameManager through signals.

`ConstructionSession` owns four contexts:

| Context | Construction and persistence |
| --- | --- |
| Sandbox | Unrestricted player catalog; personal track identity and saves |
| Authoring | Starting layout, scenery, metadata, rules, draft saves, publication |
| Puzzle Play | Loaded official or community puzzle under `PuzzleRules` |
| Player Test | Isolated authored copy with the same player rules; successful runs can become reference solutions |

Context transitions reset simulation, tools, restrictions, environment, and construction history before loading the new data. Session `context_changed` signals a transition; `changed` refreshes metadata/progress. Returning from a player test restores the captured authoring baseline. Simulation reset retains the current player construction.

`scenes/world.tscn` and `WorldManager` compose BuildManager, SimulationManager, boundaries, and cameras. The workspace can operate without the main menu. It is the common editing and physics path for every mode.

## Construction and resource registries

`BuildManager` owns placement, direct manipulation, selection, configuration, wiring edits, and Godot `UndoRedo` history. It validates complete proposed layouts before committing; a rejected member rejects a group edit. History stores construction snapshots and restores selection through stable instance IDs. Duplication remaps links within an assembly; removal cleans dangling targets.

`SnapManager` owns connector topology, cursor-directed attachment candidates, and placement geometry checks. Compatible exposed connectors align the full transform, including elevation. Scenery surface attachment uses collision hits and measured occupied volumes; the grid/active height supplies free placement. Preview and commit validate the complete group. Direct dragging keeps a stable grab plane and cursor offset, retaining internal height differences.

`BuildingPiece` is the common placed node. `PieceDefinition` supplies stable identity, scene, presentation, connectors, and measured geometry. Its `normalized_configuration`, `resolved_configuration`, and `configured` methods separate saved overrides, runtime defaults, and instance geometry. `ElevatorDefinition` and `SupportDefinition` adapt geometry without modifying shared resources.

YARD's `resources/registries/piece_registry.tres` defines membership and indexes `category` and `behavior`. Entry IDs must match `PieceDefinition.id`. `PieceCatalog` resolves via `Registry.load_entry`, filters with `Registry.where`, retains loaded resources, and sorts presentation. Categories come from definitions. Supports resolve their component resources through that same registry.

The installed YARD build hook rescans/reindexes on editor Play and export. Headless runtime tests use the saved index; they do not run that hook. The installed README's manual reindex advice does not match its disabled Reindex button. Consult the addon implementation/class reference without editing vendor documentation.

All placed objects use the shared registry and `BuildingPiece`; there is no separate scenery catalog or arbitrary-scene placement workflow. A remaining distinction applies to definitions marked `authoring_only`: PuzzleEnvironment saves these as `environment_instances` and loads them as fixed geometry outside player inventory. Ordinary props such as trees are regular construction pieces and do not use this path. See [Puzzle formats](PUZZLE_AUTHORING.md#formats-and-storage).

## Behaviors, physics, and automation

`BuildingPiece` discovers `PieceBehavior` nodes throughout its model, including the root. Static pieces have none; a piece can compose multiple behaviors. The definition's `behavior` field is a catalog tag. Functionality comes from the scene, rather than a central mechanism factory.

Behavior nodes own settings, ports, gameplay, and reset state. Scene-authored `PieceSetting` arrays supply both inspector fields and definition validation. Definitions read saved scene metadata through `SceneState`, including nested/inherited scenes. Ordinary GLBs use generated mesh collision; native-collision scenes retain authored shapes. See [Piece authoring](PIECE_AUTHORING.md) for the extension contract.

`SimulationManager` owns run states (`BUILD`, `RUNNING`, `PAUSED`, `SUCCESS`, `FAILED`), marbles, objectives, and signal delivery. Releases schedule/spawn bodies; collectors report deliveries. Ordinary travel uses `Marble`, a `RigidBody3D`. Elevator buckets temporarily capture bodies using Marble's physics snapshot and restore them on release/reset. Pause retains velocities and capture state. Reset clears runtime bodies, behavior state, and queued signals.

Ordinary Sandbox runs require exactly one release and have no timer; a catcher ends the run on arrival. Puzzle contexts support multiple releases, evaluate all authored objectives, and use `time_limit` (90 seconds when absent). Lost marbles fail a run. Delivery counts distinct marbles, optionally from one release; activation objectives require a named output to have occurred. Activation quantity is not counted. Completion does not compare layouts to a reference solution.

Behaviors expose pulse and persistent-state ports. Links live in source configuration as `{event, target, action}` using stable instance IDs. BuildManager validates port declarations/compatibility; its `edit_link` uses normal permissions and history. Simulation propagates outputs FIFO in emission/link order. State ports suppress unchanged values and seed connections at run start. Non-settling propagation fails after the scene's delivery limit (default 16,384) in one transaction.

## Navigation, cameras, and presentation

GameManager owns `CommunityService`, configured with the session's PuzzleStore and `SupabaseCommunityBackend`. The adapter uses the `SupabaseClient` autoload; no separate client is instantiated by the game. UI consumes the game-facing result contract. [Community service](COMMUNITY_SERVICE.md) owns backend, authentication, and deployment details.

Autoloads are `SoundManager`, `PhantomCameraManager`, `SupabaseClient`, and `SteamClient`. Construction input defaults live in `project.godot`; `ConstructionInput` applies/restores the game's keyboard overrides, saved in `user://settings.cfg`, without resetting addon actions.

Saved UI scenes under `scenes/ui/` and `resources/sandbox_theme.tres` own layout/styling. WorkspaceHUD binds shared controls; the selection inspector owns piece settings and permissions; the Connect tool owns mechanism relationships; the authoring drawer owns definition-wide data. Toolbars emit actions. See [UI design](UI_DESIGN.md).

`SimulationCamera` coordinates marble selection and `scenes/camera/marble_chase.tscn`. Phantom Camera owns the rendered transform; the construction camera retains the free-view pose. Chase targets follow motion rather than marble rotation. Stopping, reset, completion, or target loss restores the free view. Spring-arm clearance can still leave a close view obstructed inside enclosed mechanisms.

The menu showcase has a separate SubViewport/World3D and loads `resources/menu_machine.json` through the same construction/simulation systems. AnimationPlayer provides its wide motion; `MenuCameraDirector` schedules detail/chase shots on separate host layers. GameManager switches music at menu/workspace transitions because both worlds stay loaded. Showcase simulation must not write player constructions or progression.

## Verification

`project.godot` targets Godot 4.7 with Jolt at 120 Hz. See the [README](../README.md#development) for bundled versions, GUT invocation, and export setup. Run suites by filename with `-gselect=construction_groups`, for example. GUT is the supported runner.

`.gutconfig.json` discovers `tests/test_*.gd`. Pure tests extend `GutTest`. Persistence tests use `tests/support/game_test.gd`, which temporarily redirects application saves with `MARBLE_ENGINEER_TEST_DATA` into unique `user://gut-tests/` fixtures and removes them. Scene tests extend `scene_test.gd` to restore display, input, and audio state. Do not redirect APPDATA or Godot caches.

`SaveStorage` owns save-path resolution, identifier checks, and JSON file replacement. TrackSerializer, PuzzleStore, and PuzzleProgress own their formats and call `write_json` directly; an empty error string means success. The writer flushes and checks the temporary file before replacing the destination, and removes the temporary file if replacement fails. PuzzleStore retains ownership of campaign publication rollback across its three files. Settings use Godot's ConfigFile format.

Focused suites cover construction/groups/snapping, mechanisms and elevator transport, campaign rules/progression, authoring/distribution, cameras, UI, and community/client behavior. `test_campaign.gd` exercises the ten Introduction reference solutions and incomplete starts. These are regression checks, not proof of puzzle quality or unlimited physics reliability. Headless tests cannot establish visual quality; exercise affected interactive workflows when changing them. Backend checks and opt-in live tests are described in [Community service](COMMUNITY_SERVICE.md#verification).
