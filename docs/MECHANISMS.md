# Functional mechanisms, elevator, supports and previews

Shrouded `fan-two`, `fan-four`, `fan-standing-two`, and `fan-standing-four` produce directed finite airflow. Select a fan to set power, range, reverse and initial enabled state. Standing fans push along local -Z; flat fans along local +Y. Their visible arrows reflect reversal. Link actions can activate, deactivate, toggle or reverse the operating field. The decorative blades do not collide as moving paddles.

Exposed `fan-simple-two` and `fan-simple-four` use moving physical blade collision. Set angular speed (including negative rotation) in the inspector. They transfer momentum through contact and have no airflow force.

The new Mechanisms catalog includes Gate, Diverter, Launcher and Sensor. A gate can start open/closed, release after a delay and close again automatically; its occupied clearance prevents crushing a marble. The Y-fork diverter physically guides left/right, accepts linked direction changes and optionally alternates after each marble clears the junction. The launcher's strength and elevation angle control a real impulse in its local forward direction. Its external mode physically holds an arriving marble until Fire, and auto-rearm can be disabled for single-shot use. A sensor emits Entered and optional Exited events without obstructing the lane.

Selected mechanisms expose event/action linking in their inspector. Connections persist with track and puzzle saves, remap when assemblies are duplicated, and clean up when targets are deleted. Simulation reset restores configured initial state and clears per-run occupancy/firing/event state. Pause suspends mechanism motion and marble scheduling.

See [Puzzle authoring](PUZZLE_AUTHORING.md) for campaign restrictions and linking, and [Campaign verification](CAMPAIGN_VERIFICATION.md) for the 53 real-physics mechanism checks and all ten verified puzzles.

## Bucket elevator


The elevator is complete as one construction piece. Find **Bucket Elevator** under **Mechanisms**, or open **Bucket Elevator** in the examples browser for a connected, playable four-piece route. Loading and Output use saved instances of the Kenney `straight` model and a saved triangle collision resource made from that mesh. The pocket has a small backstop to hold an arriving marble until a bucket is available.

Select an elevator to set its output rise (2–12 m, in 0.5 m increments) and conveyor speed (0.25–2 m/s). Its inlet stays anchored; the output connector, placement bounds, frame length and bucket count change together. Point at the upper connector to attach a track without changing the building plane. Full mechanism volume is reserved during placement, including the space swept by circulating buckets. Conflicting height changes are rejected and rolled back.

The `end-square` mesh was inspected directly: identity local transform, 1×1 footprint, 0.5 m bounds height, 36 triangles, central track surface at 0.25 m and an opening toward −Z. The bucket scene retains that model, with a small retaining lip and mounting bar. Upright buckets ascend one side of a closed vertical loop, tip toward the upper station, level out and descend the return side. Drive wheels turn with conveyor phase. Bucket shapes on selection layer 4 let clicks select the whole assembly; marbles only collide with track layer 1, so these picking shapes do not affect transport physics.

Capture is restricted to the loading pocket and one marble per bucket. A reusable ownership interface freezes the rigid body and temporarily removes its collision layer/mask. It interpolates the initial seating movement, preserves visible marble orientation, then moves the frozen body with the bucket during physics ticks. Discharge occurs at the tipped bucket mouth above the real exit track, with modest forward speed and a physical drop onto the bed. It never places the marble at the exit connector. The original collision, freeze mode and other touched state are restored on release/reset. Normal track movement remains rigid-body physics. This follows Godot's [RigidBody3D freeze API](https://docs.godotengine.org/en/stable/classes/class_rigidbody3d.html#class-rigidbody3d-property-freeze).

Build mode is stationary. Pause stops conveyor phase and retains capture state. Resume keeps a carried marble frozen until discharge. Reset restores the initial arrangement, clears queues and releases occupied buckets before the simulation removes its marble. The mechanism can process multiple arrivals; Sandbox releases one marble, while campaign objectives support multiple scheduled releases and specified collectors.

