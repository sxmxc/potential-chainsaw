# UI design rules

The track is the focal point. A dark teal workbench background gives the warm Kenney surfaces a quiet setting. Mint identifies primary actions and connector alignment; gold identifies selection and finish; coral identifies rejection. Every placement state also has a text label and symbol, so color is supplementary.

## Tokens

The shared `resources/sandbox_theme.tres` is authoritative for colors, fonts and sizes. The approved overhaul uses Nunito Sans: regular body text, semibold controls, bold headings. Keep the original stylized logo in gold. Type roles are supporting text 14, body/buttons/piece names 16, menu navigation 18, section headings 20, dialog headings 28, and brand 54. Fonts and full license notices live in `assets/font/`. Spacing follows 4 / 8 / 12 / 16 / 24. Ordinary targets should be at least 40 pixels high and primary actions 44. Controls need normal, hover, pressed, disabled and keyboard-focus states. Primary buttons share a Theme type variation rather than individual styling.

## Layouts and workflows

- Main menu: unboxed left navigation around the animated real-3D showcase, with Campaign emphasized, Sandbox, saves, examples, Puzzle Editor, settings and a separated Quit action.
- Build: separate content-sized file/history and test/menu islands. A bottom-left library uses recognizable model thumbnails, search and categories for larger catalogs, and a compact one-column layout for single-piece inventories. Bottom contextual strips expose placement helpers and selection actions. Drag selected pieces directly. The right inspector appears only for configurable single pieces; group actions live in the selection strip. Temporary status and Introduction hints occupy bounded contextual cards.
- Bounded numeric piece settings use the shared `setting_slider.tscn`: live value and units above the slider, minimum and maximum below. Dragging updates the displayed number and commits one configuration/history change on release; arrow keys retain the setting's step size. Authoring limits and inventory counts remain numeric fields.
- Simulation: hide the library and inspector, emphasize test state and pause/restart/return controls. Preserve camera navigation. No world editing.
- Track browser: one modal list with load, rename and confirmed deletion. Empty state explains how to create a save. Examples use the same browser.
- Settings: audio levels, display/graphics options, camera controls, rebindable keyboard shortcuts, and restore defaults. Saved native controls in a scrollable, tabbed modal with predictable focus and Escape behavior.
- Campaign: horizontal chapter navigation, optional Introduction, completion/lock symbols and a compact empty state. Objectives describe the outcome; Introduction hints appear only when useful. Campaign menus expose campaign actions.
- Puzzle Editor: a right-side authoring drawer leaves the world editable. Its seven-page navigation uses a vertical rail. Advanced setup metadata is disclosed separately. Publishing shows the existing player-test, saved-solution and current-validation requirements. The shared header exposes Test as player.
- Placement: blue preview for isolated grid placement, mint for connector alignment, coral for physical rejection; pair these with textual instructions and a connector target marker. Selection uses gold. Rotation remains deliberate rather than changing automatically during snapping.

At 1280×720, secondary controls collapse and the library can retract; typography remains readable. Containers own internal sizing; anchors own viewport-relative outer panels. The world must receive no placement clicks through interface panels or modals. No shortcuts operate while a text field is focused.

## Reviewing changes

Review affected screens at 1280×720, 1600×900 and 1920×1080. Check clipping, scrolling, text readability, focus and input reaching the world. Exercise the affected building workflow through editing, undo/redo, test/reset and save/reopen. Keep reusable architecture rules in [Architecture](ARCHITECTURE.md); inspect current styles in the Theme editor.
