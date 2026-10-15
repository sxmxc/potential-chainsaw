# Working on Marble Engineer

These instructions apply to coding agents. Use the repository to establish current behavior; a design rule is not evidence that a feature is complete.

## Before changing anything

Read the relevant guide, then trace the affected scene, owner, callers, resources, and tests. Check input, permissions, persistence, and lifecycle transitions where they matter. Describe the smallest coherent change and its regression risks. Preserve unrelated work, and ask before introducing new game-design choices.

Inspect `project.godot` and installed addon metadata before choosing APIs. This is a Godot 4.7 GDScript project using Jolt and Forward Plus. Use official documentation for unfamiliar engine or addon APIs. For asset work, inspect actual geometry, hierarchy, pivots, and collision needs; preserve imported assets and change wrapper scenes/resources.

## Work within the existing owners

The [architecture guide](docs/ARCHITECTURE.md) explains the shared construction workspace. Sandbox, Authoring, Puzzle Play, and Player Test use that workspace and its simulation. Express differences through session data and permissions rather than another editing or simulation engine.

- Use `PieceCatalog` and YARD's `resources/registries/piece_registry.tres` for catalog membership. Registry IDs must match `PieceDefinition.id`; preserve those IDs and saved instance IDs. Editor Play/export rebuilds indexes; headless runtime tests need the saved index.
- Compose functional pieces from `PieceBehavior` nodes and scene-authored `PieceSetting` resources. Follow the [piece authoring contract](docs/PIECE_AUTHORING.md) for configuration, ports, and reset.
- Route game requests through `CommunityService`. Provider routes and authentication translation belong in the game adapter. Keep `addons/supabase_client/` independent of game schemas and Steam so it remains usable in other Godot projects. `SteamClient` owns local integration; only server ticket verification establishes online identity.

Prefer local, traceable behavior and existing owners. Use typed GDScript where practical, signals, Resources, and InputMap actions. Check inherited names before declaring members, and fix warnings in touched scripts without suppressing them.

## Preserve editing and save contracts

Preview and commit must use the same validation. Connector snapping follows the visible cursor target and aligns orientation and elevation; the grid plane is the fallback. Keep direct dragging cancellable, group transforms rigid, moving pieces excluded from snap targets, and group edits atomic in history.

Enforce puzzle permissions in operations, including shortcuts, settings, wiring, duplication, history, and group edits. Hiding a control is insufficient. Preserve save/progress compatibility and stable content identities; format changes need explicit migrations. Puzzle files resolve registered assets, never arbitrary scenes or scripts.

Ordinary marble travel uses rigid-body physics. Intentional capture, such as an elevator bucket, may control transport but must restore physics and collision on release/reset. Test transitions with multiple marbles when affected. Floating tracks and optional supports are existing design choices; do not add mandatory support rules without discussion.

## Content and presentation

Author puzzles in the shared visual editor. Establish the engineering problem, choices, constraints, and observed mechanics before building content. Test as Player with real rules, keep the solution separate from the starting layout, and preserve current successful-test proof for publication. Objectives judge outcomes, not similarity to a reference layout. Follow [Puzzle authoring](docs/PUZZLE_AUTHORING.md); do not change global physics to rescue unverified content.

Preserve the ten optional Introduction puzzles, their IDs, progress, and solutions. Introduction and Sandbox must not gate the main campaign. Retries remain unlimited and resetting a run retains the build. Human playtesting is still needed to judge puzzle quality.

Build static UI in editable `.tscn` scenes using native Controls, Containers, anchors, and size flags. Shared styling belongs in `resources/sandbox_theme.tres`. Let Containers own ordinary layout; remove obsolete manual positioning in the interface being changed. World-anchored handles use 3D projection. Follow [UI design](docs/UI_DESIGN.md), preserve the logo and animated 3D menu showcase, and keep player copy short and natural.

## Verify and deliver

Use installed GUT and `tests/test_*.gd` through its panel or the [README command](README.md#development). Pure tests extend `GutTest`; persistence tests extend `tests/support/game_test.gd`. Use GUT lifecycle cleanup, isolate saves, and restore globals/input bindings. Keep the default suite focused on owners and contracts; do not add full-application navigation, screenshots, campaign playthroughs, or live-service checks unless requested. Do not create alternate runners, force compiler warnings, or publish bundled fixtures as a test side effect.

Run parsing/resource checks and focused tests proportionate to the change. Exercise interactive editing, physics, reset, history, save/load, and context transitions when affected; parsing alone cannot establish gameplay correctness. Review UI primarily at 1920×1080, adding sizes when layout behavior changes.

Update the guide that owns the changed behavior or setup. Keep README human-facing and architecture explanations out of this file. Do not edit third-party documentation or licenses. Report what changed, what passed, and what remains unverified, including unavailable visual or live-service checks.
