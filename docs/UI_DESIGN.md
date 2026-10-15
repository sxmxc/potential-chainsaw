# UI design

The construction is the visual priority. Preserve the animated real-3D menu machine, colorful Kenney pieces, stylized gold logo, dark teal surfaces, mint actions, gold selection, and coral rejection. Pair color feedback with text or symbols.

## Scenes and theme

`resources/sandbox_theme.tres` owns shared fonts, colors, spacing, control states, and type variations. Body text uses Nunito Sans; the logo uses Dimitri. Font resources and license notices live under `assets/font/`. Inspect the Theme for current numeric values rather than maintaining a second token list here.

Compose static UI in editable `scenes/ui/*.tscn` scenes with Controls and Containers. Anchors position outer panels; Containers own internal sizing. Use size flags, minimum sizes, scrolling, and contextual visibility for content growth. Local layout dimensions are valid; ordinary viewport-position calculations and Container overrides are not. World-anchored wiring handles use 3D projection.

## Workflows

- Main menu: navigation beside the showcase, with Campaign prominent and secondary actions quieter.
- Building: separate file/history and test/menu islands; a collapsible toolbox with catalog thumbnails, search, and categories; contextual placement/selection controls. Keep filters and scroll state while browsing. Small inventories should not create tall empty panels.
- Inspector: settings for a configurable single piece, player permissions during authoring, and connection counts. Group operations belong in the selection controls. Use shared numeric-setting widgets to commit one history change after a slider drag.
- Wiring: Connect edits relationships; Wires independently displays them while normal building continues. Presentation uses the existing port contract.
- Simulation: hide editing controls and expose pause, reset, and camera-follow actions. Keep navigation available.
- Puzzle Editor: a right-side drawer with Setup, Inventory, Boundaries, Objectives, and Publish pages. Object edits stay in the shared world/inspector. Publishing exposes actual test/solution/validation requirements.
- Browsers and dialogs: one clear title, focus entry/restoration, Escape behavior, scrolling, and blocked world input. Actions reflect the current context; campaign menus do not offer personal-track management.

Player copy should be short and specific. Objectives state outcomes; contextual Introduction hints teach tools. Avoid repeated titles, internal state terms, dense shortcut prose, and unnecessary decimal precision. Preserve readable type and comfortable interaction targets rather than shrinking the whole interface.

## Motion and input

`UIMotion` holds shared short ease-out timings and animates Control opacity and native offset transforms. Container layout stays authoritative. The piece browser and authoring drawer slide by a small fraction of their own size; dialog surfaces use restrained scale and fade. Press feedback preserves stationary button hit targets. Tab content fades briefly, while selection, placement, snapping, and simulation state changes remain immediate.

Existing owners request visibility: WorkspaceHUD owns the browser and status notification, the authoring drawer owns its opening/closing, and `modal_window.gd` owns dialog surfaces. Repeated panel requests replace the active Tween from its current presentation. Closing content loses focus and descendant input immediately; the visible surface blocks clicks until it hides. Cancellation restores neutral transforms and prior input settings. Status hold time uses the HUD's one-shot Timer.

GameManager coordinates menu/workspace fades and suspends workspace input until navigation finishes. It retains existing showcase camera and music ownership. Shared modal `present()` / `dismiss(action)` calls allow reopening to cancel a pending dismissal; actions run after the exit and hide, while the Window retains modality throughout the exit. Direct `hide()` remains an immediate lifecycle cancellation for context changes. Completion waits for other application dialogs to close before opening. Do not add another competing fade or delay gameplay operations to match UI motion.

## Review

Review affected screens primarily at 1920×1080. Test additional window sizes when the change concerns resizing, clipping, or layout; routine changes do not need repeated three-resolution screenshot passes. Check focus, scrolling, pointer blocking, and the affected workflow. Report visual limitations honestly. Physics and persistence verification belong to their owning systems; screenshots do not establish those behaviors.
