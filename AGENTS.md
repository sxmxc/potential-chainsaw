# AGENTS.md — Marble Engineer

## Purpose

Marble Engineer is a Godot 4.x 3D marble-track construction and physics puzzle game using Kenney's Marble Kit. Players build modular tracks, test them with physics-driven marbles, and solve campaign puzzles by completing or modifying authored machines.

This file is a standing engineering and design contract for coding agents. **The repository is the source of truth.** Verify existing scenes, classes, APIs, asset geometry, and feature status before making assumptions. This document describes intended conventions; it does not claim every system is already implemented.

## Product boundaries

- **Sandbox:** unrestricted building, experimenting, testing, and saving constructions.
- **Campaign:** authored physics puzzles with inventories, fixed/editable pieces, objectives, and progression.
- **Puzzle Editor:** developer-facing visual authoring using the **same** construction and simulation systems; draft, test as player, validate, publish.
- **Introduction:** the original 10 tutorial-style puzzles are optional/skippable and must be preserved. The main campaign should not be a series of obvious assembly exercises.

Do not introduce separate construction or marble simulation engines for each mode. Apply mode-specific rules through data and permissions. Do not make the sandbox a required prerequisite for campaign play.

## Before changing anything

1. Read the relevant project documentation and inspect the affected scenes, Resources, scripts, and tests.
2. Identify the current code path and its callers. Check input mappings, signals, save formats, theme inheritance, and lifecycle interactions where relevant.
3. Verify the actual Godot version and available plugins before choosing APIs.
4. Inspect imported GLBs for dimensions, pivots, orientation, mesh hierarchy, and collision requirements; **never infer geometry from filenames alone**.
5. Describe the smallest coherent change and its regression risks. Prefer working within existing architecture over adding parallel managers or abstractions.
6. Preserve unrelated features and existing user content. Make a version-control checkpoint before substantial refactors when appropriate.

Do not silently expand scope. When behavior is ambiguous or involves a new game-design choice, state the assumption and seek a decision rather than inventing systems or content.

## Godot engineering standards

- Follow Godot-native conventions: typed GDScript where practical, focused scenes, reusable Resources, signals, InputMap actions, and explicit state ownership.
- Keep scene composition, data, presentation, and behavior separate. Avoid monolithic scripts, duplicate state machines, sprawling autoloads, and hardcoded node paths scattered across unrelated files.
- Use stable IDs for piece definitions and placed instances. Maintain backward compatibility for existing saved constructions, puzzle definitions, and progress; introduce migrations when formats change.
- Prefer a small, understandable implementation over general-purpose frameworks. New components must solve an existing need.
- Do not edit original imported assets destructively. Wrap assets in reusable scenes and add companion collision, connectors, or behavior there.
- Test both headless parsing/resource loading and real interactive/physics workflows when relevant. Compilation alone is not verification.

## Construction contract

- The construction engine is shared by all modes. The same transform, snapping, placement-validation, editing, history, and serialization behavior must apply wherever permissions allow.
- Connector-first snapping should align compatible pieces in full 3D (position, orientation, **and elevation**) without requiring the player to manually select the target's building level. Use visible, cursor-intended connectors; do not snap to arbitrary distant candidates.
- The grid and active height are useful fallbacks for free placement, not prerequisites for extending existing tracks.
- Direct manipulation is standard: click to select; drag to move; Shift-click and box selection; group move/rotate/duplicate/delete; connected-section selection where implemented. Routine edits should not require selecting a separate Move tool.
- A selected group moves as one rigid arrangement, retaining internal transforms and elevation differences; snapping targets exclude its own internal connectors. Group operations are single undoable actions.
- All transformations must be reversible or cancellable. Avoid sudden jumps to the ground plane or changes caused by incidental raycast hits.
- Respect mode permissions in the actual editing operations, including shortcuts, duplication, group editing, and undo/redo—not only in the UI.
- Floating tracks are allowed by default. Do not introduce structural integrity or mandatory supports without an explicit design decision.

## Physics and mechanisms

- Marble travel outside explicitly defined transport/capture mechanisms is driven by Godot rigid-body physics. Do not replace ordinary rolling with scripted track following.
- Use accurate-enough track collisions, stable transitions, physically understandable forces, and clean simulation start/reset behavior.
- Controlled attachment or kinematic transport is allowed for mechanisms such as the bucket elevator **only while the marble is intentionally captured**. Make transfer visible and believable; restore physics and collision state reliably on release/reset.
- Reuse existing mechanism contracts for activation, configuration, saving, and resets. Do not implement separate event systems for individual pieces.
- Fan families have distinct behavior: shrouded fans apply directional airflow; the exposed `fan-simple-*` models are physical rotating paddles. Confirm model geometry and existing behavior before editing them.
- The bucket elevator exists in the project; inspect and extend it rather than replacing it.
- Do not assume a mechanism, collision transition, force setting, or multi-marble interaction works just because it is logically plausible. Reproduce and test it.

## Puzzle and campaign design

