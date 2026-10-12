# Marble chase camera

Sandbox, Campaign and Test as Player use the shared world camera controller.
During simulation, click an exposed marble or use the camera icon to follow it.
The same button stops following; a next-marble button appears when following
with multiple available marbles. Returning to build, finishing a simulation,
resetting or removing the target returns to the preserved free view.

`scenes/camera/marble_chase.tscn` contains the reusable PhantomCamera third-person
rig. Persistent non-colliding targets follow position and movement direction,
never rolling-body rotation. Heading changes are smoothed and rate limited;
stationary marbles retain their heading. The addon's spring arms handle camera
clearance against track geometry. Two chase PCams permit priority transitions
between marbles, including requests made during another transition.

The construction camera drives FreeView while PhantomCameraHost owns the rendered
camera transform. Input and orbit state are preserved while following. Separate
host layers isolate the playable world and the menu SubViewport.

The menu reuses its existing wide-shot animation and machine. Its director adds
a tighter cinematic shot and randomized short chase shots, excludes stationary
and captured marbles when choosing a shot, and avoids repeating the previous
marble when another is available. Reset or target loss returns to the wide view.

Static icons are assigned in the saved toolbar scene. The follow icon changes
to a stop icon during chase. Lens resources, host layers and menu input policy
are scene configuration; scripts handle movement, state and scheduling.

Tuning: the chase scene root exposes follow distance, height, orientation
smoothing and transition duration. The showcase CameraDirector exposes wide,
detail and chase durations (11, 7 and 6 seconds by default). Lens, collision
clearance and tween easing are editable scene resources.

## Verification

- Godot 4.7.2 with PhantomCamera 0.11.0.3 enabled.
- Strict GDScript gate: 79 scripts, zero failures.
- `tests/marble_camera.gd`: 24 checks, zero failures. One representative bucket
  elevator simulation and 42 simulated seconds of the existing menu machine
  cover shot sequencing, different marble targets, host isolation, level chase
  horizon, close tracking, free pose/composition restoration, switching marbles,
  reset during transition, absent marbles and removal of a followed body.
- Live 1280×800 run: Follow and Stop were clicked through the HUD; chase state
  and restoration were inspected. The menu chase and player chase screenshots
  were inspected. Direct viewport marble picking is implemented but was not
  separately exercised through a live pointer click.
- No full campaign, all-piece or multi-resolution verification was repeated.

## Remaining visual limitations

The close player view can become substantially obstructed beneath or inside the
bucket elevator. Spring-arm clearance helps ordinary track geometry but cannot
guarantee a clear view from enclosed mechanism interiors. PhantomCamera's rotation
tween can briefly bank between shots; settled chase views retain a level horizon.
These observations are left for review rather than another cinematic tuning pass.

The installed addon intermittently lost global class registrations in the editor
cache during headless checks. A live editor filesystem rescan restored them;
addon source was not changed. Existing stale resource UID and Windows certificate
store warnings also appeared. The final camera suite passed with no script errors.
