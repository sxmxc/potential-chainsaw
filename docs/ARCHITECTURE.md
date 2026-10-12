# Architecture rules

## Shared construction and simulation

- `scenes/world.tscn` and `scripts/world_manager.gd` provide the shared construction world. Sandbox, campaign, puzzle editing and Test as Player use the same BuildManager and SimulationManager.
- BuildManager owns placement, connector snapping, selection, configuration and snapshot history. Validate complete proposed edits before committing. Group edits are atomic; one forbidden member rejects the whole operation.
- PieceDefinition resources own catalog metadata, connectors, bounds and thumbnails. Changing an adjustable piece must update its geometry, collision, connectors and placement bounds together. Reject conflicting changes without leaving partial state.
- SimulationManager owns releases, physical motion and completion. Mechanisms use collision, forces and impulses. Collectors and mechanism events determine success; a reference solution is never the completion test.
- Pause suspends mechanism motion and release scheduling. Reset clears runtime state and restores configured initial state while preserving construction.
- Elevator capture temporarily owns one marble per bucket. Restore its collision and freeze state on release or reset; discharge above the output track and let physics carry it onward.
- The menu showcase has its own SubViewport and World3D. It must not modify the playable world's construction or saves. Its camera animation lives in the saved scene.
- GameManager switches menu/world music on mode transitions. World also appears in the showcase, so scene `_ready()` must not start its playlist.

## Puzzle rules and persistence

- PuzzleSession changes modes on the shared World. Sandbox is unrestricted; campaign and Test as Player use the same PuzzleRules.
- Inventory is derived from the current layout. Duplication consumes stock; deletion and undo restore it. Permissions and boundaries apply to complete edits, including configured dimensions and mechanism links.
- Keep authored starting layouts separate from player constructions and reference solutions. Returning from Test as Player restores the authored baseline.
- PuzzleStore owns versioned JSON, progress and validation fingerprints. Drafts, published puzzles and campaign progress use separate user paths. Bundled levels live in `resources/campaign/`.
- Chapters are data-driven through `resources/campaign_chapters.json` and puzzle chapter metadata. Introduction is optional and never gates main chapters. Both Next controls use PuzzleStore's chapter navigation. Preserve flat completion records by stable puzzle ID; store route/resume state separately in `campaign_state.json`.
- Publishing requires a successful physical test matching the current authored definition. Content changes invalidate that proof. Revisions retain stable puzzle IDs.
- Preserve existing track-save compatibility. Mechanism links use stable piece IDs, survive saves, remap within duplicated assemblies and are removed when their targets are deleted.

## Native scenes and UI

- Keep presentation in saved `.tscn` scenes and the shared `resources/sandbox_theme.tres`. Scenes must be inspectable and previewable before `_ready()` runs. Do not generate scene files at runtime.
- UI scripts bind data, connect signals and update visibility, enabled states and Theme variations. Keep game logic, persistence, physics, snapping and history out of presentation code.
- Ordinary controls and StyleBoxes belong in saved scenes and the Theme. Dynamic lists instantiate reusable saved widgets such as `piece_card.tscn`.
- Containers own internal layout; anchors position outer panels. Layout minimum sizes live in scenes. Reusable fonts, colors, spacing and control states live in the Theme, rather than per-node overrides.
- Use the project-wide Theme and explicit shared Theme references in reusable scene roots. Preserve the selected fonts. See [UI design](UI_DESIGN.md) for interaction and visual rules.

## Checks and generated output

Run `./tools/verify_campaign.ps1` after construction, mechanism or campaign changes. It checks enabled compiler warnings, regression suites and positive/negative campaign cases. `SavePaths` redirects only application saves through `MARBLE_ENGINEER_TEST_DATA`; saves and logs use an automatically cleaned OS temporary directory. Never redirect `APPDATA` or copy Godot/project caches for tests. Generated evidence does not belong in `docs/`.

Use the existing Godot editor for scene changes and live checks. Keep one editor per project. Review UI changes at small and large viewport sizes and exercise the affected interaction, rather than relying on source inspection alone.
