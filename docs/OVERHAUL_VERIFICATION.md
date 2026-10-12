# Construction overhaul verification

The implementation preserves the existing catalog, measured port metadata, snapshot history, save format and physical simulation. The previous single-piece workflow now supports threshold-based direct dragging, additive selection, projected-bounds marquee selection, connected assemblies and atomic group transformations. The dark Theme and user-selected fonts are retained; normal presentation remains in Theme resources and saved scenes.

## Functional evidence

`tests/run.gd` passes 169 checks. The additional construction suite dispatches mouse and keyboard events through the actual viewport rather than calling editing methods alone. It checks selection without movement, immediate dragging, cancellation, Shift toggling, marquee selection across heights, double-click connected selection, Ctrl+A, text-field protection, repeated placement, right-click cancellation and UI ownership of clicks.

Group checks cover translation with relative heights, rotation of positions and orientations around one anchor, cancelled and committed duplication with configuration preservation, deletion/restoration, atomic history and snapped group movement. The snapping matrix tests ground and elevated rotated targets at three camera angles and three zoom distances, measured slope elevations, incompatible profiles, occupied ports, occlusion, behind-camera rejection and selection-boundary ports. Existing persistence, fan collision, pause/reset and example-completion checks remain.

The isolated showcase reaches its finish through physics, restarts and leaves the sandbox snapshot/dirty state untouched. Authored camera poses differ at intermediate times and match at the loop endpoints. Live Hera observation also recorded repeated showcase loops and distinct World3D instances.

The live Forward+ sandbox was exercised using injected mouse gestures: a valid movement preview appeared, release committed it and the ghost exited. Hera's sandbox UI audit reports no errors or warnings. The menu's intentional full-viewport input surface may be reported as a fullscreen mouse-blocker warning. The live project error log was empty at inspection.

## Visual evidence

The graphical runner instantiates the actual main scene and captures 18 states at each of 1280×720, 1600×900 and 1920×1080: three menu camera moments, empty build, single selection, multiselection, group dragging, free placement, substantial construction, elevated attachment, rejected group placement, valid group attachment, simulation, track browser, save dialog and three settings tabs.

The 54 original framebuffer captures and native viewport/layout measurements are in `docs/qa/`. Reviewed captures include menu composition, small-window HUD, assembly controls, elevated/group attachment and settings tabs. Found defects were corrected: a wrapping status label collapsed the HUD into a narrow column; unthemed tabs used gray default surfaces; camera framing put elevated entry points behind controls. Stable container minimum width, native TabBar/TabContainer styles and scene-authored camera composition offsets address those cases. No measured buttons below minimum size or panels outside the viewport remain in the final capture pass.

Resolution captures use OpenGL compatibility. Live Hera inspection and captures additionally exercise the project's Forward+ renderer. The editor's embedded runtime dimensions can differ from project settings; captures are not resized to pretend they match a requested resolution.

## Performance and practical limits

The recorded CPU benchmark uses 100 selected pieces, 200 exposed source ports, two external targets and 20 solver samples. The latest result is in `docs/qa/snapping-performance.json`. Cached local-space geometry indices and once-per-group rotation checks remove repeated work. This is a solver measurement, not a whole-game frame-rate guarantee.

- Magnetic targeting considers a bounded set of 12 ranked attachment alternatives. The pixel radius is editable on BuildManager. Hysteresis holds nearby targets; Tab selects another available alternative.
- Port visibility uses collision rays. Orbit the camera to reach an occluded port. Box selection intentionally uses projected bounding rectangles and can include pieces behind other pieces.
- Rotation remains in 90-degree increments. A rigid group keeps existing internal geometry and connections; external placement is validated together.
- Placement collision rejection retains the existing sampled-geometry approach. Very thin decorative geometry can escape rejection; actual simulation uses imported mesh collision. This overhaul does not claim exact arbitrary-mesh intersection testing.
- Fully general support/decorative attachment metadata is not present. Connected selection follows actual compatible track ports and skips locked pieces; nearby supports do not become part of an assembly automatically.
- Sandboxed standalone Godot processes report a Windows certificate-store initialization error. It is unrelated to UI resources or gameplay and does not appear in the inspected live project log.
