# Authoring pieces and automation

A new piece needs a definition and a model scene. The definition makes it a catalog asset; the scene supplies its visible geometry, collision, and optional behavior. This guide is for developers adding or maintaining those assets. For what the existing mechanisms do, see [Mechanisms](MECHANISMS.md).

Every placed object is a `BuildingPiece`, whether it is a track, an adjustable support, a gate, or scenery. Static models need no behavior script. Functional models compose `PieceBehavior` nodes, and the common instance discovers them throughout the model hierarchy, including the root. The definition's `behavior` field is only a catalog tag.

## Kenney environment pieces

The expanded catalog adds 52 Building Kit models and 86 Factory Kit models through the existing YARD registry. Let Godot create resource UIDs. Reload the project after adding definitions so Godot imports the resources and YARD refreshes its saved index; Play and export also rebuild the index. Registry entry IDs must match `PieceDefinition.id`. There is no separate scenery catalog or runtime asset scan.

The Building additions cover corner borders, partitions and plating, diagonal/round floors, flat roofs, closed/open stairs, columns, round doorways, windows, static doors, barricades, pipes, and gutters. The Factory additions cover catwalk junctions and stairs, modular conveyor structures, floors and caps, frames and walls, solid/glass pipes and fittings, hoppers, static cranes/scanners/machinery, robot arms, pistons, screens, gears, and warning props. Scenery uses Architecture, Pipes, and Props in the browser. Architecture contains building elements, doors, and tunnel arches; Pipes groups modular solid/glass pipes and fittings; Props contains static machinery and decorative objects. Starts & ends combines marble releases, finish catchers, and ordinary track ends; only the catcher supplies a finish behavior. Existing definition and instance IDs are unchanged.

Open wrappers under `scenes/environment/` to inspect imported models, origin adjustments, and authored collision. Of the 138 additions, 107 use saved mesh collision under `scenes/environment/collision/`, five planar factory floors/caps use a 10 cm slab, and 26 are selection-only decorations. Definitions hold measured occupied boxes for placement, preserving openings for doors, frames, catwalks, and pipe bores. Those boxes approximate geometry in 10 cm cells; physics uses the authored shapes. Flat faces use shared surface placement. These models have no fabricated track connectors.

Robot arms, piston details, screens, gears, warning props, gutters, and small pipe details are selection-only: marbles pass through them. Static conveyors, cranes, scanners, and machines have no motor, transport, sensor, or signal behavior; their descriptions state this. All new definitions are ordinary construction pieces, so authors can grant inventory or keep starting instances fixed through existing permissions.

The asset pass inspected all 79 Building and 143 Factory GLBs, including node hierarchies, transformed vertices, pivots, and triangle geometry. It retained existing uses, kept guidance icons outside construction, and omitted redundant conveyor paint variants, alternate door poses, duplicate barricades/gears, inert control lookalikes, and the unrelated mascot. Original imported assets are unchanged.

The short and tall factory support frames also retain the ordinary construction IDs `factory-structure-short` and `factory-structure-tall`, used by the menu machine example and personal tracks. They share the models and placement geometry of their `environment:` counterparts, which remain authoring-only puzzle scenery. Keep both identities registered; personal-track decoding excludes authoring-only definitions.

## Start from a working piece

Open a suitable definition under `resources/pieces/` and follow its Model reference. Functional wrappers live under `scenes/mechanisms/`. The sensor is a small example: its scene combines track collision, a detection area, an animated indicator, and a behavior script. The gate and launcher demonstrate moving collision and exported node references; the elevator and supports demonstrate adjustable assemblies.

For a variant, duplicate the wrapper and definition, assign a new stable ID, and set its display name, category, thumbnail, and model. Make shared resources unique before changing them. Preserve imported GLBs; assemble and adjust them in the wrapper scene.

Inspect the actual mesh, pivot, orientation, and hierarchy before defining connectors or placement geometry. A filename does not establish dimensions. Bounds, occupied volumes, and surface samples affect placement; the collision shape affects marble travel. They need to agree closely enough that a valid preview represents a usable physical object.

Ordinary meshes receive generated triangle collision. Set **Native collision** when the wrapper owns its collision shapes, as the mechanical scenes do. Existing mesh-matched shapes live under `scenes/mechanisms/collision/`. A decoration that should remain selectable without blocking marbles can disable physical collision and use the common pick bounds.

The live scene hierarchy is the authority for meshes and collision bodies. Tinting, preview bounds, and drag ray exclusions query its current descendants rather than retain geometry lists. After behaviors rebuild configurable geometry, `BuildingPiece` generates collision only for meshes without an authored physics owner; preview instances instead disable all collision objects. Keep dynamic geometry under the piece so these operations include it automatically.

## Give the instance settings

Author editable fields on the behavior's **Configuration fields** array using `PieceSetting` resources. Each field declares a key, label, description, kind, default, and, for numbers, range, step, and unit. For example, the sensor scene declares the flag `detect_exit`, shown in the inspector as “Emit exit event.” The script reads that key from its configuration when a marble leaves.

