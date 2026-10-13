# Authoring pieces and automation

Every placed object is a `BuildingPiece`. Its `PieceDefinition` supplies the stable ID, scene, catalog presentation, connectors and measured placement geometry. The scene supplies visuals, native collision and optional `PieceBehavior` nodes. A behavior can be the scene root or a child; one piece may have several behaviors.

`behavior` on the definition is a catalog tag. It does not select a script or construct functionality. Adding a behavior does not require another name in a construction, simulation or UI switch statement.

## Modify an existing piece

Open the definition in `resources/pieces/`, then open the scene referenced by **Model**. Functional scenes live in `scenes/mechanisms/`:

- `sensor.tscn`: Track, Detection, Indicator and IndicatorAnimation. Edit the detection shape and indicator mesh/material directly. Edit the `idle` and `occupied` animations to change feedback. Occupied stays on until the last marble leaves and clears on reset.
- `launcher.tscn`: Track, Detection, LoadingStop and Arrow. The root's exported references bind these nodes to `launcher.gd`; the script owns launching and rearming. Its exported stop heights and cooldown let a variant use different geometry.
- `gate.tscn` and `diverter.tscn`: editable moving collision bodies, companion visuals and detection shapes. Gate travel/release heights and speed are exported on its root.
- `fan-*.tscn`: imported housing/blade references, airflow regions/arrows or separate paddle collision arms. Airflow fans and physical paddles share the behavior interface, but retain different physics.
- `bucket_elevator.tscn` and `support-*.tscn`: existing adjustable assemblies. Their scripts create variable numbers of saved frame/bucket/model sections; their definition subclasses update placement geometry and connectors.
- `sandbox-start.tscn` and `sandbox-finish.tscn`: the release and collector behaviors own spawning/scheduling and detection. Their geometry, marker meshes and 3D labels are saved in the scenes. Edit **Display label** in the inspector to identify routes; an empty label hides the billboard. Labels are presentation only: puzzle delivery objectives still choose stable collector and source IDs.

Imported GLBs remain unchanged. Replace or edit their source assets in a modeling program, or change their wrapper scene. After a geometry change, update collision and the definition's measured bounds, connectors, occupied volumes and samples together. Existing mesh-matched track collision is saved under `scenes/mechanisms/collision/`; replace it using Godot's mesh collision tools when replacing a model. Do not leave an old collision shape under a new mesh.

The scene script's **Configuration fields** contains `PieceSetting` resources: key, label, description, numeric/flag/text kind, default, range, step and unit. Text fields commit on Enter or leaving the field. These are the single source for the inspector and puzzle restrictions. Edit them on the owning behavior node, not in a global table. The definition reads the saved scene metadata through Godot's `SceneState`, including inherited scenes and nested instances, without instantiating physics objects.

Missing settings use authored defaults at runtime. Saves retain their per-instance overrides without materializing every default. Unknown configuration keys and saved `links` remain intact. Geometry-specific normalization still belongs to definition subclasses.

## Create a piece using an existing behavior

1. Duplicate an appropriate scene and `PieceDefinition`, or create a wrapper with a reusable behavior scene as a child.
2. Give the definition a new stable `id`, display name, category, thumbnail and usage hint. Set **Model** to the new scene. Leave connectors empty for freestanding devices.
3. Bind the behavior's exported node references in Godot. Edit its **Configuration fields** resources; make them unique before changing a shared variant's values.
4. For an authored collision scene, enable **Native collision**. For ordinary GLB meshes, leave it off to use the common mesh collision generation. **Collision enabled** and measured placement geometry continue to determine placement overlap rules. A collider-free decoration can still have pick-only bounds.
5. For adjustable geometry, supply a definition subclass that implements `configured` and `normalized_configuration`. A contextual height setting is identified by **Height setting**; **Ground placement** and **Height offset** describe placement without a support-specific builder branch.
6. Save the definition under `resources/pieces/`. In YARD's piece registry, make its registry entry ID match the definition's `id`. Editor Play/export performs the installed addon's scan/index build. Headless tests use the saved registry index.
7. Place, configure, undo/redo, duplicate, save/reload, simulate, pause and reset the piece. Verify actual collision and transitions before using it in a puzzle.

## Add a new behavior

Extend `PieceBehavior` and attach it to a node in the saved scene. Use exported references for authored nodes. `configure` receives resolved per-instance configuration; call `super.configure` when overriding it. `reset` restores configured initial state, cancels timers/capture and clears runtime state. `start_run` is called once at simulation start. `active` changes during pause/resume/end and emits `activity_changed(running)` for behaviors such as audio/animation controllers; `enabled` remains the behavior's configured/runtime enabled state. Placement previews have processing and collision disabled and reject inputs.

Declare pulse inputs with callbacks and pulse outputs by name:

```gdscript
extends PieceBehavior

func _ready() -> void:
    inputs = {"trigger": _trigger}
    outputs = ["finished"]

func _trigger(value: Variant) -> void:
    # Perform the behavior's work, then announce the result.
    emit_output("finished", value)
```

State inputs and outputs are declared in `state_inputs` and `state_outputs`, with their initial values. Provide an input callback in `inputs` for each state input too. `emit_output` latches state values and emits only changes. Reset restores the declared initial values; subclasses must also restore their own dependent state. Names must be unique across a piece's components and pulse/state output declarations. Configuration keys must also be unique across components. Saved links address the piece's stable ID and a port name, so a component's internal node path can change without rewriting links.

Use `emit_output`, not the underlying signal, so persistent-state change detection stays consistent. Wiring, validation and simulation discover the same component ports; pulse ports connect to pulse ports and state ports to state ports. A pulse may carry a marble or another payload; a state carries its persistent value. A behavior with no ports operates independently.

Simulation handles outputs in FIFO order and traverses each source's saved links in array order. Outputs caused by receivers join the same queue, so downstream chains work without recursion. Unchanged input/output states allow feedback networks to settle. More than the SimulationManager scene's delivery limit (16,384 by default) in one propagation transaction stops the simulation with a wiring error; this is a finite safety limit for non-settling feedback, not a timing mechanic. Pause rejects inputs and suppresses propagation; reset discards queued signals and restores initial state. Persistent outputs seed their connected inputs at the next start.

A future logic gate declares state inputs, recomputes its result in their callbacks and emits a state output. A sound block declares a pulse input for a one-shot sound and/or a state input for a loop, references an authored `AudioStreamPlayer3D`, and stops/restores it during reset and pause as appropriate. Both use scene-owned configuration fields. Neither needs a new branch in the piece, simulation, inspector or wiring code. These examples describe the extension contract; they are not additional shipped mechanics.

## Wire a machine

**Connect** enables editing. Each sending/receiving piece has one larger role handle. Drag a send handle onto a highlighted receiving piece; the whole piece accepts the drop. If there are several compatible outputs or inputs, choose them in the compact relationship card and confirm. Escape cancels the drag/card, then returns to building.

**Wires** independently shows existing relationships while ordinary construction remains available. Directional arrows run from source to receiver. Selection emphasizes related links; hover describes the relationship. Click a wire to inspect, change or remove it. The inspector keeps normal settings separate from incoming/outgoing connection counts and its Connect action. Wiring UI hides during simulation and returns to its previous tool/overlay state on reset.

Link edits use the same configuration permissions, puzzle validation and history as ordinary settings. Internal assembly links remap on duplication; deleting a receiver removes dangling links. Track/puzzle JSON keeps the existing `event`, `target` and `action` fields.
