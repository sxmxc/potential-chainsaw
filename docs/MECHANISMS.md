# Mechanisms

Mechanisms turn a track into a machine: they can release a sequence of marbles, change a route, supply force, or react to another piece. Select a piece to edit its settings in the inspector. Settings and links are saved with the construction; reset returns mechanisms to their configured initial state.

## Release, catch, and route

A **marble release** schedules its quantity, interval, initial delay, and initial speed. Its optional display label helps identify a route, but puzzle rules refer to the instance's stable ID. A **finish catcher** reports deliveries. In a puzzle, an objective can require several deliveries or accept only marbles from one release; in ordinary Sandbox testing, reaching a catcher ends the run.

A **gate** starts open or closed and can use delayed opening, automatic closing, or linked actions. It waits for the opening to clear before closing, and opening can nudge a stalled marble through. A **diverter** chooses left or right and can alternate after a marble clears, or change direction through a link.

A **launcher** applies an impulse using its strength and elevation settings. In external mode it waits for a Fire action. Auto-rearm can be disabled when it should fire only once. The route after launch still depends on the physical track and marble motion.

## Fans and sensors

Shrouded fans provide directional airflow. Set power, range, reverse, and enabled state; arrows show the direction. Standing variants push along local −Z and flat variants along local +Y. The exposed `fan-simple-*` models work differently: their rotating paddles contact marbles physically, using signed angular speed. They do not produce airflow.

A **sensor** detects passage without blocking it. It sends an `entered` pulse, optionally sends `exited`, and maintains an `occupied` state. The indicator remains occupied until the last detected marble has left, which matters when several marbles pass close together.

Use **Connect** to link a sensor to another mechanism. Sensor Entered → Gate Open is one supported relationship; another link can fire a launcher. **Wires** lets you view and inspect relationships while building. Pulse and state ports are distinct, and the wiring tools only offer compatible connections. See [Wire a machine](PIECE_AUTHORING.md#wire-a-machine) for the workflow and saved-link contract.

## Carry marbles uphill

The **Bucket Elevator**, under Mechanisms, lifts marbles in individual buckets. Try its example track to see the loading and discharge arrangement before designing a route around it.

Output rise is adjustable from 2–12 m in 0.5 m steps; conveyor speed ranges from 0.25–2 m/s. The inlet stays anchored while the outlet connector, frame, buckets, collision, and placement bounds change together. A height change that conflicts with the construction is rejected.

Each bucket captures one marble from the loading pocket, carries it, then tips above the upper outlet. Arrivals wait for available buckets. During capture the elevator controls transport; discharge restores rigid-body physics and gives the marble rolling spin and forward speed based on belt speed, clamped to 1.4–2.6 m/s. Plan and test the receiving route around that transition.

The elevator is stationary in build mode. Pause retains captured marbles, and reset clears capture and restores the initial arrangement. Developers can edit the saved assemblies in `scenes/mechanisms/`: `bucket_elevator.tscn`, `elevator_bucket.tscn`, `elevator_frame_section.tscn`, and `elevator_track_station.tscn`.

## Support the construction

Supports are optional: floating tracks are permitted. The six complete support families cover single, two, and four supports in normal and color variants. Their bearing height ranges from 1–30 m in 0.125 m steps, with a single or double top. Middle sections fill the span between base and top.

The base stays on the ground. Placing beneath level track adopts that track's elevation; otherwise active building height supplies the height. For a slope or irregular underside, set height deliberately and inspect the contact. Moving a group preserves the assembly rather than resizing its supports. Height edits update collision, bounds, and placement checks.

The wrappers live at `scenes/mechanisms/support-*.tscn`, and their definitions resolve components through the shared registry. Loose support parts from older saves remain readable.

For implementation work, follow [Piece authoring](PIECE_AUTHORING.md). For restricting settings or inventory in a challenge, use [Puzzle authoring](PUZZLE_AUTHORING.md). Physical routes need simulation testing, especially at moving contacts and elevator handoffs.
