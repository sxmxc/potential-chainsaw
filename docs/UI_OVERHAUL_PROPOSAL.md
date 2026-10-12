# Marble Engineer — UI overhaul proposal

Status: approved and implemented. See [implementation and verification](UI_OVERHAUL_DELIVERY.md) for the final result and verification limits. The [interactive review](ui-proposal/review.html) preserves the approved design checkpoint; its controls operate mockups, not the game. The following audit and proposal describe that checkpoint.

The approved overhaul supersedes the earlier refinement layout and font-preservation direction. Implementation remains in the working tree.

## Audit and evidence

Reviewed the repository's architecture, mechanism contracts, scenes, shared Theme, UI scripts, input handling and campaign data. Inspected the running game through Hera, using one runtime and retrying transient busy responses. The runtime is stopped. Actual screenshots inspected include the main menu, sandbox single/group selection, campaign gameplay, chapter navigation and its empty state, Camera settings, and Puzzle Editor Setup/Publish tabs at a true 1280×720 render size. Other authoring tabs, save browsing, completion and shortcut pages were reviewed in source; their interaction behavior still needs live verification. This is an audit of the current working tree, including earlier refinement changes, rather than a claim that the original interface is untouched.

| Area | Finding | Design consequence |
|---|---|---|
| Shared HUD | A full-width file bar and another tool row form a ceiling over the track. Their size follows their parent, not their contents. | Separate identity/history from Test/Menu. Put construction helpers at the bottom of the viewport. |
| Inventory | Two visible cards still require heading, search and a full-width category selector. A one-piece inventory has excess structure. | One shared drawer with compact puzzle and searchable catalog variants. |
| Selection | Group selection exposes both a manipulation row and a nearly full-height inspector for only Lower/Raise and explanatory text. | One contextual action strip. Properties appear only for configurable pieces. |
| Campaign HUD | Title/objective/counter hierarchy is improved, but it still inherits the sandbox's wide bar and toolbox framing. | Lightweight objective above the world; content-sized inventory below it; progress beside testing. |
| Campaign navigation | Tall chapter column is mostly empty; each completed level repeats a word. Empty chapters inherit a large form. | Horizontal chapter navigation, completion symbols, content-sized level rows and a compact empty state. |
| Puzzle Editor | Seven tabs overflow horizontally at 720p; setup mixes ordinary authoring with IDs/order/export details. Publish explains a workflow in a paragraph, then repeats it in buttons. | A world-side drawer with a workflow rail; advanced metadata disclosed separately; explicit test/validation checklist. |
| Settings | Camera uses a large fixed-height dialog for a slider and button. Shortcut pages share that height. | Camera dialog fits its content; controls reference gets its own grouped, scrollable view. |
| Typography | Engplot renders ordinary labels as narrow uppercase shapes. Long names wrap despite generous panels. | Compare normal mixed-case sans fonts in the same component layouts. Preserve the logo treatment. |
| Dialog behavior | Modal ownership and world-input blocking are spread between GameManager, modal_window and individual dialogs. Authoring opens directly rather than through the same manager path. | Audit and unify focus/input lifecycle, preserving the ability to select world pieces while authoring. Do not call this a confirmed input leak without reproducing it. |
| Earlier refinements | Live review exposed a zero-height menu and a vertically exploding status label. Pending fixes predate this brief and are not accepted as verified. | Give status and dialogs bounded, content-aware layouts; explicitly regression-test minimum sizes. |

## Proposed screen compositions

### Main menu

Keep the stylized logo, palette and animated real-3D track. Place an unboxed navigation column in the quieter left third, with one mint Campaign action and secondary Sandbox, Saved tracks, Examples, Puzzle Editor and Settings actions. Quit stays separate at the foot. Use no slogans. Campaign opens navigation so the optional Introduction is never implied to be mandatory. The mockup background is a still from the live showcase only for this review; implementation retains animation and physics.

### Sandbox

Top left: track name, save and history controls in a content-sized island. Top right: Test track and Menu. Bottom left: Pieces drawer; two recognizable 112-pixel previews per row, names beneath, selected check/outline. Search and category browsing belong to the expanded catalog. Drawer height is capped by the viewport and scrolls internally; collapse leaves a single Pieces button with the active piece preview.

Bottom center: small Grid/Snap toggles, an elevation control and Fit view. These assist direct manipulation; they do not introduce a separate Move tool. Selection replaces this strip with rotate/duplicate/delete and group elevation controls while keeping placement helpers reachable. A mechanism selection opens a content-sized right properties card. Ordinary track selection needs no empty inspector. At 720p the selection strip wraps into two deliberate groups, with no text shrink. Floating regions use hit testing only over their actual controls, so the gaps remain usable world space.

