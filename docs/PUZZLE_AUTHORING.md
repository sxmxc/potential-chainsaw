# Visual puzzle authoring

Run `scenes/main.tscn`. Press **Ctrl+Shift+P** to enter the developer editor; the player menu exposes Campaign and Sandbox. The editor uses the same piece library, connectors, snapping, selection, dragging, elevation, duplication and undo/redo as Sandbox.

## Create a puzzle

1. Use the **folder icon beside Save** to open an existing draft/published puzzle. Open **Authoring tools** to create a new draft. Opening the library saves pending construction changes in the current draft first; if that save fails, the library stays closed.
2. Construct the starting layout. Place at least one marble release and the collector or mechanism that will be the objective. A release's inspector sets quantity, spacing, delay and initial speed.
3. In **Settings**, set name, description, chapter ID/display name, chapter order, optional/introduction classification, chapter unlock requirements, level order, difficulty, hints, prerequisites and time limit. Reuse a known chapter ID to populate its metadata, or enter a new ID to create a future chapter. Capture the intended camera. Optional time/piece award targets do not change the mandatory objective.
4. Select an existing piece in the world. In **Permissions**, choose Fixed, Move, Rotate, Configure or Full, or set individual capabilities. Apply the permissions to the selection. Configurable pieces may be restricted to one setting with an optional numeric range; clearing the restriction allows the other configuration fields.
5. In **Inventory**, choose catalog pieces and quantities. Zero removes a type. Players receive only this stock; fixed starting pieces do not spend it. Numeric setting limits can also restrict all inventory instances of a type, including elevator height.
6. In **Boundaries**, draw the build region by clicking two corners on the current construction plane; set its lower/upper elevations. Draw forbidden regions similarly. Select a zone to redraw or remove it. Escape cancels a pending drawing operation. The wire cages show the resulting regions.
7. In **Objectives**, select a collector for delivery or an event-producing mechanism for activation. Delivery can require a quantity and a specific marble source. **All marbles** fills the count from configured releases. Add multiple requirements when needed; all must succeed.
8. In **Links**, choose a source piece and event, a target piece and a supported action, then add the link. A sensor's Entered event can Open a gate and Fire a launcher through two links. The selected mechanism's ordinary inspector also provides link controls in Sandbox and allowed player configurations.
9. **Save Draft**. Drafts remain separate from the playable published list.

Permission checks apply to complete group edits, duplicates, removal, settings, links and history. A player cannot use height configuration to grow an elevator beyond its limits. Deleting a target removes its dangling links; duplication remaps relationships within the duplicated assembly.

## Test, validate and publish

1. Choose **Test as Player**. The actual campaign inventory, permissions, boundaries and objectives apply immediately.
2. Solve using normal construction tools. **Test Track** runs the actual physical simulation. Pause/continue and reset behave as in Sandbox; resetting the simulation keeps the player's construction.
3. After success, choose **Save solution** in the completion dialog. This records the tested construction separately from the starting layout. It does not rewrite the draft's authored baseline.
4. **Return to Editor** restores the original starting layout and authoring permissions. The developer-only **Load reference** action can restore a stored solution during a test, but the solution must still pass the current rules and physics. Campaign players do not receive that action.
5. Open **Authoring tools → Publish**. Use **Validate** to inspect definition/link/rule errors, then **Publish**. Untested drafts and stale solution fingerprints are rejected. If you change puzzle content after a successful test, test and save a new solution before publishing again.
6. Open Campaign's level selection, play the published puzzle and complete it. Completion, best time, fewest added pieces and optional earned awards persist across launches. Prerequisites and campaign order control unlocking.

Open a published puzzle to revise it. Its stable ID remains; publication increments the revision when content changes. The old working published copy remains playable while the revised draft is being tested.

Construction and mechanism edits support undo/redo. Authoring metadata uses explicit draft saves and has no separate undo history. The permission form currently supports one restricted configuration key per starting piece; inventory limits can cover several keys. Tune difficulty and optional awards through playtesting after the physical checks pass.

## Saves and shipping content

