# Puzzle authoring and distribution

## Create a puzzle

Run `scenes/main.tscn` and choose **Puzzle Editor** for community authoring. In a project run, **Ctrl+Shift+P** enters official authoring. The project-only **Publish to** selector in the authoring Setup page changes destination without recreating the draft. Exported builds offer community publication only.

The editor uses the shared construction workspace, toolbox, snapping, selection, configuration, and undo/redo. Open **Authoring tools** for definition-wide settings; use the selection inspector for object settings and player permissions.

1. Build the incomplete starting machine. Place a marble release and targets for its objectives. Releases configure quantity, spacing, delay, initial speed, and an optional display label.
2. In **Setup**, enter the title, objective description, creator, difficulty, hints, and time limit. Capture the intended camera. Optional time/piece awards do not affect the mandatory outcome. Official authoring also exposes chapter metadata, level order, and prerequisites.
3. Select starting pieces and set **Player permissions** in the inspector. Permissions cover moving, rotation, removal, and configuration. You can restrict a configuration key and its numeric range. The form currently exposes one restricted key per starting piece; inventory-wide limits can cover several keys. Authoring-only environment pieces are fixed during play; ordinary decorative props follow normal piece permissions.
4. In **Inventory**, choose catalog types and quantities. Only added pieces consume inventory; starting pieces do not. Zero removes a type. Configuration limits can restrict added instances, including adjustable geometry.
5. In **Boundaries**, draw the build region with two corners and lower/upper elevations. Draw forbidden regions similarly; select a region to redraw/remove it. Escape cancels drawing.
6. In **Objectives**, choose a collector for delivery or a mechanism output for activation. Delivery supports a quantity and optional source release; **All marbles** fills the quantity from configured releases. All objectives must succeed. Activation checks whether the event occurred, not how many times it occurred.
7. Use the shared **Connect** tool for mechanism wiring; see [Piece authoring](PIECE_AUTHORING.md#wire-a-machine).
8. **Save Draft**. The folder button beside Save opens the draft/published library; **New puzzle** is in Authoring tools. Opening another context saves dirty authoring work first and stays put if saving fails.

Construction, settings, permissions, and wiring follow shared editing rules. Metadata is saved explicitly and has no separate undo history. Describe what the player must achieve without giving away the construction. A working machine still needs human playtesting to assess whether its choices make an interesting puzzle.

## Test and publish

1. Choose **Test as Player**. ConstructionSession captures a separate authored baseline and loads the actual inventory, permissions, scenery, boundaries, and objectives.
2. Solve with normal tools, then **Test Track** in the real simulation. Reset retains your player construction; **Restart puzzle** reloads its starting layout.
3. After success, choose **Save solution**. This stores the construction from that successful run separately from the starting layout, together with a validation fingerprint, engine version, elapsed seconds, and test timestamp.
4. **Return to Editor** restores the baseline. The test-only **Load reference** action can load a saved solution, but it still must obey current rules and complete the simulation. Ordinary players cannot use it.
5. In **Publish**, choose **Validate**, then **Publish locally** or **Add to Campaign**. A current successful test and preserved solution are required. Content edits invalidate proof; test and save a new solution before publishing again.

Opening a published puzzle for editing retains its ID. Gameplay content changes advance its revision and leave the previous published copy playable while the new draft is tested. Merely changing the publication destination does not invalidate proof. Selecting objects does not change content.

For portable sharing, publish locally and choose **Export puzzle**. Another player uses **Community puzzles → Import puzzle**. **Publish online** first preserves the same local published revision, then opens the online browser for submission. It returns a `<UUID>@<revision>` share code, accepted by **Open shared puzzle**. **My puzzles** lists owned online publications and supports unpublishing. Installed copies survive unpublishing. See [Community service](COMMUNITY_SERVICE.md) for authentication and backend setup; local publication/import/export requires neither account nor network.

## Scenery

Registered Building Kit and Factory Kit pieces use the same toolbox and editing tools as track. They are decorative/fixed geometry, not additional working mechanisms. During player tests and puzzle play they are outside inventory and cannot be selected or edited.

Surface snapping uses the collision hit and measured occupied volumes. Flat faces and edges offer attachments; Tab cycles alternatives and R retains deliberate rotation. Track connectors still align full transforms across elevations. Without an attachment, use the grid and active height. Blue previews indicate grid placement, green attachment, and red rejection.

Face contact is permitted; solid penetration is rejected. Door/window volumes preserve openings. Columns have a registered wall-joint exception. Sloping/curved surfaces do not automatically provide rectangular attachments. Machinery placement bounds approximate its shape while physical collision uses mesh geometry; the decorative control display is pickable without blocking marbles.

Scenery changes participate in the validation fingerprint, including registered resource dependencies. Geometry changes require a fresh player test before republishing. Runtime scenes are resolved from the current registry; publication does not freeze a scene snapshot.

## Formats and storage

`TrackSerializer` reads/writes personal track format **1**: `version`, `id`, `name`, `modified`, and `pieces`. A construction record contains `uid`, catalog `piece`, `position: [x,y,z]`, quarter-turn `rotation`, and `config`. Mechanism `config.links` contains `{event, target, action}`. Personal-track decoding skips unknown/authoring-only pieces with warnings and normalizes configuration; puzzle imports instead reject missing catalog dependencies.

`PuzzleStore.create()` creates puzzle format **2**; readers accept versions **1 and 2**. Version 2 provides catalog scenery through `environment_instances`. The primary fields are:

| Data | Representation |
| --- | --- |
| Identity/presentation | `id`, `revision`, `name`, `description`, `creator`, `difficulty`, `status`, `hints` |
| Starting layout/reference | `pieces`, `solution`: construction records; the solution is separate from the start |
| Player rules | `permissions` by starting UID; `inventory` and `configuration_limits` by piece ID |
| Geometry | `bounds: [min_x,min_z,max_x,max_z,min_y,max_y]`; each restricted zone is `[x,y,z,size_x,size_y,size_z]` |
| Scenery | `environment_instances`: `{uid, asset, position, rotation}` with registered authoring-only asset IDs |
| Outcomes | `objectives`, optional `time_limit`, optional `awards` |
| View/proof | `camera: {focus,yaw,pitch,distance}`, `validation`, `required_assets` |

Rotation is an integer 0–3 about Y. Arbitrary scene/script paths, per-instance scale, node properties, and the retired `environment`, `environment_placement`, and `environment_snapshot` fields are unsupported. Files with retired scenery fields fail with a rebuild message. Author through the visual editor rather than hand-editing JSON.

Paths below use Godot's resource/user roots:

| Path | Owner/content |
| --- | --- |
| `res://resources/campaign/` | Official puzzle JSON |
| `res://resources/campaign_manifest.json` | Official membership, paths, chapter IDs, order, prerequisites |
| `res://resources/campaign_chapters.json` | Chapter presentation/navigation metadata |
| `user://tracks/` | Personal track saves |
| `user://puzzles/drafts/` | Editable drafts, optionally with draft-only `campaign` registration |
| `user://puzzles/published/` | Local community publications |
| `user://puzzles/community/` | Installed JSON/online imports |
| `user://campaign_progress.json` | Official completion, best results, awards |
| `user://campaign_state.json` | Official route/resume and Introduction choice |
| `user://community_progress.json` | Separate community completion by stable puzzle ID |

PuzzleStore saves through the shared `SaveStorage` JSON writer, which checks a flushed temporary file before replacing the destination. Imports and online downloads both use `install_community`: size/type/asset/definition/solution-rule checks precede installation. Conflicting IDs in drafts, local publications, or imports fail without overwriting; identical reimports retain identity. Imported author proof records a prior run, not a trusted physics guarantee. Resource hashes are not compared across packaged builds; editing/republishing requires a new local test.

## Official campaign and progression

Only project runs with the editor feature and `project.godot` present can **Add to Campaign**. It validates the puzzle, writes published content, and updates the manifest and chapters, restoring previous bytes if a write fails. Exported debug/release builds cannot promote project resources. Existing registered paths and IDs are retained; conflicting/stale revisions are rejected.

Official membership comes from the manifest loader's provenance, never from a field in an imported puzzle. Portable publications omit campaign registration and `_source`. An imported puzzle with an official ID remains community content and uses independent completion records. Local publications do not override packaged campaign entries.

The manifest currently registers `campaign-01` through `campaign-10` in optional Introduction and four Chapter 1 puzzles. Introduction levels are independently available. Main chapters check their own prerequisites; a level with no explicit prerequisites uses the preceding level in its chapter. Introduction requirements are treated as satisfied for main-route unlocking, including legacy references. Awards never gate progress. Skip Introduction enters the main route without marking tutorial levels complete; completing Introduction reaches that route too.

Legacy embedded chapter/order/prerequisite fields are moved to draft registration on load, rebinding valid proof for this metadata-only conversion. Shared chapter metadata determines runtime navigation; the manifest can preserve a legacy chapter override for authoring. Existing completion records survive route initialization. Future campaign content requires separate authoring, simulation, and playtesting.

The Windows export preset includes campaign/example JSON, `resources/community_catalog.json`, and `addons/supabase_client/*.cfg`. Keep registry resources, imported models, and scene dependencies included. User-directory content is not shipped automatically. See [Architecture](ARCHITECTURE.md#verification) for isolated GUT checks; tests must not republish bundled content.