### Puzzle gameplay

Top left: title and one objective, without a full-width panel. A dark local backing protects contrast over geometry. Top right: arrival progress, Test track, Menu. Bottom left: available pieces only; one or two cards do not show search/category chrome. Larger inventories use the same drawer as Sandbox. Fixed-piece actions remain hidden/disabled according to actual permissions.

An optional Introduction hint appears near the relevant inventory/placement action, dismisses explicitly and disappears when its step is complete. No idle instruction footer. Normal campaign copy states the outcome without a solution. During simulation the inventory and construction helpers retract; progress and Pause/Return to build remain. Return/reset preserves the construction. Failure uses a brief reason plus Try again, without opening another large panel.

### Selection and placement states

Idle: no inspector, no selection instructions. Ordinary single selection: small manipulation strip and visible world highlight. Mechanism: name, editable fields and units in a compact properties card, with advanced details disclosed below. Group: count and one action strip; elevation moves the rigid arrangement through existing operations. Placement: active card marked with a check; snapped connector ring plus short “Connector aligned” label. Rejection: existing preview plus rejection symbol/reason; never color alone. Escape cancels the current operation before affecting navigation. Do not change snapping, group transforms or physics as part of this UI work.

### Puzzle Editor

Use the same build viewport and drawer. Top identity says Draft once; primary actions are Save draft and Test as player. A right-side authoring drawer contains a vertical workflow selector: Setup, Pieces, Boundaries, Objectives, Links, Publish. Vertical navigation avoids seven overflowing tabs. Advanced chapter IDs/order/package export live under expandable Advanced sections.

Pieces switches between selected-piece permissions and player inventory, keeping the world selectable. Boundaries uses existing authoring operations with their world feedback; this design does not assume a new direct-drawing engine exists. Objectives selects real targets/events; Links uses existing source/action choices. Publish shows three concrete checks: completed player test, saved solution, current revision validated. Publish remains unavailable until existing validation permits it, with the missing step visible. Test as player uses the existing isolated copy and a clear Return to editor action. These are presentation changes around PuzzleSession, not a new authoring backend.

### Campaign navigation

A dedicated navigation overlay over the showcase, with horizontally arranged chapter choices and a short progression line. Introduction is visibly Optional. Rows use a number, title and completion/check or lock indicator; completion text is accessible to screen readers/tooltips but not repeated visually. Selected level gets its objective and one Play action. Continue is a separate action for the remembered eligible level; if it is also the selected level, that action replaces Play rather than duplicating it. Locked rows explain their actual prerequisite. An empty chapter shows “No levels available yet.” below its heading and Back, with no empty list/detail frame. Do not invent chapters or levels to fill the layout.

### Settings, saves, pause and completion

One title per dialog, a visible close control, Escape, focus entry/restoration and blocked world editing. Camera sensitivity/reset fits a short dialog. Controls uses grouped Building/Camera/Testing rows with aligned key chips and scrolling when necessary. The reference remains discoverable without filling the build screen.

Saved tracks and Examples share a list presentation. Rename is contextual to the selected save; delete asks confirmation because it removes stored content. Ordinary edits, reset and selection do not gain confirmations. Save-name input gets focus and shows actionable errors inline. A compact pause menu uses mode-specific actions: sandbox file actions, campaign Restart/Levels, editor Save/Test/Authoring, player-test Return to editor. Completion keeps the solved world visible and emphasizes Next puzzle; Keep building and Levels are secondary. Editor test completion emphasizes Save solution/Return to editor. Error dialogs identify the failed action and an available recovery, without developer trace text.

## Visual and type system

Keep dark teal local surfaces, mint actions, gold selection, coral rejection and the colorful kit. Leave most of the world uncovered. Avoid nested panel backgrounds; use spacing/separators inside actual inventories or forms. Secondary actions use quieter surfaces. Delete has a separate icon/label and restrained coral treatment. Selected controls have a check and outline; focus has an independent outer ring; active snap has an icon/state label; disabled actions retain readable labels and explain the reason.

Proposed type roles: screen title 28/700; section 20/700; objective/body/buttons/piece names 16/600 or 400; secondary/tooltip 14/400; numeric readouts 16 with tabular figures when available. Preserve the stylized brand font at its existing display role. Spacing ladder 4/8/12/16/24. Minimum ordinary target height 40 pixels, primary actions 44; icon controls 40 square. Long piece names wrap to two lines rather than reducing type. Preview images stay recognizable.

**Provisional preference: Nunito Sans.** Its softer mixed-case text fits the models; Rubik offers a more angular alternative. The interactive review compares all three in a button/goal, catalog card, mechanism field and status component using real project labels/assets. These are browser mockups, not native Godot font verification. Before final font selection, approved implementation must compare actual Godot controls at all three resolutions, including glyph coverage, line wrapping and numeric fields. No font has been installed into the game.