## Supports

The Supports inventory now has six complete families: single/two/four, each in normal and color variants. Select one assembly, choose Single or Double top style, and set its bearing height. The bottom and top always use the exact matching kit models at their original scale. Matching 0.5 m middle models repeat between them; a final partial middle section fits a fine height increment. The whole support is one selectable, movable, rotatable, duplicable, saveable and undoable piece.

New placement uses the active building level and keeps the base at ground. Hovering a level track automatically uses that track's base elevation. Away from a suitable level track, the building plane remains the height reference. Slopes and irregular undersides require choosing the appropriate bearing height manually. Inspector Lower/Raise buttons change support height rather than translating its base. Ordinary rigid group movement preserves the whole group's transforms, including supports; it does not silently resize members of a moved group.

Support heights range from 1–30 m, with 0.125 m fine resolution. Height changes rebuild actual segment collision, bounds and placement samples. Legacy bottom/middle/top IDs remain readable for existing tracks, but those loose parts are hidden from the inventory. Existing saved stacks are preserved rather than silently replaced.

## Saved scenes and images

- `scenes/mechanisms/bucket_elevator.tscn`: station, drive, frame and bucket hierarchy, with a saved default arrangement.
- `scenes/mechanisms/elevator_bucket.tscn`: reusable tray, lip and mounting geometry.
- `scenes/mechanisms/elevator_frame_section.tscn`: reusable frame/chain segment.
- `scenes/mechanisms/elevator_track_station.tscn`: original straight model and its saved collision.
- `scenes/mechanisms/support-*.tscn`: six editable family scenes with bottom, two middle segments and top at the default 2 m bearing height.
- `scenes/ui/inspector.tscn`: saved themed settings controls, with native scrolling for small windows.

Runtime code instantiates those existing scenes and adjusts mechanism state/height. It never writes or composes `.tscn` files at runtime. Editor-maintainable default arrangements are present before scripts run.

All 169 PieceDefinition resources explicitly reference their previews. Kit pieces use `assets/models/previews/`; support family cards use their supplied top preview; the elevator retains its generated `resources/thumbnails/bucket-elevator.png`. Piece cards bind the resource's thumbnail directly, including the contextual extension picker.

## Verification

- Existing construction/physics regression suite: 169 checks, zero failures.
- Elevator suite: 62 checks, zero failures. Physical input, capture, ascent, discharge and finish at 2/4/12 m and three rotations; pause/resume; occupied reset; repeated runs; three close arrivals; atomic settings/history; obstruction rollback; save/load; configured ghost geometry; upper output snapping; actual straight station models; selecting the assembly by clicking a bucket.
- Support/preview suite: 1,160 checks, zero failures. Six families × both tops × minimum/default/fractional/maximum heights; matching segment continuity; unchanged cap scale; collision/bounds; history; duplication/deletion; save/load; ground anchoring; fitting beneath an elevated track; all supplied preview references.
- Nine elevator captures include Build mode at three resolutions, loading, ascent, tipping, discharge, finish and maximum height. Six support captures cover the families and Double top at 1280×720, 1600×900 and 1920×1080. Native inspector and HUD bounds fit the support captures. The previous fixed 700-pixel inventory minimum was changed to fill available container height and scroll, preventing small-window HUD clipping.

The results and original framebuffer captures are under `docs/qa/` and `docs/*_test_results.txt`. Resolution captures use the actual game scenes with the Compatibility renderer; live Hera additionally checks the editor's Forward+ game. Standalone sandboxed processes may emit the existing Windows certificate-store initialization error.

```powershell
$env:APPDATA = "$PWD/.local-user"
godot --headless --path . --fixed-fps 120 --script tests/run.gd
godot --headless --path . --fixed-fps 120 --script tests/bucket_elevator.gd
godot --headless --path . --fixed-fps 120 --script tests/resizable_supports.gd
```