Chapter 1 prototype drafts are bundled under `resources/puzzle_drafts/` and appear only in the editor library. See [the blind playtest guide](CHAPTER1_PLAYTEST.md). Local drafts with the same ID override bundled copies.

### Environment objects

Use **Scenery** in the left construction toolbox for kit decorations, Wall, Floor, Column and Factory machine. All objects share one searchable catalog and placement previews. Walls and columns align visible solid faces and edges; R keeps quarter-turn rotation and Tab cycles nearby alignments. Aim at a column's top to stack another column without changing the active elevation. Free placement uses the construction grid. Click and drag, Shift-click or box-select, rotate, move, duplicate and delete using the normal construction controls. Mixed groups preserve their relative transforms and elevations. Escape cancels a pending edit. The contextual inspector provides move, rotate, duplicate, delete and elevation controls for scenery.

Environment and track edits share one undo/redo history, including atomic group operations. Columns can intersect walls to form corner posts; their registered definition permits this joint and snapping can centre the column on it. Other scenery and track overlaps remain rejected before committing. Selecting an object does not invalidate its proof. **Save draft** preserves both collections; reopening reconstructs the same objects and native collision. During Test as Player and Campaign, scenery is fixed, excluded from inventory and unavailable to player selection or shortcuts.

Reusable scenes under `scenes/environments/` own each model and its companion collision. Their saved `PieceDefinition` resources are entries in YARD's shared piece registry; authoring scenery is not a separate catalog. Puzzle version 2 adds `environment_instances`: stable `uid`, catalog `asset`, three-component `position`, and quarter-turn `rotation` (0–3). Instance scale and arbitrary node properties are not supported. Catalog models are curated from the imported Building and Factory kits, with base-centred pivots and matching static box solids. New puzzles need no separately authored environment scene.

Version 1 `environment` scene references are selectable composites in the editor, including Service block. Click any of their solids to select the complete scene; normal movement, rotation, duplication, deletion and history apply. Internal models and collision remain authored in the reusable scene. An unchanged scene reference keeps its existing fingerprint. Moving it saves an optional `environment_placement`; duplicates use scene-reference records in `environment_instances`. During player tests and Campaign these scenes remain fixed. The Environment page’s reusable scene chooser also participates in shared construction history.

Adding, moving, rotating or removing scenery changes the validation fingerprint. Scene and imported-resource dependency contents also participate, so editing a collision scene invalidates old proof even when its filename stays the same. A successful player test must still match the environment loaded at test entry. Test again and save the solution before publishing.

New publication embeds the effective environment's native mesh, texture and collision resources in a revision-specific snapshot beside the published JSON. Campaign uses that frozen snapshot; editor revisions and Test as Player use current reusable scenes. Previously published legacy records without a snapshot retain their original scene references until republished. Exported campaign ZIPs include snapshots, and the importer stages them under `resources/campaign/environments/`.

Godot's ordinary user data directory contains `puzzles/drafts`, `puzzles/published`, `campaign_progress.json`, and `campaign_state.json`. Completion records retain stable puzzle IDs; campaign state records the introduction choice and resume location. Local publication affects this installation. It does not automatically modify bundled project resources.

In **Publish**, export a campaign ZIP through the native file dialog. To include that content in a distributable game:

```powershell
python tools/import_campaign.py path/to/campaign.zip
godot --headless --path . --script addons/gut/gut_cmdln.gd -gselect=campaign -gexit
```

The bundle includes chapter metadata; import stages published JSON into `resources/campaign/`, matching existing IDs and filenames, and merges `resources/campaign_chapters.json`. Test the staged campaign in the target engine before export. In Godot's export preset, select all resources and add **`resources/campaign/*.json, resources/campaign_chapters.json`** to the non-resource inclusion filter. JSON is essential campaign data; user-directory saves are not shipped. Keep imported model assets and the native scene/resource dependencies in the export. Then export through Godot with the matching platform templates installed.

GUT campaign tests exercise the reference solution and incomplete starting layout for each preserved Introduction puzzle. Fixtures use isolated save directories and remove them during teardown. Tests never rewrite validation records or publish levels. Refresh authored solutions and validation through the visual Puzzle Editor after engine or physics changes.
