# Authoring pieces and automation

Every placed object is a `BuildingPiece`. Its `PieceDefinition` supplies the stable ID, model scene, presentation, connectors, and measured placement geometry. Functionality comes from optional `PieceBehavior` nodes in that scene, including its root; one piece can compose several behaviors. The definition's `behavior` string is a catalog tag, not a script factory.

## Edit or add a piece

Open the definition under `resources/pieces/` and its **Model** scene. Functional wrappers live under `scenes/mechanisms/`; imported GLBs remain unchanged. Examples include:

- `sensor.tscn`: detection area and idle/occupied indicator animations.
- `gate.tscn`, `diverter.tscn`, `launcher.tscn`: authored moving collision, detection, visuals, and exported node references.
- `fan-*.tscn`: airflow housings/arrows or physical paddle collision arms, with different physics behavior.
- `bucket_elevator.tscn` and `support-*.tscn`: adjustable assemblies using saved component scenes and definition subclasses.
- `sandbox-start.tscn` and `sandbox-finish.tscn`: release scheduling and collector detection; display labels are presentation, while objectives use stable instance IDs.

To add a variant, duplicate a suitable wrapper and definition. Assign a new stable definition ID, name, category, thumbnail, and model. Bind behavior node references and make shared resources unique before editing them. Static pieces need no behavior node.

Inspect actual mesh dimensions, pivots, orientation, and hierarchy before updating bounds/connectors/occupied volumes/samples. Keep collision aligned with geometry. Enable **Native collision** for wrappers owning their shapes; ordinary meshes use the common generated triangle collision. Existing mesh-matched collision scenes are under `scenes/mechanisms/collision/`. Collider-free decorations can use pick-only bounds.

Behavior **Configuration fields** are arrays of `PieceSetting` resources: key, label, description, type, default, range, step, and unit. These saved fields supply both the inspector and definition normalization/authoring restrictions. `PieceDefinition` reads nested/inherited scene metadata through `SceneState`. Do not add a parallel name-keyed settings table.

Ordinary normalization retains omitted defaults and unknown keys, including `links`; runtime configuration resolves defaults separately. Adjustable definition subclasses may materialize their geometry settings. `configured` and `normalized_configuration` belong on those subclasses; use **Height setting**, **Ground placement**, and **Height offset** for existing contextual placement behavior.

Save the definition and register it in YARD's `resources/registries/piece_registry.tres`. The registry entry ID must equal `PieceDefinition.id`. Editor Play/export scans and indexes; headless tests consume the saved index. No separate catalog or runtime directory scan is needed. If online compatibility changes, regenerate the [community manifest](COMMUNITY_SERVICE.md#api-v1).

Verify placement, configuration, undo/redo, duplication, save/reload, simulation, pause, and reset. Geometry or mechanism changes need actual collision/transition tests, including multiple marbles where applicable.

## Behavior contract

Extend `PieceBehavior`. `configure(settings)` receives resolved instance configuration; call `super.configure` when overriding it. `reset()` restores configured initial state and clears timers/capture/runtime work. `start_run()` starts a simulation. `active` follows pause/resume/end and emits `activity_changed`; `enabled` is the behavior's own enabled state. Ghosts set `preview_only` and disable processing/collision.

Pulse inputs are callback entries in `inputs`; pulse outputs are names in `outputs`:

```gdscript
extends PieceBehavior

func _ready() -> void:
    inputs = {"trigger": _trigger}
    outputs = ["finished"]

func _trigger(value: Variant) -> void:
    emit_output("finished", value)
```

Persistent ports use `state_inputs` and `state_outputs`, with initial values. Each state input also needs an `inputs` callback. `emit_output` latches state and emits only changes; do not emit the underlying signal directly. Base reset restores declared initial values; subclasses restore their dependent state too.

Input/output names and setting keys must be unambiguous across a piece's components. Links address stable piece IDs and port names, so internal node paths can change without rewriting links. Pulse connects to pulse; state connects to state. Current Sensor provides a persistent `occupied` output alongside entered/exited pulses. The interface supports composing further behaviors; it does not imply shipped logic-gate or sound-block pieces.

Simulation delivers FIFO in source emission and saved-link order. Receiver outputs join that queue. Unchanged state values permit feedback to settle; exceeding the scene's delivery limit (default 16,384) fails the run. Pause rejects delivery; reset clears the queue and start seeds persistent connections. See [Architecture](ARCHITECTURE.md#behaviors-physics-and-automation).

## Wire a machine

Choose **Connect**, drag a send handle onto a compatible receiving piece, and choose ports/actions in the relationship card when needed. Escape cancels the drag/card, then leaves Connect. **Wires** independently shows directional relationships during normal building. Click a wire to inspect, change, or remove it. Selecting a mechanism emphasizes related links.

The shared UI calls `BuildManager.edit_link`; settings permissions, puzzle validation, and undo/redo apply. Duplicating an assembly remaps internal links; deleting targets removes dangling links. JSON retains `{event, target, action}` under source `config.links`. Simulation hides wiring and reset restores the previous Connect mode/overlay presentation.
