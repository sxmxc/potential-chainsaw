# Chapter 1 prototype playtest

Three unpublished drafts are available in the Puzzle Editor. Press **Ctrl+Shift+P**, click the **folder icon beside Save**, choose **Chapter 1**, select a draft and choose **Test as player**. Build and test with the normal construction tools. The curved-arrow toolbar icon returns to the authored starting layout. The save icon opens solution tools; leave reference loading alone for a blind first playthrough.

| Draft | Objective | Environmental premise |
| --- | --- | --- |
| Service block | Deliver the marble to the far collector. | A service enclosure obstructs routing between separated stations. |
| Loading loft | Deliver the marble to the loft collector. | A machinery canopy occupies the space below an elevated destination. |
| Shared clearance | Deliver each batch to its labelled collector. | Two sources and matching A/B collectors share a plant bay with conflicting clearances. |

The ten Introduction files and chapter membership remain unchanged. Drafts do not appear in player campaign navigation or record campaign completion. Local edits override the bundled draft with the same stable ID. Player tracks, progress and published puzzles retain their existing formats.

Each reference was constructed through BuildManager placement and completed the actual Jolt simulation in GUT on Godot 4.7.2 at the project's normal 120 Hz. Incomplete baselines did not complete. Tests cover environment collision, thin partitions, open space beneath decks, inventory, group placement, undo/redo, save/load and editor/test/sandbox transitions. Human playtesting must determine reasoning difficulty, alternate approaches, enjoyment and duration; these have not been established.

Player-test controls now use two icons in the existing toolbar: return to editor and solution tools. HUD bounds passed at 1024×720 and 1280×720; the final 1280×720 loft and shared-clearance screens were inspected. The boundary guide does not cast shadows. Middle-button panning now grabs the focus plane under the pointer, correcting inverted vertical motion and the former fixed speed multiplier; 21 short panning assertions passed across zooms, viewport sizes and Shift panning. Subjective camera feel still needs user review.

The broad regression run passed the Introduction reference/incomplete-layout tests, chapters/import/rules, construction/groups, elevators, functional mechanisms and marble camera before being stopped during the unrelated six-minute showcase endurance check. The corrected UI suite separately passed 664 assertions. The full suite and remaining music/settings/workflow suites were not completed. A proof-only check passed its nine assertions but reported music-playlist resources retained at engine shutdown; audio-plugin cleanup was not changed.

Fixed environments are native `.tscn` scenes selected under **Authoring tools → Boundaries**. They are separate from construction pieces and player inventory. Their static collision also blocks construction, using the existing occupied track cells and full swept bounds for mechanisms. Scene and dependency changes invalidate the physical validation fingerprint.

Authoring currently supports axis-aligned BoxShape3D solids and quarter turns, on static bodies with layer 1 / mask 2. Split walls, frames and decks into individual solids; do not enclose openings in one collider. Mesh transforms can differ from collision transforms; resize shapes instead of scaling physics bodies. Collision uses the catalog's existing 10 cm occupied cells, so placements very close to curved surfaces can remain conservative. Floating tracks remain permitted.

When exporting a build for this review, include `resources/puzzle_drafts/*.json` alongside the existing campaign JSON filters and export all native scene/model resources. Nothing here is automatically published.
