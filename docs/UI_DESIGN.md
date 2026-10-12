# Interface design contract

The track is the focal point. A dark teal workbench background gives the warm Kenney surfaces a quiet setting. Mint identifies primary actions and connector alignment; gold identifies selection and finish; coral identifies rejection. Every placement state also has a text label and symbol, so color is supplementary.

## Tokens

The shared `resources/sandbox_theme.tres` defines the interface. Background #0E1C24, raised surface #253E45, border #2D4851, text #E6F2ED, secondary text #9CBBBD, action mint #56D6A3, selection gold #FFC66D, error coral #F23D4D. Segoe UI with a platform fallback; body 15, secondary 13, panel heading 17, contextual title 20, menu brand 48. Spacing uses 4 / 8 / 12 / 16 / 24; corners 8. Controls have normal, hover, pressed, disabled and keyboard-focus states. Primary buttons share a Theme type variation rather than individual styling.

## Layouts and workflows

- Main menu: one focused card over an example track, with sandbox, saves, examples, settings and quit.
- Build: compact top rows group file/history and build/test actions. A collapsible left library uses two columns of actual model thumbnails, search and categories. A small contextual tool strip exposes selection, moving, rotating and deletion. The right inspector exists only for selection. A thin lower status area shows the current tool, elevation, validation and input hints.
- Simulation: hide the library and inspector, emphasize test state and pause/restart/return controls. Preserve camera navigation. No world editing.
- Track browser: one modal list with load, rename and confirmed deletion. Empty state explains how to create a save. Examples use the same browser.
- Settings: camera sensitivity and the complete discoverable control scheme. Native modal focus and Escape behavior.
- Placement: blue preview for isolated grid placement, mint for connector alignment, coral for physical rejection; pair these with textual instructions and a connector target marker. Selection uses gold. Rotation remains deliberate rather than changing automatically during snapping.

At 1280×720, secondary controls collapse and the library can retract; typography remains readable. Containers own internal sizing; anchors own viewport-relative outer panels. The world must receive no placement clicks through interface panels or modals. No shortcuts operate while a text field is focused.

## Evidence required

Use runtime screenshots and UI bounds checks at 1920×1080, 1600×900 and 1280×720. Capture main menu, empty build, library, selected inspector, preview, simulation and browser. Exercise new → find → place → rotate → snap → elevate → edit → undo/redo → test/reset → save/reopen. Source inspection and parsing alone cannot establish acceptance.
