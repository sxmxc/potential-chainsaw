# Construction experience overhaul

Audit: reuse catalog resources, measured connector definitions, sampled collision validation, snapshot history, JSON saves and physical simulation. The native Theme and saved UI scenes are already a suitable foundation. Current weaknesses are single selection, explicit move-tool activation, world-distance snapping restricted by active elevation/manual orientation, tall identical inspector actions, dense settings instructions, and a static menu sharing the editable sandbox.

Implementation sequence:

1. Extend the existing construction controller with threshold-based direct dragging, projected-bounds marquee selection, connected selection and atomic group editing. Preserve the existing single-piece API for UI bindings.
2. Add one screen-space connector solver for new pieces and group previews: availability/compatibility, depth/occlusion, automatic permitted rotations, candidate cycling and hysteresis. Retain stable horizontal planes and free grid placement. Add a catalog-driven extension popup.
3. Keep presentation in the shared Theme and reusable scenes. Add saved selection/context widgets; bind their state through scripts.
4. Recompose the HUD and library as compact game controls, reduce inspector/debug clutter, group settings, soften construction grid/environment.
5. Isolate a physical example showcase in its own scene and world, with authored looping AnimationPlayer camera motion and a left-aligned menu.
6. Exercise actual input, group/history/persistence and physics; render all required states at three resolutions and inspect captures. Record controls and practical limitations.

No additional editor instance is needed. Use the existing Hera-enabled editor and standalone runtime validation processes.
