# Mechanisms

Select a piece to edit its settings in the shared inspector. Configuration and links are saved with tracks/puzzles. Pause suspends mechanism motion; reset restores the configured initial state. These descriptions follow the implementation; they do not guarantee a particular machine's physics outcome.

## Releases, routing, and forces

| Piece | Behavior |
| --- | --- |
| Marble release | Schedules quantity, interval, start delay, and initial speed; emits `released`. Optional display label identifies a route. |
| Finish catcher | Detects delivered marbles and emits `collected`. Puzzle objectives can count deliveries from a particular source. |
| Shrouded fans | Directional airflow with power, range, reverse, and enabled state. Standing variants push along local −Z; flat variants along local +Y. Arrows indicate direction. |
| Exposed `fan-simple-*` fans | Physical rotating paddles, with signed angular speed; no airflow. |
| Gate | Initial open/closed state, optional delayed opening/automatic closing, and linked actions. Waits for a clear opening before closing; opening can nudge a stalled marble through. |
| Diverter | Left/right routing with linked direction changes and optional alternation after a marble clears. |
| Launcher | Strength/elevation set an impulse. External mode waits for Fire; auto-rearm can be disabled. |
| Sensor | Nonblocking entered/optional exited pulses and a persistent `occupied` state. Its indicator stays occupied until the last detected marble leaves. |

Use **Connect** to drag a send handle onto a receiver, then choose compatible ports. For example, Sensor Entered → Gate Open; a second link can fire a launcher. **Wires** shows relationships independently while building. Ports are declared by behavior components; pulse/state compatibility is enforced. See [Piece authoring](PIECE_AUTHORING.md#wire-a-machine).

## Bucket elevator

Choose **Bucket Elevator** under **Mechanisms**, or open its example track. Output rise is 2–12 m in 0.5 m steps; conveyor speed is 0.25–2 m/s. The inlet stays anchored while output connector, frame, buckets, collision, and placement bounds update together. Conflicting height changes are rejected.

Each bucket captures one marble from the loading pocket, carries it, tips above the upper outlet, and restores physics on release. Arrivals wait for available buckets. Discharge provides forward speed based on belt speed, clamped to 1.4–2.6 m/s, with rolling spin. Outside intentional capture, travel remains rigid-body physics.

Build mode is stationary. Pause retains captured marbles; reset clears capture and restores the initial arrangement. Saved editable components are `bucket_elevator.tscn`, `elevator_bucket.tscn`, `elevator_frame_section.tscn`, and `elevator_track_station.tscn` under `scenes/mechanisms/`.

## Supports

Six complete families provide single, two, and four supports in normal/color variants. Bearing height is 1–30 m in 0.125 m steps; choose a single/double top in the inspector. Matching middle sections fill between the original base and top.

The base stays on the ground. Placement beneath level track adopts its elevation; otherwise active building height supplies it. Set height deliberately for slopes/irregular undersides. Moving a group retains its arrangement without resizing supports. Height changes update collision, bounds, and placement checks. Loose support parts from older saves remain readable.

The assemblies live in `scenes/mechanisms/support-*.tscn`; definitions resolve component resources through the shared registry. Supports are optional; floating tracks are permitted.

For implementation changes see [Piece authoring](PIECE_AUTHORING.md); for player permissions and limits see [Puzzle authoring](PUZZLE_AUTHORING.md).
