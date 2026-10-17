# Mechanisms

Mechanisms turn a track into a machine: they can release a sequence of marbles, change a route, supply force, or react to another piece. Select a piece to edit its settings in the inspector. Settings and links are saved with the construction; reset returns mechanisms to their configured initial state.

## Release, catch, and route

A **marble release** schedules its quantity, interval, initial delay, and initial speed. Enable **Signal-controlled release** to wait for `release` pulses instead of releasing automatically. Each accepted pulse releases a marble without a lifetime limit. Quantity applies only to the automatic schedule. Pulses before the initial delay or during the interval cooldown are ignored rather than queued. The `released` event still reports each actual marble. Pause stops the delay and cooldown clock; reset restarts the automatic schedule and signal ordinal. Its optional display label helps identify a route, but puzzle rules refer to the instance's stable ID. A **finish catcher** reports deliveries. In a puzzle, an objective can require several deliveries or accept only marbles from one release; in ordinary Sandbox testing, multiple releases can run together and reaching a catcher ends the run.

A **gate** starts open or closed and can use delayed opening, automatic closing, or linked actions. It waits for the opening to clear before closing, and opening can nudge a stalled marble through. A **diverter** chooses left or right and can alternate after a marble clears, or change direction through a link.

A **launcher** fires from a fixed discharge point at its scene-authored `ReleasePoint`. It sets the marble's output velocity using **Launch speed** and its angle, replacing incoming velocity and clearing spin so arriving speed does not change the shot. The marble immediately continues with normal rigid-body physics and collision. Its flush loading paddle captures arriving marbles using the same physics ownership contract as elevator buckets. In external mode it holds its queue until a Fire action; automatic mode fires one marble per rearm interval. The first captured marble seats on the flush paddle; other arrivals wait while it fires. Release or reset restores their saved physics and collision. Its `loaded` state is true when a marble is seated and the paddle is ready, allowing AND gates and memory to authorize a shot. With auto-rearm enabled, a marble can fire again after leaving the detector and returning; the same marble is not repeatedly boosted while still inside it. Disabling auto-rearm limits the launcher to one shot per run, restored by reset. Pause preserves the cooldown and waiting state. Existing saves retain their `strength` setting as launch speed.

Selecting or placing a launcher in Build mode shows a world-space trajectory line through the shared construction overlay. It uses the same discharge point, configured launch velocity, and piece rotation as an actual shot, and hides during simulation. Nearer geometry obscures the line naturally. The preview sweeps the marble's collision shape along the gravity arc and ends at the first contact with physical geometry; selection-only decorations do not stop it. It does not predict bounces, fan forces, or damping after launch.

The hinged paddle and side pivots show the launcher's state: level with the track floor when armed, lifting its trailing end up and forward around the front pivot, then returning during auto-rearm. A spent one-shot launcher or a disabled launcher stays in its fired pose. The captured marble follows the paddle through the stroke. It releases when the seat reaches the fixed discharge marker, then continues under ordinary physics with the configured velocity. The paddle holds at release before returning, keeping it clear of the departing marble. Pause freezes the stroke; reset restores the configured initial pose. The editable handle animations live in `scenes/mechanisms/launcher.tscn` and follow the launcher's cooldown without affecting marble physics.

## Fans and sensors

Shrouded fans provide directional airflow. Set power, range, reverse, and enabled state; arrows show the direction. Standing variants push along local −Z and flat variants along local +Y. The exposed `fan-simple-*` models work differently: their rotating paddles contact marbles physically, using signed angular speed. They do not produce airflow.

A **sensor** detects passage without blocking it. It sends an `entered` pulse, optionally sends `exited`, and maintains an `occupied` state. The indicator remains occupied until the last detected marble has left, which matters when several marbles pass close together.

