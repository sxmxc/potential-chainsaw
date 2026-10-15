# Authoring pieces and automation

A new piece needs a definition and a model scene. The definition makes it a catalog asset; the scene supplies its visible geometry, collision, and optional behavior. This guide is for developers adding or maintaining those assets. For what the existing mechanisms do, see [Mechanisms](MECHANISMS.md).

Every placed object is a `BuildingPiece`, whether it is a track, an adjustable support, a gate, or scenery. Static models need no behavior script. Functional models compose `PieceBehavior` nodes, and the common instance discovers them throughout the model hierarchy, including the root. The definition's `behavior` field is only a catalog tag.

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

Preview instances set `preview_only`, disable processing, and remove collision participation. Initialization must still work when the scene is created as a preview. Do not begin a run in `_ready()` or require an application menu to exist.

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

Keep port names and setting keys unique across components on one piece. Links address a piece UID and a port name, not the behavior's node path. Pulse outputs connect to pulse inputs and state outputs to state inputs. The component contract allows more behaviors to be composed; it does not imply that logic-gate or sound-block pieces already exist in the catalog.

Simulation queues outputs in FIFO order, preserving emission and saved-link order. Receiver outputs join that queue. State outputs suppress unchanged values, and persistent wires are seeded at run start and on resume. A non-settling transaction fails after the scene's delivery limit, default 16,384. When implementing feedback, check both initial state and reset rather than assume an entry event will always arrive.

## Register and verify

Save the definition in YARD's `resources/registries/piece_registry.tres`. The entry ID must equal `PieceDefinition.id`; saves and published content depend on that identity. `PieceCatalog` handles loading and filtering, so no runtime directory scan or second catalog is needed.

Editor Play and export rebuild the registry index. Headless runtime tests consume the saved index, so ensure it is current before diagnosing a missing entry there. If a piece changes online compatibility, regenerate both [community catalog manifests](COMMUNITY_SERVICE.md#api-v1).

Check placement and rejection previews, settings, duplication, undo/redo, save/reload, and puzzle restrictions. Run the mechanism through start, pause, resume, and reset. Geometry and transport changes also need real collision tests, including multiple marbles where relevant. A correctly declared connector or passing parser cannot establish a successful physical transition.

## Wire a machine

In the game, choose **Connect**, drag a send handle onto a compatible receiving piece, and choose the ports/actions in the relationship card if needed. For example, connect a sensor's `entered` output to a gate's `open` action. Escape cancels the drag or card, then leaves Connect mode.

**Wires** independently displays directional relationships during ordinary building. Click a wire to inspect, change, or remove it; selecting a mechanism emphasizes related links. Simulation hides this editing presentation and reset restores the previous Connect mode.

The UI calls `BuildManager.edit_link()`, so configuration permissions, validation, and undo/redo apply. Links are stored under the source instance's `config.links`:

```json
{"event": "entered", "target": "gate-instance-uid", "action": "open"}
```

Here `gate-instance-uid` stands for the target instance's saved UID, not its catalog ID. Duplicating a whole assembly remaps internal targets to the copies. Removing a target prunes links to it. Keep new wiring features within that operation contract so player rules and saved machines stay consistent.
