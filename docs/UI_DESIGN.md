# UI design

The construction is the visual priority. Players need to see where a piece will go, what they have selected, and what happened during a run. Panels should support those decisions without covering the machine or showing every possible action at once.

The visual style combines colorful track pieces, the stylized gold logo, and an animated real-3D menu machine. Dark teal surfaces frame the construction; mint marks actions, gold marks selection, and coral marks rejection. Pair color with text or symbols so it is never the only explanation.

This guide is for changes to interface scenes and behavior. [Puzzle authoring](PUZZLE_AUTHORING.md) owns the detailed editor workflow; [Architecture](ARCHITECTURE.md) explains the workspace and application boundaries.

## Build the layout in scenes

Static interfaces belong in editable `scenes/ui/*.tscn` scenes. Use anchors for outer placement and Containers for internal layout, with size flags, minimum sizes, and scrolling to handle growing content. Local panel widths and icon sizes are useful constraints; ordinary layout should not depend on calculating positions from viewport dimensions or overriding a Container's decisions.

`resources/sandbox_theme.tres` holds shared fonts, colors, spacing, control states, and type variations. Body text uses Nunito Sans and the logo uses Dimitri. Inspect the Theme for current values rather than maintain a duplicate token list in code or documentation. Font resources and their notices live under `assets/font/`.

Scripts bind data, signals, and context to those scenes. Dynamic lists and settings may instantiate saved row/widget scenes: `mechanism_settings.gd`, for example, chooses a numeric, flag, or text widget from the selected definition's `PieceSetting` resources. This keeps editable presentation shared while allowing content to vary.

World-anchored handles are a separate case. `SelectionOverlay` projects connector targets and snap contacts from 3D, and the wiring presentation uses the existing port contract. Centralize their presentation parameters rather than add unrelated sizing rules to construction logic.

## Show the actions that fit the task

In build mode, the shared HUD separates file/history actions from test/menu actions. The collapsible Pieces browser provides thumbnails, search, and categories; selection and placement controls appear when relevant. Preserve filters and scroll state while browsing. A small puzzle inventory should not leave a tall empty panel.

The inspector describes the current selection. A single configurable piece exposes settings and connection information; authoring also exposes player permissions. Group transforms belong with selection controls. Numeric-setting widgets commit one history change after a slider drag, so adjusting a value does not fill undo history with intermediate samples. The operation owner still enforces permissions when a control is disabled or hidden.

**Connect** edits relationships, while **Wires** controls their visibility independently. A player can inspect wiring during normal building without remaining in the connection tool. During simulation, editing controls give way to pause, reset, and camera follow, while navigation remains available.

The authoring drawer keeps whole-puzzle decisions together on the right. Setup owns presentation and rules; Inventory reuses the Pieces browser to define available quantities; Boundaries and Objectives connect controls to viewport selection; Publish explains readiness and the next useful action. Keep exact dimensions, proof details, and draft/sharing utilities subordinate to those primary tasks. A successful player test should make **Save solution** easy to find.

Boundary selection highlights the selected volume in gold. Mint describes permitted space and coral prohibited space. Selection alone does not dirty the draft; gestures are cancellable, opening a dialog cancels provisional work, and leaving boundary editing restores ordinary construction input. These transitions matter as much as the panel's appearance.

## Browsers should explain the choice

The campaign browser combines chapter progress, a numbered route, completion/lock symbols, and the selected starting-machine preview beside its goal. `CampaignDefinition` decides availability and the next destination; UI should display those decisions rather than reproduce progression rules.

Saved/example tracks preview actual registered geometry. Rename and delete belong to personal saves. Community browsing presents discovery results alongside the selected creation's details, installation state, and play action; share codes expand on request and owned-publication management remains contextual. Online results contain metadata rather than preview geometry, and a creator label is displayed only when available.

`scenes/ui/widgets/construction_preview.tscn` creates static previews from preview-only BuildingPiece instances in an isolated World3D. It frames measured mesh bounds and renders when content, visibility, or size changes. It does not load the reference solution or start another simulation. Keep starting-layout previews separate from solution disclosure.

The main menu keeps equally styled navigation beside the cinematic showcase. Hover and focus show interaction; no option gets a different default treatment. Preserve the showcase's real construction, camera, and music ownership when changing menu layout.

## Motion must respect input and lifecycle

World guidance shares one collision-free 3D marker scene and the existing guidance text strip. Gold means attention, mint target, blue direction, white interaction, and coral problem; captions identify the meaning without relying on color alone. Materials, icon transforms, and captions are editable in `scenes/guidance/marker.tscn`. The imported chevron's local -X tip is corrected to forward in its wrapper; semantic orientation then points it down or along the target direction. Markers do not bounce or glow, and disappear while placement overlays own the cursor target. Goal and Hint are contextual actions beside the puzzle name. Whole-puzzle guidance fields live on the existing Objectives page in a native Container layout.

`UIMotion` supplies shared timings and animates opacity and native Control offset transforms without taking layout away from Containers. The Pieces browser and authoring drawer use short slides, dialog surfaces use restrained scale/fade, and tab content fades briefly. Selection, snapping, placement, and simulation state changes stay immediate.

Main-menu buttons enter from the left with staggered elastic motion in scene order. Hidden actions and spacers do not consume delays. Choosing an action reverses the order for the exit before navigation proceeds. Reopening cancels pending dispatch; hiding settles unfinished motion. Each button becomes interactive after its own entrance completes, with its displayed transform and hit area aligned.

Visibility requests stay with the owner: WorkspaceHUD controls the browser and status, the authoring drawer controls itself, and `modal_window.gd` controls dialog surfaces. Repeated requests replace the active tween from its current presentation. Closing content immediately loses focus and descendant input, while the still-visible surface blocks clicks until hidden. Status duration uses the HUD's one-shot Timer.

For a shared modal, call `present()` to open and `dismiss(action)` to close before running an action. Reopening during dismissal cancels that pending action. The Window stays modal throughout the exit, and focus returns after hiding. Direct `hide()` immediately cancels the lifecycle for a context change. GameManager coordinates application fades, workspace input suspension, and deferred completion dialogs; avoid adding another competing transition owner.

## Write and review in context

Use short, specific sentence-case copy. State the outcome an objective requires, and let contextual Introduction hints teach the tools. Avoid repeated headings/status, internal state names, dense shortcut paragraphs, and unnecessary decimal precision. When a panel grows too large, reconsider visibility and information order before shrinking all the controls.

Review affected interfaces primarily at 1920×1080. Add window sizes when the change affects resizing, clipping, or layout. Exercise focus, Escape, scrolling, pointer blocking, interrupted animation, and the affected workflow. A screenshot can establish readability, while input and lifecycle need interaction. Report when visual inspection is unavailable; physics and save checks belong to their own systems.
