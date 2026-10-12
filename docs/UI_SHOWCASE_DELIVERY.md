# Main-menu machine and UI refinement

The menu now runs an authored 122-piece machine through the shared construction,
mechanism and rigid-body simulation systems. Two connected release lanes feed
twelve marbles into two interwoven circuits with bucket elevators, six spiral
descents, alternating diverters, sensor-controlled gates, merging return lanes
and six airflow fans. Marbles return physically through the elevators; ordinary
rolling uses the existing physics. No global physics settings were changed.

The saved construction is `resources/menu_machine.json`; `scripts/showcase.gd`
loads it into the existing WorldManager. The menu camera frames the whole machine
beside the preserved logo and seven consistently styled navigation options.

Common construction actions use shared icons and tooltips. The toolbox starts
on All pieces, keeps its filter and scroll state when collapsed, and uses quieter
cards with separate inventory quantities. Placement has an unboxed identity row;
feedback appears for snapping or invalid placement. Transparent embedded Windows
and an unframed settings tab panel remove the square background behind rounded
dialogs. These changes remain editable scenes and shared Theme resources.

## Verified

- Godot 4.7.2: 75 scripts loaded with zero failures.
- Showcase: 40 checks across two 180-second physics trials. All twelve marbles
  completed at least two return circuits and visited alternate branches in each
  trial, with no reset or lost marble. Reset cleared captured and active marbles.
- UI workflows: 606 checks; construction: 169; campaign permissions: 24;
  puzzle authoring: 29; functional mechanisms: 53. All passed.
- Native 1920×1080 and 1280×720 menu and construction screenshots were inspected.
  Settings corners and a live icon tooltip were inspected at 1920×1080. Rotate
  and collapse/expand were exercised through actual viewport clicks.
- `git diff --check` passed. The runner removed its isolated temporary save data.

The new `menu_showcase` suite is included in the normal verification runner.
These bounded trials verify repeated circulation, rather than proving unlimited
runtime reliability. This pass did not repeat every Introduction solution.
The environment still reports a root certificate-store error during headless
startup and stale UID warnings during live startup; resources resolve by their
correct paths. No live script errors were recorded in the inspected run.

Local review captures are in `build/ui-pass/`: `main-menu-1080.png`,
`main-menu-720.png`, `construction-1080.png`, `construction-720.png`,
`settings-1080.png`, and `tooltip-1080.png`. The build directory is ignored by
Godot so temporary scene backups cannot override production resource UIDs.
