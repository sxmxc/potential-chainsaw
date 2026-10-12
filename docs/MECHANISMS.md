# Mechanisms

Select a piece to edit its settings in the inspector. Settings and event links are saved with tracks and puzzles. Pause stops mechanism motion; reset restores configured initial state.

## Fans, gates and links

| Piece | Behavior and settings |
| --- | --- |
| Shrouded fans (`fan-two`, `fan-four`, standing variants) | Finite airflow with power, range, reverse and initial enabled state. Standing fans push along local −Z; flat fans along local +Y. Arrows show the direction. |
| Exposed fans (`fan-simple-two`, `fan-simple-four`) | Physical rotating paddles. Angular speed can be negative. These pieces do not produce airflow. |
| Gate | Starts open or closed, with optional delayed opening and automatic closing. Once raised, it gently nudges a stalled marble through. An occupied opening prevents it from closing on a marble. |
| Diverter | Guides the marble left or right. Linked actions can change direction; optional alternation switches after each marble clears the junction. |
| Launcher | Strength and elevation control the impulse. External mode holds an arriving marble until Fire. Disable auto-rearm for single-shot use. |
| Sensor | Emits Entered and optional Exited events without blocking the lane. |

The inspector's link controls connect a source event to a target action. For example, Sensor Entered → Gate Open. Add a second link to fire a launcher from the same event. Available events and actions depend on the selected mechanism. Links remap within duplicated assemblies and are removed when their target is deleted.

## Bucket elevator

Choose **Bucket Elevator** under **Mechanisms**, or load its connected example from the examples browser.

- Output rise: 2–12 m in 0.5 m steps. Conveyor speed: 0.25–2 m/s.
- The inlet stays anchored. Height changes update the output connector, frame, buckets, collision and placement bounds together.
- Attach track to the upper connector without changing the building plane. Placement reserves the complete mechanism volume, including the moving buckets. Conflicting height changes are rejected.
- Each bucket carries one marble from the loading pocket, tips above the output track and releases it onto the track. Multiple arrivals queue for available buckets.
- Discharge adds forward speed (1.4–2.6 m/s, following belt speed) and matching rolling spin to preserve momentum on the outlet.
- Build mode is stationary. Pause retains carried marbles; reset releases them and restores the initial arrangement.

Editable scenes live in `scenes/mechanisms/`: `bucket_elevator.tscn`, `elevator_bucket.tscn`, `elevator_frame_section.tscn` and `elevator_track_station.tscn`.

## Supports

Six complete families provide single, two and four supports in normal and color variants. Select an assembly to choose Single or Double top and set bearing height from 1–30 m, in increments down to 0.125 m.

The base stays on the ground. Placement beneath a level track adopts that track's elevation; otherwise the building plane supplies the height. Set height manually for slopes and irregular undersides. Inspector Lower/Raise changes support height. Moving a group preserves its transforms without resizing its supports.

Matching middle segments fill the height between the original bottom and top models. Height changes update collision, bounds and placement checks. The complete assembly supports selection, movement, rotation, duplication, saves and undo. Older saves containing loose support parts remain readable.

The six `scenes/mechanisms/support-*.tscn` scenes contain editable default assemblies. PieceDefinition resources supply the inventory thumbnails.

See [Puzzle authoring](PUZZLE_AUTHORING.md) for inventory limits, permissions and objectives, and [Architecture](ARCHITECTURE.md) for implementation rules.