The same saved resources supply the inspector, definition normalization, and authoring restrictions. `PieceDefinition` reads scene metadata through `SceneState`, including nested and inherited scenes. Keep these declarations in the scene rather than add a second settings table in UI code.

Configuration has three stages:

- `normalized_configuration()` prepares saved overrides. The base implementation normalizes declared values that are present, leaves omitted defaults omitted, and retains unknown keys such as `links`.
- `resolved_configuration()` fills defaults before passing settings to behaviors.
- `configured()` returns the definition used for instance geometry. The base returns itself; adjustable subclasses return adapted geometry without mutating the catalog resource.

Use `SupportDefinition` or `ElevatorDefinition` as references when a setting changes bounds or connectors. Their normalizers also materialize geometry settings. Existing **Height setting**, **Ground placement**, and **Height offset** properties connect adjustable pieces to contextual placement; do not reproduce that logic in an inspector widget.

## Implement the behavior lifecycle

Extend `PieceBehavior`. `configure(settings)` stores resolved configuration and calls `reset()`. Call the base implementation when overriding it. Reset must restore configured initial state and clear timers, captures, and other run work. `start_run()` begins activity; `active` changes on pause, resume, and run end and emits `activity_changed`. `enabled` is the behavior's own setting, distinct from whether the simulation is running.

Preview instances set `preview_only`, disable processing, and remove collision participation. Initialization must still work when the scene is created as a preview. Do not begin a run in `_ready()` or require an application menu to exist. Native Timer nodes must also stop advancing when activity is suspended: the timer module starts automatic timing in `start_run()`, disables its child clock processing while inactive, and stops the clock on reset. Keep a wired Stop command separate from simulation pause so resume does not undo it. The timer uses its configured value directly as seconds; the legacy `frequency` save key is retained for compatibility, while the inspector calls it Duration.

Behaviors can return world-space points from `build_trajectory(excluded)` for the shared `SelectionOverlay` to draw when selected or previewed. The default returns no path. The overlay's depth-tested 3D mesh updates during physics processing; its excluded body RIDs omit hidden moving originals. The launcher uses the same velocity calculation for its shot and its gravity arc, sweeping the shared `scenes/marble_shape.tres` collision shape until first contact. No separate physics simulation or piece-specific overlay is needed.

The sensor illustrates the division: `_ready()` connects detection signals and declares its pulse outputs; entry/exit callbacks update occupancy while running; reset clears occupancy and returns the indicator to idle. A bucket elevator has more state to restore, but follows the same lifecycle. If a behavior captures a marble, restore its physics and collision on release and reset, and preserve capture correctly through pause.

### Declare ports

Pulse inputs are callbacks in `inputs`; pulse outputs are names in `outputs`. This minimal example shows the contract:

```gdscript
extends PieceBehavior

func _ready() -> void:
    inputs = {"trigger": _trigger}
    outputs = ["finished"]

func _trigger(value: Variant) -> void:
    emit_output("finished", value)
```

`receive()` handles the input's running/preview checks before calling the callback. Use `emit_output()` rather than emit `output_raised` directly, so declaration checks and persistent state handling remain intact.

State ports describe a value that remains meaningful between events. Declare initial values in `state_inputs` or `state_outputs`; a state input also needs its callback in `inputs`. Base reset restores those values. The sensor, for example, exposes `occupied` alongside its `entered` and optional `exited` pulses. Occupied stays true until the last detected marble leaves.

Keep port names and setting keys unique across components on one piece. Links address a piece UID and a port name, not the behavior's node path. Pulse outputs connect to pulse inputs and state outputs to state inputs. The component contract allows more behaviors to be composed. The logic modules in `scenes/mechanisms/logic/` demonstrate event memory, counting, and persistent boolean evaluation without polling.

Simulation queues outputs in FIFO order, preserving emission and saved-link order. Receiver outputs join that queue. State outputs suppress unchanged values, and persistent wires are seeded at run start and on resume. During initial seeding, `initializing_signals` is true. After the queue settles, simulation calls `signals_ready()` on each behavior; call the base implementation when overriding it. Gates defer rising events to this hook, so transient initial state deliveries cannot fire pulse-driven mechanisms. Resume only reseeds states and does not call this hook. A non-settling transaction fails after the scene's delivery limit, default 16,384. When implementing feedback, check both initial state and reset rather than assume an entry event will always arrive.

## Register and verify

Save the definition in YARD's `resources/registries/piece_registry.tres`. The entry ID must equal `PieceDefinition.id`; saves and published content depend on that identity. `PieceCatalog` handles loading and filtering, so no runtime directory scan or second catalog is needed.

