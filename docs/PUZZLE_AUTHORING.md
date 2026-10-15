# Puzzle authoring and distribution

A puzzle is an incomplete machine plus rules for finishing it. Its starting layout tells the player what is already there; inventory and permissions define what they may change; objectives decide whether the result works. The reference solution is kept separately and never used to judge similarity to the player's design.

Use the shared visual editor to author puzzles. Before building, identify the engineering problem, the choices the player should make, and the mechanics you have observed in simulation. A machine that runs successfully may still need human playtesting to become a good puzzle.

## Create a puzzle

Run the game and choose **Puzzle Editor** for community authoring. In a project run, **Ctrl+Shift+P** opens official authoring. The project-only **Publish to** selector changes the destination without recreating the draft. Exported builds offer community publication only.

Build the incomplete starting machine using the normal toolbox, snapping, selection, settings, and Connect tools. Place at least one marble release and the pieces that objectives will target. Use the selection inspector for individual settings and player permissions; open **Authoring tools** for the whole puzzle.

### Define the challenge

In **Setup**, enter a name, an outcome-focused description, creator, difficulty, and the available time. Author hints under **Objectives → Player hints**. Capture a camera view that makes the initial problem legible. Time and piece-budget awards are optional goals; they do not change mandatory completion. Official authoring also exposes chapter metadata, level order, and prerequisites.

Starting pieces are fixed unless you grant permissions. Select them and expand **Player permissions** in the inspector to allow moving, rotating, configuring, removing, or duplicating. You can limit configuration to a selected key and a numeric range. The form edits one restricted key per starting piece; the data format can retain existing restrictions on several keys.

For example, a fixed gate can still be configurable if the challenge is about timing rather than moving the gate. Wiring is configuration too, so take permitted keys into account when the player should be able to connect signals. Verify that freedom in a player test rather than infer it from which controls are visible.

In **Inventory**, clicking catalog thumbnails in the shared Pieces browser adds piece types to the player's toolbox. Edit their quantities inline; zero removes a type. Starting pieces do not consume inventory, but new instances, including duplicates, do. The selected inventory type can have numeric configuration restrictions, including limits on adjustable geometry. Type-wide `configuration_limits` also apply to starting instances of that type.

Numeric range enforcement has a gap for omitted settings: it checks values present in saved configuration, while a behavior can receive its default at runtime. A default outside the authored range can therefore pass unchecked. Test newly placed pieces as well as edited settings, and do not rely on a range excluding an omitted default.

### Set the space and outcomes

In **Boundaries**, draw the build region with two corners, then set its lower and upper elevations. Add restricted regions in the same way. Select a region in the world or list to redraw or remove it; drag to move it, and use Escape to cancel a drag or drawing. **Exact dimensions** exposes its X/Z origin, width, and depth. Opening a dialog cancels an unfinished region gesture. Selection by itself does not dirty the draft.

Boundaries govern new and transformed construction. Unchanged starting pieces may extend outside the player's build region, which lets the authored machine frame the problem without making all of it editable space. Changing geometry through a setting is still an edit that can violate the region.

In **Objectives**, select a collector or mechanism in the viewport or target menu. Choose an existing goal to edit it, or create a new one. Delivery requires a quantity of distinct marbles at a collector, optionally from one release. **Require all released marbles** fills the quantity from the configured releases. Activation requires a named output to have occurred; it does not count repeated activations. Every objective must succeed, and an individual deadline can constrain it further.