- The existing 10 introductory levels are **optional Introduction content**. Do not delete, overwrite, or relabel their stable identifiers casually; preserve progress and known-good solutions.
- Design main-campaign puzzles around **observed game behavior**, not invented physics outcomes (for example, never assume a curve sheds or requires a particular speed without testing).
- Before authoring a level, record its actual engineering problem, available mechanics, starting conditions, player choices, constraints, and why those choices are meaningful.
- Construct and verify a working solution in the real simulation. Save that solution separately from the incomplete player-facing starting layout.
- Verify that difficulty comes from reasoning, not tedious positioning, opaque rules, frame-perfect timing, or unpredictable collision behavior.
- Do not fill a campaign quota with generic gaps, superficial variations, or mechanism-showcase exercises. A mechanically working level is not automatically a good puzzle.
- Validate outcomes through simulation objectives, **not** by comparing the player's construction to one prescribed layout. Legitimate alternate solutions are welcome.
- Keep player retries unlimited unless explicitly directed otherwise. Testing a puzzle must not erase the player's build.
- Puzzle Editor must use actual in-game construction and support draft → test as player → validation → publish, with isolated test copies. Do not require hand-editing JSON or GDScript to author levels.
- Publishing requires tested completion conditions and a known-good solution. Do not claim fun has been established without human playtesting.

## UI architecture

- Build UI in editable `.tscn` scenes using Godot `Control` and `Container` nodes, anchors, and size flags. Use a shared `.tres` `Theme`, theme type variations, and reusable widgets.
- GDScript should primarily implement behavior, data binding, state changes, and truly dynamic content. Do not build static screens as one-off code-generated controls or scatter colors, dimensions, and `StyleBox` instances through scripts.
- Local scene-specific layout values are valid. Do not force every margin or coordinate into the global Theme.
- Sandbox, Campaign, and Puzzle Editor should share presentation components but present **mode-appropriate** actions. Never show sandbox save/rename/new-track actions in a campaign pause menu.
- Preserve comfortable font sizes and touch targets. Fix oversized UI by changing **information architecture and contextual visibility**, not by globally shrinking everything.
- Keep the construction and marble simulation as the visual priority. Avoid full-width instruction banners, unnecessarily tall empty toolboxes, always-open inspector panels, and duplicated status text.
- Make the piece toolbox catalog-driven with recognizable thumbnails, clear selection states, scrolling for larger inventories, and sensible sizing for small ones.
- Verify UI by running the project and reviewing actual screens at 1280×720, 1600×900, and 1920×1080 when possible. Report honestly if visual inspection is unavailable.

## Player-facing writing

- Treat UI copy as authored game content, not filler. Write for a player, not a developer or marketing deck.
- Be short, natural, specific, and consistent. Prefer sentence case for ordinary UI text; reserve all caps for intentional display treatments.
- Avoid repeating a level title in its objective, describing obvious buttons, stacking slogans, or exposing internal state terminology.
- Introduction hints should appear contextually; normal campaign objectives state **what** to achieve, not the exact piece or sequence to use.
- Prefer `1 piece` / `2 pieces` over malformed counters; avoid unjustified decimal precision (`0.000 m`) and dense shortcut paragraphs.
- Examples of direction, not mandatory replacements:
  - `FIRST CONNECTION · BRIDGE THE MISSING TRACK AND DELIVER ONE MARBLE` → `Get the marble to the finish.` (the title is already elsewhere).
  - `CHOOSE STRAIGHT, POINT AT A GLOWING CONNECTOR, AND CLICK` → contextual `Select a straight track`, then `Click a connector to attach` only when needed.
  - `1 PIECES · HOVER FOR DETAILS` → `1 piece` or omit.
  - `PUZZLES ARE BEING PREPARED. NO PUBLISHED PUZZLES YET` → `No levels available yet.`
- Review every new screen for duplicated information, awkward terminology, and instructions that give away puzzle solutions.

## Main menu and visual identity

- Preserve the current Marble Engineer identity and the animated, real-3D marble-track showcase. Do not replace it with a static background simply to simplify UI implementation.
- Keep menu controls composed around the showcase instead of obscuring it. Use real shared piece scenes and believable simulation where practical.
- Favor deliberate framing, lighting, and motion over generic decoration. The colorful Kenney track should remain prominent.

## Verification and delivery

For each substantive task:

1. Identify files and systems impacted and the user-visible behavior being changed.
2. Implement the smallest coherent change, preserving scene/resource conventions.
3. Run available tests and headless project validation; test interactive, visual, and physics behavior where the change requires them.
4. Check regressions in Sandbox, Campaign, and Puzzle Editor as relevant; check save/load, undo/redo, permissions, and reset behavior.
5. Report what changed, what was **actually tested**, and what remains unverified. Never claim a screenshot was inspected or physics was simulated when it was not.

### Do not

- Invent mechanics, level solutions, asset geometry, or reliability claims.
- Change global marble physics to rescue an unverified level without analyzing consequences.
- Recreate systems that already exist or rewrite the project to accommodate a small feature.
- Deliver untested puzzle batches to meet an arbitrary level count.
- Call generic-looking, oversized, text-heavy panels “polished” without examining user workflows.
- Hide missing functionality behind visual polish or claim completion based only on successful parsing.

**Core standard:** players should spend their time designing and testing marble machines—not fighting the editor. Agents should spend their time validating that experience—not generating plausible-looking code or content.

## Test framework

Use the installed GUT plugin and `tests/test_*.gd` suites for automated tests. Run through the GUT panel or its standard CLI. Do not add custom verification runners, force compiler warnings, create one-off test scripts, or publish/modify campaign fixtures as a test side effect. Preserve player saves with isolated GUT fixtures.