Editor Play and export rebuild the registry index. Headless runtime tests consume the saved index, so ensure it is current before diagnosing a missing entry there. If a piece changes online compatibility, regenerate both [community catalog manifests](COMMUNITY_SERVICE.md#api-v1).

Check placement and rejection previews, settings, duplication, undo/redo, save/reload, and puzzle restrictions. Run the mechanism through start, pause, resume, and reset. Geometry and transport changes also need real collision tests, including multiple marbles where relevant. A correctly declared connector or passing parser cannot establish a successful physical transition.

## Wire a machine

In the game, choose **Connect**, drag an output terminal onto a compatible input terminal, and choose the ports/actions in the relationship card if needed. For example, connect a sensor's `entered` output to a gate's `open` action. Escape cancels the drag or card, then leaves Connect mode. Snapping follows the visible input handle, not the entire piece. The pending wire stays visible while the relationship card is open; Apply commits it and Cancel discards it.

**Wires** independently displays directional relationships during ordinary building. Click a wire to inspect, change, or remove it; selecting a functional piece isolates its direct incoming and outgoing links. Multiple selected functional pieces combine their links; clearing selection or selecting only ordinary track restores the full network. Connect keeps all terminals available for new relationships. Simulation hides this editing presentation and reset restores the previous Connect mode.

The UI calls `BuildManager.edit_link()`, so configuration permissions, validation, and undo/redo apply. Links are stored under the source instance's `config.links`:

```json
{"event": "entered", "target": "gate-instance-uid", "action": "open"}
```

Here `gate-instance-uid` stands for the target instance's saved UID, not its catalog ID. Duplicating a whole assembly remaps internal targets to the copies. Removing a target prunes links to it. Keep new wiring features within that operation contract so player rules and saved machines stay consistent.

## Author a mounted control

The five definitions are `resources/pieces/logic-{memory,counter,and,or,not}.tres`. Their model scenes are under `scenes/mechanisms/logic/`; `module_housing.tscn` provides the shared mounting plate, colored cover, terminals, indicator, and pick shape. Open an individual scene to edit its material overrides, terminal visibility, labels, scene-authored settings, and behavior references. The counter additionally authors its display bezel, numerical face `Label3D`, and optional billboard count readout. Static geometry is saved in scenes; behaviors update only state lamps and text.

For another accessory, author its contact at the model origin, with local +Y pointing out of the supporting surface. Keep bounds, collision solids, and authored geometry consistent, leaving a small clearance above the contact plane. Set `PieceDefinition.surface_mounted` and register the definition normally. This capability uses the same `SnapManager` cursor collision hit, preview assembly, validation, and BuildManager operations as other pieces. Contacts snap to the existing 0.5 m construction grid in the mounting piece's local surface plane, centered on its definition bounds. The snapped position is checked against the same physical collider so edges and curved faces cannot leave an accessory floating. R changes the twist about the surface normal. Mounted accessories cannot support other accessories; stationary construction bodies supply the mounting surface. Pick-only collision keeps compact electronics from blocking marble travel while collision solids reserve their construction volume.

`config.mount_target` is the supporting construction UID. `config.mount_basis` is a nine-number, column-major, right-handed orthonormal world basis. Existing position and yaw fields remain present; the full basis applies only to surface-mounted definitions. These reserved configuration keys are placement metadata rather than inspector settings. Files without them retain the existing yaw representation; old tracks and puzzles need no migration. New mounted pieces require both fields, a valid registered supporting piece, and contact with its occupied geometry. Track/puzzle validation rejects missing targets, scaled/reflected bases, and mounting metadata on ordinary definitions.

BuildManager expands support edits to include accessories before permission checks. A rigid assembly preserves world offsets and orientations; duplication remaps attachment UIDs along with internal wire targets. History captures the complete operation. Moving an accessory alone chooses a new surface, and deleting a support removes its accessories atomically. Puzzle rules compare full orientation using rotate permission, and attachment target changes using move permission, independently of mechanism-setting permission.

The shared gate behavior exports its operation in each scene, while ports are declared by the behavior itself. New behaviors use the same `PieceSetting`, `receive()`, `emit_output()`, reset, and signal initialization contracts. Add new IDs through YARD and regenerate both community manifests after changing mounting capability, settings, or ports. Catalog thumbnails are rendered from saved scenes in `resources/thumbnails/logic-*.png`; refresh them when changing the model.

## Loading a launcher

The launcher uses `Marble.capture()` for its waiting queue and restores that snapshot on firing, reset, and scene removal. `loaded` is a persistent state for a seated marble with the paddle ready; `fired` remains a pulse. Its scene owns track collision and declares native collision so the editable hinged paddle, cheeks, and animated arm cannot accidentally become obstacles through generated mesh collision. The Detection area is only a broad-phase trigger: capture additionally requires the marble center to be at deck loading height and behind the armed seat. Airborne marbles and the space beyond the front lip remain ordinary physics. `Arrow/Handle/Seat` carries the captured marble during the front-pivot stroke and coincides with `ReleasePoint` at release; actual launches and trajectory prediction share that fixed point. Saved speed/angle settings and piece IDs are unchanged.
