# UI design

The construction is the visual priority. Players need to see where a piece will go, what they have selected, and what happened during a run. Panels should support those decisions without covering the machine or showing every possible action at once.

The visual style combines colorful track pieces, the stylized gold logo, and an animated real-3D menu machine. Dark teal surfaces frame the construction; mint marks actions, gold marks selection, and coral marks rejection. Pair color with text or symbols so it is never the only explanation.

This guide is for changes to interface scenes and behavior. [Puzzle authoring](PUZZLE_AUTHORING.md) owns the detailed editor workflow; [Architecture](ARCHITECTURE.md) explains the workspace and application boundaries.

## Build the layout in scenes

Static interfaces belong in editable `scenes/ui/*.tscn` scenes. Use anchors for outer placement and Containers for internal layout, with size flags, minimum sizes, and scrolling to handle growing content. Local panel widths and icon sizes are useful constraints; ordinary layout should not depend on calculating positions from viewport dimensions or overriding a Container's decisions.

`resources/sandbox_theme.tres` holds shared fonts, colors, spacing, control states, and type variations. Body text uses Nunito Sans and the logo uses Dimitri. Inspect the Theme for current values rather than maintain a duplicate token list in code or documentation. Font resources and their notices live under `assets/font/`.

Scripts bind data, signals, and context to those scenes. Dynamic lists and settings may instantiate saved row/widget scenes: `mechanism_settings.gd`, for example, chooses a numeric, flag, or text widget from the selected definition's `PieceSetting` resources. This keeps editable presentation shared while allowing content to vary.

World-anchored handles are a separate case. `SelectionOverlay` projects connector targets and snap contacts from 3D, and the wiring presentation uses the existing port contract. Centralize their presentation parameters rather than add unrelated sizing rules to construction logic.

Trajectory feedback uses the same overlay owner but renders as a depth-tested 3D line, so nearer geometry occludes it. The saved overlay scene owns its mesh and unshaded material; the line takes its color from the shared Theme. Behaviors supply world-space paths and stop them at predicted physical contact. Hiding the HUD or leaving Build mode clears this feedback.

## Show the actions that fit the task

In build mode, the shared HUD separates file/history actions from test/menu actions. The full-width bottom dock sits below the side-panel columns, so opening both panels cannot squeeze the build tools into a vertical strip. The collapsible Pieces browser provides thumbnails, search, and categories; selection and placement controls appear when relevant. Preserve filters and scroll state while browsing. A small puzzle inventory should not leave a tall empty panel. Ordinary catalogs fill their column and scroll; never feed the previous column height into the catalog minimum during resizing. Cards share a three-line caption area and use the catalog display name without ID-specific text substitutions.

The inspector describes the current selection. A single configurable piece exposes settings and connection information; authoring also exposes player permissions. Group transforms belong with selection controls. Numeric-setting widgets commit one history change after a slider drag, so adjusting a value does not fill undo history with intermediate samples. The operation owner still enforces permissions when a control is disabled or hidden.

**Connect** edits relationships, while **Wires** controls their visibility independently. A player can inspect wiring during normal building without remaining in the connection tool. During simulation, editing controls give way to pause, reset, and camera follow, while navigation remains available.

The authoring drawer keeps whole-puzzle decisions together on the right. Setup owns presentation and rules; Inventory reuses the Pieces browser to define available quantities; Boundaries and Objectives connect controls to viewport selection; Publish explains readiness and the next useful action. Use shared FormHeading, FormFields, and FieldPair variations for section breaks and label/value spacing. Setup separates puzzle details and starting view from run rules, awards, and campaign placement. Campaign-only groups follow the session destination. Keep exact dimensions, proof details, and draft/sharing utilities subordinate to those primary tasks. A successful player test should make **Save solution** easy to find.

Boundary selection highlights the selected volume in gold. Mint describes permitted space and coral prohibited space. Selection alone does not dirty the draft; gestures are cancellable, opening a dialog cancels provisional work, and leaving boundary editing restores ordinary construction input. These transitions matter as much as the panel's appearance.

## Connection art direction

Enabling Connect or Wires deliberately makes the automation network a visual focus. Luminous conduits use a slender dark jacket with three narrow luminous channels, a mint-to-periwinkle gradient, and continuous bands traveling from sender to receiver. Curve height follows horizontal span with a bounded rise; stacked endpoints use a lateral bow instead of a tall loop. Animation describes direction only; it does not report signal traffic or simulation state. Fan-out routes separate in height and depth. Opaque depth testing resolves crossings; a broken translucent silhouette keeps occluded portions traceable through machinery.

Terminals sit above definition bounds and follow movement previews. Raised mint emitters identify outputs; recessed periwinkle sockets identify inputs. Connect shows distinct input/output terminals, with short OUT/IN captions on the current interaction and gold receiver/hover feedback. Receiver snapping uses the visible input handle within 16 pixels; the projected component body does not attract the wire. Wires shows terminals for existing relationships. Selection and inspection bring related cables toward gold with a short width/color transition; unrelated cables retain their presence. Dragging previews the same 3D conduit used by saved relationships, snapping to the receiver's elevation. The pending conduit remains visible while choosing ports/actions and clears on Apply or Cancel. A successful connection briefly emphasizes the resulting cable.

