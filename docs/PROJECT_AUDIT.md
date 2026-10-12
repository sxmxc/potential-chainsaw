# Project audit and implementation

The starting project already had a working 165-piece sandbox, measured connectors, a shared BuildManager, immutable construction snapshots for undo/redo, native Godot UI scenes and a shared Theme. The bucket elevator already transported real marbles; six adjustable support families already updated bounds, collision and connectors. Those systems were retained.

Before changes, the source was preserved in `.local-user/pre-campaign-source.zip`. There was no Git repository in the workspace. The archive records the original scripts, scenes, resources, tests, project configuration and existing documentation. A Git baseline was subsequently reconstructed from that untouched archive, together with the unchanged assets and editor plugin; the final implementation is recorded in a separate commit.

## Findings and decisions

| Finding | Implemented behavior |
| --- | --- |
| All fan models used the same rotating collision behavior | Four shrouded fans use finite directed force regions, measured local axes and visible direction markers. The two exposed `fan-simple` models use physical moving blade boxes with gaps. |
| Exposed rotor collider cleanup could remove its AnimatableBody3D | Separate blade shapes now remain attached and follow construction transforms even while stopped. |
| Simulation assumed one marble and any collector | One shared SimulationManager schedules multiple releases and tracks actual collector, source and event outcomes. |
| Configuration application was specific to elevator/support | Shared configuration normalization now covers mechanisms and marble releases. |
| No puzzle data, rules, progression or authoring layer | PuzzleStore, PuzzleRules, PuzzleObjectives and PuzzleSession extend the same construction and physics systems. |
| No event/action relationship model | Stable piece IDs and serialized event/action links support sensors, gates, launchers, fans, paddles and elevator events. |
| Fixed UI minimum sizes overflowed when puzzle controls were added | Toolbars wrap; inventory and inspector scroll within available space. |

## Shared architecture

`scripts/construction/build_manager.gd` remains the only construction controller. Rules inspect proposed complete snapshots before edits commit. Mixed selections are atomic: a forbidden member prevents the whole move, rotation or deletion. Inventory derives from the current layout, so duplication consumes stock and deletion/undo refunds it. Configured elevator/support dimensions participate in bounds checks.

`scripts/simulation/simulation_manager.gd` remains the only physical simulation. Mechanisms use real areas, rigid bodies, collision and impulses. Collectors record deliveries; objectives never compare the layout to a reference answer. Pause suspends releases and mechanism motion. Reset restores runtime state without modifying the construction.

`scripts/campaign/puzzle_session.gd` changes modes on the existing sandbox scene. Sandbox has no puzzle rules. Campaign and Test as Player share PuzzleRules. Editor keeps its authored baseline separate from player solutions. Published revisions retain their ID, so progress is stable across revisions.

`scripts/campaign/puzzle_store.gd` owns versioned JSON persistence and validation fingerprints. Player progress, local drafts and local published puzzles use separate user paths. The bundled ten levels reside under `resources/campaign/`. Publication requires a successful physical test whose fingerprint matches the current authored definition.

The native `.tscn` UI windows and panels use `resources/sandbox_theme.tres`. Authoring lists use scene objects and supported event/action names rather than requiring authors to type IDs. Existing serialized track saves remain compatible; mechanism links live inside piece configuration.
