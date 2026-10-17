# Architecture

Marble Engineer has one construction workspace. Building freely, editing a puzzle, and solving that puzzle all use the same placement, selection, wiring, and physics code. The important difference is the data and permissions loaded into that workspace.

This guide explains those boundaries and where a change belongs. For hands-on workflows, see [Piece authoring](PIECE_AUTHORING.md), [Puzzle authoring](PUZZLE_AUTHORING.md), and [UI design](UI_DESIGN.md).

## Application and workspace

`scenes/main.tscn` runs `GameManager`, the application host. It owns navigation, dialogs, settings, and the community service. `scenes/construction_workspace.tscn` combines a World, a `ConstructionSession`, and the shared HUD. `ConstructionWorkspace` binds them and sends application actions to GameManager through signals. The workspace can also operate without the main menu.

The session determines what the construction means:

| Context | Data and rules |
| --- | --- |
| Sandbox | Unrestricted player catalog and personal track saves |
| Authoring | A puzzle's starting layout, scenery, metadata, rules, and draft/publication actions |
| Puzzle Play | An official or community puzzle enforced by `PuzzleRules` |
| Player Test | An isolated authored copy using the player's rules, with the ability to preserve a successful solution |

A player test is a useful example of why these contexts share an implementation. The session captures the authored baseline, then loads it through the same player path used for puzzle play. The author must solve with the actual inventory and permissions. Returning to the editor restores the baseline; it does not replace the incomplete starting machine with the solved construction.

Context changes clear the previous run, tools, rules, environment, and history before loading new content. A simulation reset is smaller: it removes runtime marbles and resets behaviors while retaining the current construction. Features that load a different puzzle belong in the session; features that reset a run belong in simulation.

`WorldManager` in `scenes/world.tscn` binds construction, simulation, boundaries, and cameras. Hosts enable input through `set_input_enabled()`. WorldManager then enables building only in the BUILD state while no boundary interaction owns the pointer. This keeps a reset from accidentally re-enabling editing behind a dialog. Worlds begin with input disabled.

## Editing is a validated change

`BuildManager` owns construction edits and UndoRedo history. An edit first describes a proposed result, checks geometry and player rules, and only then changes live pieces. `validate_edit()` is shared by placement previews and commits. Rejection must leave the machine, selection, and history intact.

During placement, movement, and duplication, `BuildManager/PlacementPreview` is a Node3D assembly containing preview `BuildingPiece` children. Each child holds its configuration and local transform; the parent holds the proposed group transform. Snapping and validation read this assembly through `placement_items()`. This makes an elevator's adjusted height, for example, part of the same proposal the player sees and commits.

Preview children also carry their final instance IDs. Moving retains the original IDs; duplication assigns fresh IDs and remaps internal wires and mounts while preparing the preview. Validation reads those identities and references directly, and commit retains them without another remapping pass. Repeated placement assigns a fresh preview ID after each commit. Saved IDs remain opaque, so no reserved placeholder IDs can collide with an existing construction.

Movement hides the originals while the preview is active. Cancellation restores them. A confirmed group operation produces one history entry containing construction snapshots; stable instance IDs restore selection. Duplicating an assembly remaps links between its members, while deleting targets prunes dangling links. New edit tools should use these operations rather than mutate nodes behind the history system.

### Snapping and placement geometry

`SnapManager` finds cursor-directed attachment candidates and checks placement geometry. An exposed compatible track connector aligns the whole transform, including elevation and orientation. It takes precedence over the free-placement grid plane. Surface attachment instead uses collision hits and measured occupied volumes; without a suitable attachment, the active grid height supplies placement.