`MechanismWiring` retains interaction, permissions, and visibility ownership. `WiringConduit` caches one tube per relationship and supplies the same projected centerline for picking; camera movement only changes projection. Distance-based shader animation needs no mesh rebuilds or lights. Terminal geometry is editable in `scenes/ui/widgets/wiring_terminal.tscn`; shaders and `resources/wiring_conduit_material.tres` own the cable finish. Semantic colors remain in `resources/sandbox_theme.tres`. The network has no collision and hides with the HUD, input suspension, or simulation. Human review of composition, crowded networks, close views, and distant readability remains necessary.

## Shared dialog presentation

GameManager owns the dimming backdrop and workspace suspension for shared modals. Dialog surfaces use the shared SurfacePanel style and DialogContents/DialogColumns/DialogFooter spacing. Native Window wrapping sizes content; wrapped labels need an authored useful minimum width so their initial narrow measurement cannot inflate the window height. Settings uses category navigation beside one scrolling page; authoring keeps its five tabs on one row.

The [UI review record](UI_AUDIT.md) lists rendered coverage, fixes, and unresolved design issues. A captured layout does not establish that its interaction or live-service flow works.

## Browsers should explain the choice

The campaign browser combines chapter progress, a numbered route, completion/lock symbols, and the selected starting-machine preview beside its goal. `CampaignDefinition` decides availability and the next destination; UI should display those decisions rather than reproduce progression rules.

Saved/example tracks preview actual registered geometry. Rename and delete belong to personal saves. Community browsing presents discovery results alongside the selected creation's details, installation state, and play action; share codes expand on request and owned-publication management remains contextual. Online results contain metadata rather than preview geometry, and a creator label is displayed only when available. The online page scrolls within a bounded region, while service feedback and the primary play/download action stay outside that region. Long messages and puzzle descriptions use plain, selectable RichTextLabel content with native scrolling and scene-authored maximum sizes; player text is not interpreted as BBCode.

`scenes/ui/widgets/construction_preview.tscn` creates static previews from preview-only BuildingPiece instances in an isolated World3D. It frames measured mesh bounds and renders when content, visibility, or size changes. It does not load the reference solution or start another simulation. Keep starting-layout previews separate from solution disclosure.

The main menu keeps equally styled navigation beside the cinematic showcase. Hover and focus show interaction; no option gets a different default treatment. Preserve the showcase's real construction, camera, and music ownership when changing menu layout.

## Motion must respect input and lifecycle

World guidance pairs a collision-free 3D marker with one instruction card above the build controls. The world marker has no generic caption: its shape locates the target, while the card carries the actual instruction and step progress. Gold means attention, mint target, blue direction, white interaction, and coral problem. Materials, icon transforms, and the short arrival animation are editable in `scenes/guidance/marker.tscn`. The imported chevron's local -X tip is corrected to forward in its wrapper; semantic orientation then points it down or along the target direction. Destination marks sit close to the marked surface. A changed target uses a short movement and arrival; ordinary refreshes do not restart it. Pointer arrows continuously tween toward their target and ease back, using the marker root�s Pointer distance and Pointer period settings. Direction arrows move along their indicated axis; downward pointers bob vertically. Unchanged refreshes preserve the running loop. Destination and problem marks stay still. All marker tweens stop immediately during placement or context changes; markers have no glow, shadow, or collision.

WorkspaceHUD uses `UIMotion` to bring the card in and out, and briefly fades changed instruction text without moving its Container layout. Repeated refreshes retain the current animation. Step count stays beside the instruction. Next appears only for manually advanced hints, with Done on the final manual hint; selection, connection, and run steps advance through the player's action. Goal briefly highlights the destination without displaying a generic label. **Objectives → Player hints** leads with a piece, instruction, and advance condition; optional marker, track-end, and timing controls stay under Advanced. Preview shows authored instructions with their marker. The fields stay in the existing Objectives page with native Containers.

`UIMotion` supplies shared timings and animates opacity and native Control offset transforms without taking layout away from Containers. The Pieces browser and authoring drawer use short slides, dialog surfaces use restrained scale/fade, and tab content fades briefly. Selection, snapping, placement, and simulation state changes stay immediate.

Main-menu buttons enter from the left with staggered elastic motion in scene order. Hidden actions and spacers do not consume delays. Choosing an action reverses the order for the exit before navigation proceeds. Reopening cancels pending dispatch; hiding settles unfinished motion. Each button becomes interactive after its own entrance completes, with its displayed transform and hit area aligned.

Visibility requests stay with the owner: WorkspaceHUD controls the browser and status, the authoring drawer controls itself, and `modal_window.gd` controls dialog surfaces. Repeated requests replace the active tween from its current presentation. Closing content immediately loses focus and descendant input, while the still-visible surface blocks clicks until hidden. Status duration uses the HUD's one-shot Timer.

For a shared modal, call `present()` to open and `dismiss(action)` to close before running an action. Reopening during dismissal cancels that pending action. The Window stays modal throughout the exit, and focus returns after hiding. Direct `hide()` immediately cancels the lifecycle for a context change. GameManager coordinates application fades, workspace input suspension, and deferred completion dialogs; avoid adding another competing transition owner.

## Write and review in context

Use short, specific sentence-case copy. State the outcome an objective requires, and let contextual Introduction hints teach the tools. Avoid repeated headings/status, internal state names, dense shortcut paragraphs, and unnecessary decimal precision. When a panel grows too large, reconsider visibility and information order before shrinking all the controls.

Review affected interfaces primarily at 1920×1080. Add window sizes when the change affects resizing, clipping, or layout. Exercise focus, Escape, scrolling, pointer blocking, interrupted animation, and the affected workflow. A screenshot can establish readability, while input and lifecycle need interaction. Report when visual inspection is unavailable; physics and save checks belong to their own systems.