Use **Connect** to link a sensor to another mechanism. Sensor Entered → Gate Open is one supported relationship; another link can fire a launcher. **Wires** lets you view and inspect relationships while building. Pulse and state ports are distinct, and the wiring tools only offer compatible connections. See [Wire a machine](PIECE_AUTHORING.md#wire-a-machine) for the workflow and saved-link contract.

## Carry marbles uphill

The **Bucket Elevator**, under Mechanisms, lifts marbles in individual buckets. Try its example track to see the loading and discharge arrangement before designing a route around it.

Output rise is adjustable from 2–12 m in 0.5 m steps; conveyor speed ranges from 0.25–2 m/s. The inlet stays anchored while the outlet connector, frame, buckets, collision, and placement bounds change together. A height change that conflicts with the construction is rejected.

Each bucket captures one marble from the loading pocket, carries it, then tips above the upper outlet. The loading pocket captures arrivals while they wait for available buckets, preventing empty buckets from knocking waiting marbles out. A bucket takes ownership of that same capture as it loads. During capture the elevator controls transport; discharge restores rigid-body physics and gives the marble rolling spin and forward speed based on belt speed, clamped to 1.4–2.6 m/s. Plan and test the receiving route around that transition.

The elevator is stationary in build mode. Pause retains captured marbles, and reset clears capture and restores the initial arrangement. Developers can edit the saved assemblies in `scenes/mechanisms/`: `bucket_elevator.tscn`, `elevator_bucket.tscn`, `elevator_frame_section.tscn`, and `elevator_track_station.tscn`.

## Support the construction

Supports are optional: floating tracks are permitted. The six complete support families cover single, two, and four supports in normal and color variants. Their bearing height ranges from 1–30 m in 0.125 m steps, with a single or double top. Middle sections fill the span between base and top.

The base stays on the ground. Placing beneath level track adopts that track's elevation; otherwise active building height supplies the height. For a slope or irregular underside, set height deliberately and inspect the contact. Moving a group preserves the assembly rather than resizing its supports. Height edits update collision, bounds, and placement checks.

The wrappers live at `scenes/mechanisms/support-*.tscn`, and their definitions resolve components through the shared registry. Loose support parts from older saves remain readable.

For implementation work, follow [Piece authoring](PIECE_AUTHORING.md). For restricting settings or inventory in a challenge, use [Puzzle authoring](PUZZLE_AUTHORING.md). Physical routes need simulation testing, especially at moving contacts and elevator handoffs.

## Logic modules

Find **Memory**, **Counter**, **AND Gate**, **OR Gate**, and **NOT Gate** under **Logic**. Hover over a stationary construction surface, rotate with R, and click to mount. Placement snaps to a 0.5 m grid centered on the supporting piece, including side and underside faces. The preview and committed position use the same grid contact. Side and underside mounting keeps the control off the marble route. They are selectable accessories with pick collision, so their housing does not block marbles. Their placement volume still prevents overlapping other construction.

Use **Connect** and the normal inspector to configure and wire them. State outputs connect only to state inputs; events connect to actions.

| Module | Inputs | Outputs | Configuration |
| --- | --- | --- | --- |
| Memory | `set`, `reset`, `toggle` actions | `state` boolean; `changed` event | Initially on |
| Counter | `increment`, `reset` actions | `threshold_reached` boolean; `reached` event | Initial count, positive threshold |
| AND | `a`, `b` boolean states | `result` boolean; `rising` event | None |
| OR | `a`, `b` boolean states | `result` boolean; `rising` event | None |
| NOT | `a` boolean state | `result` boolean; `rising` event | None |

Memory retains its last command after the source pulse has ended. Commands follow saved wire order, so set then reset leaves it off. The counter continues counting after its threshold but emits `reached` only once until reset. Its readout shows current count / threshold; an initial count at or above the threshold starts reached without a new crossing event. Reset restores the configured count, rather than always zero. The optional billboard readout stays synchronized while hidden and displays the current count when enabled.

Unconnected gate inputs start false. Initial state wires settle before a gate emits its initial `rising` event, so an unconnected NOT can trigger a signal-controlled release, while a NOT connected to an initially-on memory does not fire accidentally. Later false-to-true results emit `rising`; unchanged results emit nothing. Resume does not retrigger initial activation. Reset restores all configured defaults.

Moving, rotating, duplicating, or deleting a supporting piece includes its mounted controls in the same history operation. All affected pieces must permit that edit in Puzzle Play and Player Test. Move a control alone to remount it; rotate a selected control to twist it about its mounting normal. Controls require a construction surface; fixed puzzle scenery, moving mechanism bodies, and other mounted controls are not mounting targets. Changing support geometry must leave the accessory on occupied geometry or the edit is rejected.

The **Timer** counts down its Duration in seconds: 2 means a two-second wait. It starts with Run when Start automatically is enabled, or waits for its Start input. Stop holds the remaining time; Start resumes it, and Reset restarts the interval. Loop repeats the Tick output; turning Loop off emits once and leaves the countdown at zero. Simulation pause freezes the clock without changing a wired Stop command. Returning to build mode resets it to idle. **Delay** forwards each received signal after its configured delay. Both have catalog thumbnails rendered from their saved models.