Surface-mounted definitions align local +Y to a stationary construction collision normal. Their contact and full world orientation persist through shared attachment metadata in configuration. Supporting-piece edits include accessories atomically; standalone accessories can be remounted. Fixed environment pieces and moving mechanism bodies are excluded as mounting targets. See [mounted control authoring](PIECE_AUTHORING.md#author-a-mounted-control) for the persistence and geometry contract.

A group remains a rigid assembly during a drag, including differences in height. Its own pieces are excluded from snap targets. Maintaining that relationship matters more than independently snapping every member, which would deform the machine.

Placement geometry and physics collision serve different purposes. Bounds and occupied volumes help reject overlapping constructions and find surfaces. Mesh collision or authored shapes determine how a marble actually contacts a piece. Passing placement checks does not prove the route will work in a run.

## Pieces, definitions, and the catalog

A `BuildingPiece` is a placed instance. Its `PieceDefinition` is the shared resource describing identity, presentation, model scene, connectors, and placement geometry. The instance stores a stable UID and configuration. Those two identities have different jobs: the definition ID selects an asset; the UID identifies a particular gate or catcher in a saved machine.

Definitions separate three configuration operations. `normalized_configuration()` prepares saved overrides, `resolved_configuration()` fills runtime defaults, and `configured()` supplies instance-specific geometry. `ElevatorDefinition` and `SupportDefinition` adapt bounds/connectors without changing the shared definition. This is why changing one elevator's height does not resize every elevator using that resource.

YARD's `resources/registries/piece_registry.tres` is the catalog authority. `PieceCatalog` resolves resources through `Registry.load_entry()` and queries indexed fields through `Registry.where()`, then sorts them for presentation. Entry IDs must equal `PieceDefinition.id`. Editor Play and export rebuild the registry index; headless runtime tests read its saved state. Add pieces to this registry rather than scan folders at runtime.

Tracks, mechanisms, supports, and scenery use this common piece system. Definitions marked `authoring_only` are a special case for puzzle environments: authors manipulate them with the shared tools, then `PuzzleEnvironment` saves them as `environment_instances` and loads them as fixed geometry during play. Ordinary decorative props remain regular construction pieces. The distinction is a definition flag, not whether an object looks decorative.

## Behaviors, physics, and automation

A model scene may contain any number of `PieceBehavior` nodes, including its root. `BuildingPiece` discovers them and applies instance configuration. The definition's `behavior` string is a catalog tag; changing it does not create functionality. Settings are scene-authored `PieceSetting` resources, read by definitions as well as the inspector. [Piece authoring](PIECE_AUTHORING.md) explains how to extend this contract.

`SimulationManager` owns BUILD, RUNNING, PAUSED, SUCCESS, and FAILED states. At run start it validates wiring, captures the construction, starts behaviors, and seeds persistent signal connections. Releases spawn `Marble` rigid bodies, and collectors report deliveries. Behaviors own their mechanical state; simulation owns the run and its outcomes.

Release and collection bookkeeping uses the same `released` and `collected` behavior outputs as wiring and objectives. A release assigns its ordinal to the marble before emitting it. Through `PieceWiring.output_observed`, SimulationManager adopts and identifies that body, or records its delivery, before wired receivers run. PieceWiring owns all run subscriptions and disconnects them on reset; there are no separate release/collector signal connections retained on construction nodes.

Ordinary marble motion uses rigid-body physics. The bucket elevator temporarily captures a marble and carries it deliberately, restoring its saved physics/collision state when released or reset. Pause preserves velocities and capture state. Reset clears bodies, behavior state, and queued signals. A mechanism that captures marbles needs to respect all three transitions, including the case where several marbles are waiting or in transit.

Ordinary Sandbox testing requires at least one release, runs every placed release, and has no deadline. A catcher ends that run on arrival. Puzzle contexts may have several releases and must satisfy every authored objective before the run deadline; an omitted deadline defaults to 90 seconds. Losing a marble fails the run. Delivery objectives count distinct marbles, optionally from one release. Activation objectives record that a named output occurred, not how often. No objective compares the player layout to a reference solution.

### Signals between pieces

Links are saved on the source instance in `config.links` as `{event, target, action}`. The target is a UID and the other fields are port names, so reorganizing a model's internal nodes need not break saved wiring. `BuildManager.edit_link()` applies the normal permission, validation, and history rules.

Pulse ports describe events; state ports latch a value. `PieceWiring`, a child of SimulationManager, validates behavior contracts and links, resolves saved UIDs and ports to live receivers once per run, and owns behavior startup, pause/resume, and reset. It disconnects run connections on reset so edits and history restoration cannot retain old receivers. SimulationManager observes outputs for objectives and handles wiring failures as run outcomes. Authoring validation calls the same wiring validator; BuildManager owns only the edits.

PieceWiring delivers signals in FIFO order, preserving emission and saved-link order. Receiver outputs join the queue rather than recurse. State ports suppress unchanged values, allowing feedback to settle. A transaction exceeding the scene's delivery limit fails the run with a wiring error. This protects a run from an endless signal loop without silently dropping actions. Initial persistent states settle before the shared `signals_ready()` behavior hook exposes initial gate activation events; pause/resume reseeding does not repeat that hook.

## Persistence and distribution

`SaveStorage` resolves save paths, checks identifiers, and writes JSON through a flushed temporary file before replacement. TrackSerializer owns personal-track data; PuzzleStore owns puzzle drafts, publication, and installation; PuzzleProgress owns completion and route state. Settings use ConfigFile separately. Keep domain validation with those owners rather than add it to the generic writer.

Official campaign membership comes from the manifest loader, not a field supplied by a puzzle file. Community content has separate completion records and cannot replace an official entry merely by claiming its ID. Publication retains a separate starting layout, solution, and successful-test fingerprint. [Puzzle authoring](PUZZLE_AUTHORING.md#formats-and-storage) covers formats, paths, compatibility, and revision handling.

GameManager creates `CommunityService` with the session's PuzzleStore and a `SupabaseCommunityBackend`. UI requests game operations from the service; the adapter translates provider routes, authentication, and response envelopes. The generic `SupabaseClient` autoload handles JSON transport and password sessions. `SteamClient` owns local Steam integration and ticket handles. This boundary keeps online infrastructure out of puzzle rules and keeps local play independent of the service. See [Community service](COMMUNITY_SERVICE.md) for the server side.

## Presentation and cameras

`ConstructionWorkspace/Guidance` owns world-space guidance presentation for authored steps, editor previews, and objective location. It instantiates `scenes/guidance/marker.tscn`, which contains imported Kenney icons and editable materials, with no collision or construction membership. Selection, construction, context, simulation-state, and objective-progress signals update it; a one-shot timer ends previews. It has no per-frame processing. Placement hides its marker while existing snap/connector overlays own the target.

Puzzle format 3 adds bounded declarative `guidance` steps. Stable construction UIDs and connector indices resolve targets against live pieces; explicit points cover locations. Missing targets hide safely and produce authoring validation errors. Official Introduction content can show steps automatically; other puzzles require the player's Hint action. Goal briefly locates objective targets, cycling through multiple objectives without exposing a reference layout. The existing HUD guidance strip displays step text. Context changes clear state, and simulation reset restarts the sequence against the retained build.

Saved scenes under `scenes/ui/` own static layout; `resources/sandbox_theme.tres` owns shared styling. WorkspaceHUD binds the common controls, the inspector edits a selection, the Connect tool edits relationships, and the authoring drawer edits definition-wide data. `SelectionOverlay` projects connector handles and snap contacts from BuildManager's targets; construction does not create presentation nodes for them.

`WorldGuidance` owns all player-hint progression, including reading text-only `hints` from older puzzles when no authored sequence exists. WorkspaceHUD only displays its instruction and forwards Next or Close. The editor authors hints only in Objectives; there is no parallel Setup hint field, per-puzzle copy table, or HUD tutorial state. Puzzle descriptions supply objective text directly.

`ConstructionInput` applies saved keyboard overrides without resetting addon actions. The autoloads are SoundManager, PhantomCameraManager, SupabaseClient, and SteamClient. GameManager loads and saves settings and coordinates modal input suspension.

`SimulationCamera` selects marbles and coordinates `scenes/camera/marble_chase.tscn`. Phantom Camera controls the rendered view while the construction camera retains the free-view pose. Follow targets use motion rather than marble rotation. Stopping follow, reset, completion, or target loss returns to the free view; close views can still be obstructed inside enclosed mechanisms.

The menu showcase has its own SubViewport and World3D but uses the same construction and simulation systems to load `resources/menu_machine.json`. AnimationPlayer supplies wide motion and `MenuCameraDirector` schedules detail/chase shots. Both worlds remain loaded, so GameManager owns music transitions. The showcase must stay independent of player saves and progression.

## Verification

Use the GUT panel or the [README command](../README.md#development). `.gutconfig.json` discovers `tests/test_*.gd`; select a file with a flag such as `-gselect=construction_groups`. Pure tests extend `GutTest`. Persistence tests extend `tests/support/game_test.gd`, which redirects application saves through `MARBLE_ENGINEER_TEST_DATA` into a unique fixture and cleans it up. Restore globals and InputMap bindings locally; do not redirect APPDATA or Godot caches.

The default suite checks owners and contracts: editing, connector geometry, puzzle rules, distribution, save replacement, camera math, settings, and service behavior. It does not launch the full application, play campaign solutions, or call hosted services. Use interactive checks for the workflow a change affects, and actual simulation for physical routes. Backend checks are described in [Community service](COMMUNITY_SERVICE.md#verification).

For scene or script changes, let the open Godot editor discover resources and generate UIDs. Do not hand-author UID files or launch a second editor import against the same project: native addons can lock their hot-reload DLLs while the first editor is open. Runtime GUT commands can run alongside the editor.

When no editor is open, a headless editor import is also a useful parsing/resource check:

```powershell
godot --headless --editor --path . --quit
```

A clean parse and passing unit tests are useful evidence, but neither establishes that an authored machine works or that an interface is readable.
