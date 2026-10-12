# UI design rules

The track is the focal point. A dark teal workbench background gives the warm Kenney surfaces a quiet setting. Mint identifies primary actions and connector alignment; gold identifies selection and finish; coral identifies rejection. Every placement state also has a text label and symbol, so color is supplementary.

## Tokens

The shared `resources/sandbox_theme.tres` is authoritative for colors, fonts and sizes. Preserve the fonts selected in that resource. Use the established dark teal surfaces, mint actions, gold selection and coral errors. Keep a consistent type hierarchy for secondary text, body text, headings and menu branding. The baseline sizes are 13 / 15 / 17 / 20 / 48; adjust shared Theme variations when changing them. Spacing follows 4 / 8 / 12 / 16 / 24, with an 8-pixel corner preset. Controls need normal, hover, pressed, disabled and keyboard-focus states. Primary buttons share a Theme type variation rather than individual styling.

## Layouts and workflows

- Main menu: one focused card over an example track, with campaign, sandbox, saves, examples, settings and quit.
- Build: compact top rows group file/history and build/test actions. A collapsible left library uses two columns of actual model thumbnails, search and categories. A small contextual tool strip exposes selection, moving, rotating and deletion. The right inspector exists only for selection. A thin lower status area shows the current tool, elevation, validation and input hints.
- Simulation: hide the library and inspector, emphasize test state and pause/restart/return controls. Preserve camera navigation. No world editing.
- Track browser: one modal list with load, rename and confirmed deletion. Empty state explains how to create a save. Examples use the same browser.
- Settings: camera sensitivity and the complete discoverable control scheme. Native modal focus and Escape behavior.
- Placement: blue preview for isolated grid placement, mint for connector alignment, coral for physical rejection; pair these with textual instructions and a connector target marker. Selection uses gold. Rotation remains deliberate rather than changing automatically during snapping.

At 1280×720, secondary controls collapse and the library can retract; typography remains readable. Containers own internal sizing; anchors own viewport-relative outer panels. The world must receive no placement clicks through interface panels or modals. No shortcuts operate while a text field is focused.

## Reviewing changes

Review affected screens at 1280×720, 1600×900 and 1920×1080. Check clipping, scrolling, text readability, focus and input reaching the world. Exercise the affected building workflow through editing, undo/redo, test/reset and save/reopen. Keep reusable architecture rules in [Architecture](ARCHITECTURE.md); inspect current styles in the Theme editor.
