# Visual puzzle authoring

Run `scenes/main.tscn`. Press **Ctrl+Shift+P** to enter the developer editor; the player menu exposes Campaign and Sandbox. The editor uses the same piece library, connectors, snapping, selection, dragging, elevation, duplication and undo/redo as Sandbox.

## Create a puzzle

1. Open **Authoring tools**. Create a new draft or open an existing draft/published puzzle.
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
3. After success, choose **Preserve validated solution** or **Preserve solution**. This records the tested construction separately from the starting layout. It does not rewrite the draft's authored baseline.
4. **Return to Editor** restores the original starting layout and authoring permissions. The developer-only **Load reference** action can restore a stored solution during a test, but the solution must still pass the current rules and physics. Campaign players do not receive that action.
5. Use **Validate** to inspect definition/link/rule errors, then **Publish**. Untested drafts and stale solution fingerprints are rejected. If you change puzzle content after a successful test, test and preserve a new solution before publishing again.
6. Open Campaign's level selection, play the published puzzle and complete it. Completion, best time, fewest added pieces and optional earned awards persist across launches. Prerequisites and campaign order control unlocking.

Open a published puzzle to revise it. Its stable ID remains; publication increments the revision when content changes. The old working published copy remains playable while the revised draft is being tested.

Construction and mechanism edits support undo/redo. Authoring metadata uses explicit draft saves and has no separate undo history. The permission form currently supports one restricted configuration key per starting piece; inventory limits can cover several keys. Tune difficulty and optional awards through playtesting after the physical checks pass.

## Saves and shipping content

Godot's ordinary user data directory contains `puzzles/drafts`, `puzzles/published`, `campaign_progress.json`, and `campaign_state.json`. Completion records retain stable puzzle IDs; campaign state records the introduction choice and resume location. Local publication affects this installation. It does not automatically modify bundled project resources.

In **Publish**, export a campaign ZIP through the native file dialog. To include that content in a distributable game:

```powershell
python tools/import_campaign.py path/to/campaign.zip
./tools/verify_campaign.ps1
```

The bundle includes chapter metadata; import stages published JSON into `resources/campaign/`, matching existing IDs and filenames, and merges `resources/campaign_chapters.json`. Test the staged campaign in the target engine before export. In Godot's export preset, select all resources and add **`resources/campaign/*.json, resources/campaign_chapters.json`** to the non-resource inclusion filter. JSON is essential campaign data; user-directory saves are not shipped. Keep imported model assets and the native scene/resource dependencies in the export. Then export through Godot with the matching platform templates installed.

Verification uses a uniquely named OS temporary directory for application save files and logs, removes it on exit, and leaves `APPDATA` unchanged. `-VisualReview` opens the chapter regression scene for Hera inspection with the same isolated saves and a three-minute automatic exit. It does not copy the project, Godot, or asset caches.

For intentional fixture refresh after engine/physics changes, `./tools/verify_campaign.ps1 -PublishVerified` replaces bundled validation records only after all campaign cases pass. It is a developer verification command, not the authoring workflow. Future puzzle layouts and rules can be created entirely through the visual editor.