Candidate font files and required license notices are embedded in the offline review. Both candidates use the SIL Open Font License: [Nunito Sans source/license](https://github.com/google/fonts/tree/main/ofl/nunitosans), [Rubik source/license](https://github.com/google/fonts/tree/main/ofl/rubik). Approved redistribution will retain each full notice alongside the game font.

## Before/after writing guide

Strings below are from project scenes/scripts, campaign data, or the supplied examples identifying the earlier baseline. Existing short copy is kept when useful. Display copy must not modify validated puzzle fingerprints or stable IDs.

| Existing text | Proposed display | Reason |
|---|---|---|
| First Connection · Bridge the missing track and deliver one marble. | First Connection / Get the marble to the finish. | Title once; outcome only. |
| Choose Straight, point at a glowing connector, and click. Test track runs the marble. | Select a straight track. → Click a connector to attach. | Introduction steps appear only when needed. |
| 1 pieces · Hover for details | Remove the footer; inventory quantity on the card if limited | Grammar and redundancy. |
| Height: 0 m / Ground | 0 m / tooltip: Reset placement height | Units in readout, explanation on demand. |
| Frame all / Fit view | Fit view; tooltip: Show the whole track | Keep concise existing refinement. |
| 01 First Connection · Complete | 01 First Connection + check symbol | Scan titles without repeated status words. |
| Heights stay together / Rotates around the first selected piece. | Remove permanent prose; retain rotation-pivot tooltip | Group controls explain available action without a paragraph. |
| Chapter ID (reuse an ID or create a new chapter) | Chapter; Advanced → Chapter ID | Ordinary selection separated from technical metadata. |
| Validate current revision | Validate | Revision state belongs to the checklist. |
| Save draft → Test as player → preserve successful solution → return here → Validate → Publish… | Player test / Saved solution / Validation checklist | Communicate current task instead of repeating a workflow. |
| A successful player test is required. | Complete a player test to publish. | Missing step and purpose. |
| Select a track and enter its new name | New track name [input]; Rename unavailable until valid | Prevent an avoidable error rather than explaining after a click. |
| No saved tracks yet. / No levels available yet. | Keep | Already direct and appropriate. |
| A little gravity. A lot of possibilities. / Dream it. Build it. Let it roll. | Remove both | The live showcase supplies personality. |

Terminology: piece, track, finish, Test track, Return to build, Test as player, Return to editor, Save draft. Preserve “collector” where an actual objective targets a mechanism whose meaning differs from a finish. Use sentence case, integer counts with singular/plural, useful units and brief action-specific errors. No new campaign solutions, hints or mechanics are authored by this proposal.

## Responsive rules and implementation sequence

The review can switch 1280×720, 1600×900 and 1920×1080 logical layouts. Controls retain their type/target sizes as the world grows. At 720p inventory and authoring widths are bounded; contextual strips wrap; secondary metadata is disclosed rather than squeezed. Wider screens add usable world space, not taller empty panels. The embedded world image is stretched as a mockup backdrop; this is not proof of the game's camera/aspect behavior.

After approval: (1) checkpoint existing work and reconcile earlier refinements; (2) shared Theme/type/button/focus/dialog components; (3) sandbox inventory/build/selection/simulation; (4) campaign HUD/navigation; (5) editor workflow; (6) main menu/settings/saves/completion; (7) writing sweep and regression verification. Reuse existing scene controllers, data-driven catalog, BuildManager, PuzzleSession and SimulationManager. Static layouts belong in saved scenes/Containers and shared Theme variations. Do not create parallel managers.

Verification must cover native font rendering and all screens at three resolutions through Hera, UI click-through and focus, direct selection/drag/cancel/snapping, single/group undo and permissions, test/pause/reset preserving builds, save/load, modal escape, Introduction progress compatibility, authoring isolated tests and publication gates. Earlier headless tests passed before the latest brief, but do not verify this proposal. Save/delete/publish interactions and all-resolution native layouts remain unverified. No implementation is authorized by this document alone.

## Approval decision

Review artifact checks: its JavaScript generated markup for all 243 screen/state/font/resolution combinations without unresolved data or script errors. Four embedded fonts and their candidate license notices are included; the review has no external network dependencies. This was a script/markup check, not browser visual inspection. Existing game-scene whitespace warnings from earlier work remain pending with implementation; no game files were edited to clear them during this design-only phase.

Approve or revise the six compositions, contextual state changes, horizontal chapter navigation, authoring drawer, and provisional Nunito Sans direction before implementation. Font choice remains subject to the native component comparison described above.
