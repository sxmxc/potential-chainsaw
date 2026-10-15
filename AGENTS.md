# AGENTS.md — Marble Engineer

Operational instructions for coding agents. The repository defines current behavior; design constraints below are not evidence that a feature is complete.

## Investigate before editing

- Read the relevant guide and trace the affected scene, owner, callers, signals, resources, and tests. Check input, persistence, permissions, and lifecycle interactions when relevant.
- Inspect `project.godot` and installed addon metadata before choosing APIs. The project targets Godot 4.7, GDScript, Jolt physics, and Forward Plus. Consult official Godot/addon documentation for unfamiliar APIs.
- Inspect actual GLB geometry, pivots, hierarchy, orientation, and collision needs. Never infer dimensions or functionality from filenames. Preserve original imported assets; edit wrapper scenes/resources.
- State the smallest coherent change and its regression risks. Preserve unrelated edits and user content; use a version-control checkpoint before substantial refactors when appropriate. Ask about new game-design choices rather than inventing mechanics or content.

## System map and boundaries

Read [Architecture](docs/ARCHITECTURE.md) for ownership and [Puzzle authoring](docs/PUZZLE_AUTHORING.md) for formats and publication.

- `scenes/construction_workspace.tscn` binds the World, `ConstructionSession`, and shared HUD. Session contexts are Sandbox, Authoring, Puzzle Play, and Player Test. Apply mode differences through data and permissions; never create another construction or simulation engine.
- `scripts/construction/` owns placement, snapping, selection, history, definitions, and behavior contracts. `scripts/simulation/` owns marble runs. `scripts/campaign/` owns puzzle rules, persistence, objectives, registration, and progression. `GameManager` hosts application navigation and dialogs.
- YARD's `resources/registries/piece_registry.tres` is the authoritative catalog. Use `PieceCatalog` and the registry API; do not add filesystem scans or parallel catalogs. Registry IDs must equal `PieceDefinition.id`. Editor Play/export rebuilds indexes; headless runtime tests consume the saved index. Preserve stable piece and instance IDs.
- Tracks, mechanisms, supports, and authoring scenery use the shared piece system. Functional scenes compose `PieceBehavior` nodes with scene-authored `PieceSetting` resources. Reuse this lifecycle, configuration, and port contract; see [Piece authoring](docs/PIECE_AUTHORING.md).
- Game code calls `CommunityService`; provider details belong in `scripts/community/supabase_backend.gd`. Keep `addons/supabase_client/` reusable and project-agnostic: no puzzle schemas, Steam, game routes, or campaign rules. `SteamClient` owns local Steam integration; only server ticket verification establishes online identity. See [Community service](docs/COMMUNITY_SERVICE.md).

## Engineering conventions

- Use typed GDScript where practical, focused scenes, reusable Resources, signals, InputMap actions, and explicit ownership. Check inherited members before naming variables. Fix warnings in touched scripts; do not suppress warnings to pass checks.
- Keep behavior local and traceable. Reuse existing owners instead of adding managers, forwarding layers, fallback paths, duplicate state, or speculative abstractions.
- Preserve save/progress compatibility and stable content IDs; introduce explicit migrations when changing formats. Puzzle data resolves registered assets only; arbitrary scene references and published scenery snapshots are retired.
- Preview and commit must use the same placement validation. Connector snapping aligns position, orientation, and elevation using visible cursor-intended targets; the active grid plane is a fallback. Preserve cancellable direct dragging and rigid group transforms. Exclude the moving group from snap targets and record group operations atomically.
- Enforce puzzle permissions in actual operations, including shortcuts, settings, links, duplication, history, and group edits. Definitions marked `authoring_only` are excluded from player inventory; ordinary decorative props are regular construction pieces. Floating tracks are allowed; mandatory supports require a design decision.
- Ordinary marble travel uses rigid-body physics. Controlled transport is allowed while intentionally captured, as with the existing bucket elevator; restore physics/collision state on release/reset. Shrouded fans provide airflow; exposed `fan-simple-*` models are rotating paddles. Verify transitions and multi-marble behavior in simulation.

## Puzzles and content

- Preserve the ten optional Introduction puzzles, stable IDs, progress, and reference solutions. Introduction and Sandbox must not gate the main campaign.
- Author puzzles through the shared visual editor. Record the engineering problem, meaningful player choices, constraints, and mechanics before building a level. Base designs on observed behavior, not assumed physics.
- Test as Player with real inventory, permissions, and objectives; preserve the working solution separately from the incomplete starting layout. Publishing requires a current successful test and saved solution. Objectives judge simulation results, never similarity to one layout. Human playtesting is needed to assess fun.
- Retries remain unlimited and simulation reset preserves the build. Do not change global marble physics to rescue unverified content or deliver untested puzzle batches.

## UI and writing

- Build editable `.tscn` layouts with native Controls, Containers, anchors, size flags, and minimum sizes. Shared styling belongs in `resources/sandbox_theme.tres`; local scene layout values are valid. Scripts bind data and behavior rather than constructing static screens.
- Remove obsolete manual layout hacks in the interface being changed. Do not calculate ordinary positions from viewport dimensions, reposition normal controls in `_process()`, or override Container layout. Intentional icon sizes and bounded panel widths are valid. Project world-anchored handles from 3D and centralize their presentation parameters.
- Keep the construction visible, controls readable, and actions appropriate to the current mode. Resolve oversized UI with contextual visibility and information structure. Preserve the identity, logo, and animated real-3D menu showcase. See [UI design](docs/UI_DESIGN.md).
- Write short, natural player-facing copy in sentence case. Avoid duplicated titles/status, developer terminology, dense shortcut paragraphs, and campaign instructions that reveal solutions.
- Review affected UI primarily at 1920×1080. Check additional sizes when resizing/layout behavior is affected; do not repeat multi-resolution screenshots for routine changes. Report when visual inspection is unavailable.

## Verification and delivery

- Use installed GUT and `tests/test_*.gd`, through its panel or standard CLI in the README. Do not invent verification runners or one-off test scripts, force compiler warnings, or modify/publish campaign fixtures as a test side effect.
- Pure tests extend `GutTest`. Persistence tests extend `tests/support/game_test.gd`. Keep the default suite focused on owners and contracts; do not add full-application navigation, screenshots, campaign playthroughs, or live-service checks unless explicitly requested. Use GUT lifecycle/autofree methods, isolate saves, and restore previous globals. Do not inspect addon internals or runner paths for teardown.
- Run parsing/resource checks and focused tests appropriate to the change. Verify interactive, physics, reset, undo/redo, save/load, and cross-mode behavior where affected. Parsing alone does not establish gameplay correctness; keep verification proportionate.
- Update the owning documentation when behavior, APIs, formats, or setup changes. Keep README human-facing, architecture explanations in their guides, and this file operational. Do not modify third-party documentation or licenses.
- Report what changed, what actually passed, and what remains unverified. Never claim physics, screenshots, deployments, or live authentication were tested without evidence.