Use **Connect** for relationships between mechanisms. [Wire a machine](PIECE_AUTHORING.md#wire-a-machine) explains port selection and compatibility. Ordinary marble travel remains physical: an apparently aligned route or an activation signal does not guarantee delivery.

### Author world guidance

In **Objectives → Player hints**, choose **New hint**, pick a piece (or **Use selected piece**), and write what the player should do. **Next hint when** chooses how to advance. The default is a pointer shown while building, with a **Next** button for the player. Choose **Add hint** to append it. Select a numbered hint to edit it, then **Save hint**; **Remove** deletes the selected hint. New hints start with fresh defaults and use the currently selected piece when available.

**Advanced** holds marker style, track end, and when to show the hint. Connection hints reveal these options so you can choose a numbered track end. **Whole piece** points at the object's top; **World point** exposes X/Y/Z. Direction follows the track end's outward axis or the piece's local forward axis. Hints can advance on selection, track connection, starting a run, objective activity, or **Next**. Only manually advanced hints show Next (Done on the last hint); action-driven hints wait for the chosen action. Objective activity means a recorded delivery or activation, rather than completion of the entire objective. These options use the existing declarative guidance format; no scripts or expressions are supported.

**Preview** shows both the marker and instruction for five seconds in the editor. **Test as player** uses the same sequence and permissions as normal play. All ten existing Introduction puzzles contain short examples and show them automatically: the first three demonstrate track connections; later puzzles point to settings and wiring, then the destination during the run. Open **Campaign puzzles**, choose an Introduction puzzle, then inspect **Objectives → Player hints**. Community and ordinary campaign puzzles show hints after **Hint**; **Goal** locates destinations and cycles through multiple objectives. Reset starts the sequence against the retained construction, so already-connected hints may immediately advance. Hint metadata edits invalidate publication proof like other authoring changes; they do not have separate undo history.

Targets follow committed piece moves, rotation, configuration, and undo/redo. Removing a target leaves a visible validation error in the editor; select a replacement or remove the step before testing/publishing. Runtime presentation safely hides an unresolved target. Guidance references starting construction instances, not arbitrary nodes or future inventory instances.

Player hints have one runtime owner, `WorldGuidance`, and one authoring form. Older puzzles with only a `hints` text list use the same Hint and Next controls without world markers or a save-format rewrite. An authored `guidance` sequence takes precedence over that older text. Puzzle descriptions supply objective copy directly; there is no separate Introduction copy table or HUD tutorial progression.

Open `scenes/development/guidance_workshop.tscn` and run that scene for a separate editable sample. It loads `resources/development/guidance_workshop.json` into the normal Puzzle Editor. Its steps select a real track, point at its exposed connector, advance on connection, and guide a run toward the collector. Choose **Test as player**, then **Hint**. The layout also demonstrates fixed platforms, stairs, a physical partition and machine, and selection-only robot/traffic props; inventory includes ordinary environmental tools. It is a development draft with no claimed successful-test proof or preserved solution. It does not change campaign puzzles or progression.

### Save the draft

Choose **Save Draft** while developing. The folder button beside Save opens the puzzle library, and **New puzzle** is in Authoring tools. In project runs, the library opens as **Campaign puzzles**, with a selector for **Community puzzles**; exported builds show the community library only.

Opening a packaged puzzle retains its ID and registration and permits authoring regardless of player progression. Edits stay in a draft until a tested revision is added to the campaign. Navigation saves dirty authoring work first and stays put if that save fails. Save explicitly after important changes; metadata has no separate undo history, while construction, piece settings, and wiring use the shared edit history.

## Test and publish

Publication depends on three separate things: the intended starting machine, a solution that obeys the player's rules, and a successful run of that solution for the current draft.

1. Choose **Test as Player**. The session captures the authored baseline and enters a separate copy with real inventory, permissions, scenery, boundaries, and objectives.
2. Solve with the normal tools and run **Test Track**. Reset retains the player construction; **Restart puzzle** reloads the starting layout. Retries are unlimited.
3. After success, choose **Save solution**. This stores the successful construction separately from the starting layout, together with its fingerprint, engine version, elapsed time, and test timestamp.
4. **Return to Editor** restores the baseline. A test-only **Load reference** action can load the saved solution, but it must still obey current rules and complete a run. Ordinary players cannot use it.
5. In **Publish**, review readiness and use **Validate** to inspect problems. When ready, the primary action becomes **Publish locally** or **Add to Campaign**.

Edits covered by the validation fingerprint require another successful test and saved solution. This includes presentation fields such as the name and description, not just track changes. Selecting objects does not change content. Changing the publication destination or campaign registration alone does not invalidate proof.

Reopening a published puzzle preserves its ID. Changing fingerprinted content advances the revision and returns it to draft status; the prior published copy remains playable while you work. Keep this identity rather than create a replacement puzzle merely to revise it.

## Share a community puzzle

Publish locally, then choose **Export puzzle** to write a portable JSON file. Another player installs it through **Community puzzles → Import puzzle**. This workflow needs no account or network connection.

**Publish online** first retains a local published copy, then opens the online browser for submission. The service returns a `<UUID>@<revision>` share code for **Open shared puzzle**. **My puzzles** lists the current owner's publications and supports unpublishing. An installed copy remains playable after its online publication is removed. Authentication and server setup live in [Community service](COMMUNITY_SERVICE.md).

Imports and downloads use the same `PuzzleStore.install_community()` path. It validates size, types, registered assets, the definition, and solution rules before writing. A conflicting ID in drafts, local publications, or imports is rejected rather than renamed or overwritten; an identical reimport keeps its identity. Imported proof records the author's prior run, rather than independently proving physics on the receiving machine.

## Scenery and physical space

Registered Building Kit and Factory Kit scenery is authored with the same tools as track. Definitions marked `authoring_only` become fixed environment geometry in play and player tests, outside selection and inventory. Ordinary decorative props, such as trees, remain normal construction pieces and follow their permissions. Decorative machinery does not become a working mechanism merely because its model resembles one.

Surface snapping uses collision hits and measured occupied volumes. Flat faces and edges offer attachments; Tab cycles alternatives and R preserves deliberate rotation. Track connectors align the full transform across elevations. Without an attachment, the grid and active building height supply placement. Blue previews indicate grid placement, green attachment, and red rejection.

Face contact is permitted and solid penetration rejected. Door/window volumes preserve openings, and columns have a registered wall-joint exception. Curved or sloping surfaces do not automatically offer rectangular attachments. Decorative machinery can have approximate placement bounds while using mesh collision physically; the control display is selectable without blocking marble travel.

Authoring-only scenery dependencies contribute to the validation fingerprint. Their geometry changes require a new local test before republishing. Puzzle files resolve current registered assets; publication does not freeze scene snapshots.

## Formats and storage

Personal tracks use format **1**, owned by `TrackSerializer`: `version`, `id`, `name`, `modified`, and `pieces`. A construction record identifies the asset separately from the placed instance:

```json
{
  "uid": "sensor-instance",
  "piece": "sensor",
  "position": [0, 0, 0],
  "rotation": 0,
  "config": {"detect_exit": true}
}
```

Rotation is an integer 0–3 in quarter turns about Y. Mechanism links live under `config.links` as `{event, target, action}`, with a target instance UID. Personal-track decoding skips unknown or authoring-only pieces with warnings and normalizes settings; puzzle imports reject missing catalog dependencies.

`PuzzleStore.create()` produces puzzle format **2**, and readers accept versions **1, 2, and 3**. Version 2 adds catalog scenery through `environment_instances`. Saving authored guidance upgrades a draft to version 3; existing files need no rewrite, and capturing scenery never downgrades version 3. Version 3 adds `guidance`: at most 32 steps, each containing `kind`, a starting-piece UID in `target` (or empty for a point), `connector` (-1 for the whole piece), optional `position: [x,y,z]`, optional `text` (200 characters), `appear`, and `complete`. Client and server validate these fields and target dependencies; publication proof includes them. The principal fields are:

| Area | Fields and representation |
| --- | --- |
| Identity and presentation | `id`, `revision`, `name`, `description`, `creator`, `difficulty`, `status`, `hints` |
| Construction | `pieces` for the start; `solution` for the separate solved construction |
| Player rules | `permissions` keyed by starting UID; `inventory` and `configuration_limits` keyed by piece ID |
| Build space | `bounds: [min_x,min_z,max_x,max_z,min_y,max_y]`; restricted zones are `[x,y,z,size_x,size_y,size_z]` |
| Fixed scenery | `environment_instances`: `{uid, asset, position, rotation}`; asset omits the registry's `environment:` prefix |
| Completion | `objectives`, optional `time_limit`, optional `awards` |
| View and publication | `camera: {focus,yaw,pitch,distance}`, `validation`, `required_assets` |

Arbitrary scene/script paths, per-instance scale, and node properties are unsupported. The retired `environment`, `environment_placement`, and `environment_snapshot` fields are rejected with instructions to rebuild using catalog pieces. Use the visual editor rather than hand-editing playable JSON.

| Location | Content |
| --- | --- |
| `res://resources/campaign/` | Official puzzle JSON |
| `res://resources/campaign_manifest.json` | Official membership, paths, chapter IDs, order, and prerequisites |
| `res://resources/campaign_chapters.json` | Chapter presentation/navigation metadata |
| `user://tracks/` | Personal tracks |
| `user://puzzles/drafts/` | Editable drafts, with optional draft-only `campaign` registration |
| `user://puzzles/published/` | Local community publications |
| `user://puzzles/community/` | Installed JSON and online puzzles |
| `user://campaign_progress.json` | Official completion, best results, and awards |
| `user://campaign_state.json` | Official route/resume state and Introduction choice |
| `user://community_progress.json` | Separate community completion by puzzle ID |

`SaveStorage` flushes a temporary JSON file before replacing the destination. PuzzleStore owns domain validation and campaign publication rollback. Imported resource hashes are not compared across packaged builds, where resource representations can differ; editing and republishing requires fresh local proof.

## Official campaign and progression

**Add to Campaign** is available only when running the Godot project with the editor feature and `project.godot` present. It validates and writes the published puzzle, manifest, and chapters, restoring previous bytes on a write failure. Existing registered paths and IDs are retained, and stale/conflicting revisions are rejected. Exported debug builds do not gain this permission.

Official membership comes from the manifest loader's provenance, never an imported field. Portable publications omit campaign registration and `_source`. Even an imported file with an official puzzle ID is community content with independent completion; local publications do not override the packaged campaign.

The manifest registers `campaign-01` through `campaign-10` in the optional Introduction and four Chapter 1 puzzles. Introduction levels are independently available. Main-route levels use explicit prerequisites, or the preceding level in their chapter when none are specified. Introduction requirements are treated as satisfied for main-route unlocking, including legacy references. Awards never gate progress. Skipping Introduction enters the main route without marking tutorial puzzles complete; finishing it reaches that route too.

Legacy embedded chapter, order, and prerequisite fields are converted into draft registration on load, preserving valid proof for that metadata-only conversion. Shared chapter metadata drives navigation. Existing completion records survive route initialization; preserve their stable IDs when maintaining content.

The Windows export preset includes campaign/example JSON, the community catalog, and public addon configuration. Registry resources, imported models, and scene dependencies must also be available; user-directory content is not shipped automatically. Use [isolated tests](ARCHITECTURE.md#verification) for persistence changes, and never republish bundled campaign fixtures as a test side effect.
