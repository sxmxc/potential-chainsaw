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
- Marble Engineer has one construction system: BuildManager places and edits tracks and environment instances with the same previews, selection, rigid group transforms and history. PieceDefinition determines connectors and collision behavior; modes and PuzzleRules determine permitted operations. Environment definitions reference reusable scenes with native static solids and are authoring-only. PuzzleSession loads gameplay scenery as fixed geometry outside player construction.
- History snapshots include both object types; track saves, inventories and reference solutions remain track-only. Puzzle JSON retains separate track and environment placement collections, stable IDs and legacy scene references. Referenced scenes are editable composites in authoring, with optional placement data; their internal geometry and published snapshots remain intact. Fingerprints include placements and scene/dependency contents. Publication still freezes native environment resources into revision snapshots used by Campaign and included in campaign ZIPs.
- Publishing requires a successful physical test matching the current authored definition. Content changes invalidate that proof. Revisions retain stable puzzle IDs.
- Preserve existing track-save compatibility. Mechanism links use stable piece IDs, survive saves, remap within duplicated assemblies and are removed when their targets are deleted.

## Native scenes and UI

- Keep presentation in saved `.tscn` scenes and the shared `resources/sandbox_theme.tres`. Scenes must be inspectable and previewable before `_ready()` runs. Do not generate scene files at runtime.
- UI scripts bind data, connect signals and update visibility, enabled states and Theme variations. Keep game logic, persistence, physics, snapping and history out of presentation code.
- Ordinary controls and StyleBoxes belong in saved scenes and the Theme. Dynamic lists instantiate reusable saved widgets such as `piece_card.tscn`.
- Containers own internal layout; anchors position outer panels. Layout minimum sizes live in scenes. Reusable fonts, colors, spacing and control states live in the Theme, rather than per-node overrides.
- Use the project-wide Theme and explicit shared Theme references in reusable scene roots. Preserve the selected fonts. See [UI design](UI_DESIGN.md) for interaction and visual rules.

## Resource registries

YARD's `resources/registries/piece_registry.tres` is the authoritative piece catalog. It scans `PieceDefinition` resources in `resources/pieces` and indexes `category` and `behavior`. Registry string IDs must match each definition's persistent `id`, including the existing `environment:partition`, `environment:deck`, `environment:column` and `environment:machine` IDs. Auto-scanning preserves existing registered IDs; when adding a resource, give its registry entry the same ID as the definition. See the installed [YARD documentation](../addons/yard/README.md) and in-editor `Registry` class reference.

The installed addon automatically rescans and rebuilds configured property indexes on editor Play and export. Its manual Reindex button is disabled; the README's manual reindex instruction is outdated for this installation. Headless runtime/GUT invocations consume the saved registry and do not invoke the editor's build hook. Tests should use the saved index rather than add a custom reindexing runner.

`PieceCatalog` loads entries through `Registry.load_entry` and queries through `Registry.where`; it owns presentation sorting and compatibility with legacy reusable-scene placements. Toolbox category filtering uses the property index, while inventories, extension choices, persistence and construction all resolve the same registered definitions. Support assemblies resolve their hidden sections through the same registry. There is no runtime directory scan, separate environment catalog or duplicate ID lookup table. Native scenery definitions are saved resources referencing the existing scenes and collision solids. Unregistered legacy and user-authored scene placements remain on-demand composites; they are not library entries. Keep mode permissions and native geometry in their existing systems.

## Checks and generated output

Use GUT from the Godot bottom panel or `godot --headless --path . --script addons/gut/gut_cmdln.gd -gexit`. `.gutconfig.json` discovers native GUT suites in `tests/`. Fixtures isolate tracks, puzzles, campaign progress, and settings in unique `user://gut-tests/` directories and clean them during teardown. Tests assert behavior; they do not force compiler warnings, publish levels, or rewrite bundled resources. Never redirect `APPDATA` or copy project caches for tests. Generated evidence does not belong in `docs/`.

Use the existing Godot editor for scene changes and live checks. Keep one editor per project. Review UI changes at small and large viewport sizes and exercise the affected interaction, rather than relying on source inspection alone.
