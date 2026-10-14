# Optional Introduction campaign

## Audit and checkpoint

Checkpoint: `436a335` captures the entire pre-restructure working tree, including the existing uncommitted cleanup. The ten puzzles live in `resources/campaign`, with stable IDs `campaign-01` through `campaign-10`. They contain immutable starting layouts, inventory, permissions, objectives, mechanisms, reference solutions, and validation fingerprints. `PuzzleSession.player` loads these records through the existing construction/simulation pipeline. No puzzle files were moved or edited.

Previously `PuzzleStore` returned one global ordered list, implicit unlocking depended on the preceding puzzle, the browser displayed that flat list, and the completion window opened the next global entry. Completion saves were flat dictionaries in `user://campaign_progress.json`, keyed by puzzle ID, with completion, revision, best time, piece count, and optional awards. There was no saved campaign route or chapter metadata.

## Chapters and authoring

`resources/campaign_chapters.json` defines chapter IDs, display names, chapter order, optional/introduction classification, puzzle prerequisites, descriptions, and membership lists. Its Introduction membership assigns the ten existing levels without changing their content or fingerprints. Chapter 1 is separate from Introduction and now contains four published puzzles.

Official Puzzle Editor Settings exposes Chapter ID, Chapter display name, Chapter navigation order, Optional chapter, Introduction / tutorial chapter, Chapter unlock requirements, level order and prerequisites. New community drafts have no mandatory campaign registration. Official settings live in draft-only `campaign` metadata and are promoted to project registration. The campaign manifest determines official membership, paths, level order and requirements; conflicting legacy chapter overrides remain in registration for authoring, while runtime chapter order comes from the shared chapter definitions. Portable puzzle JSON omits these fields.

Introduction puzzles are independently accessible. Main chapters unlock by their own prerequisites and level sequence; introduction requirements never gate the main route. Awards never unlock levels. On completion, navigation proceeds within a chapter and then through eligible main chapters. The final Introduction level joins the main route. Empty chapters show their description and an explicit lack of published puzzles.

Current distribution uses direct developer **Add to Campaign** promotion and `campaign_manifest.json` registration. The former bundle/importer path has been removed; see [Puzzle authoring](PUZZLE_AUTHORING.md#publication-and-distribution). Chapter assignments, IDs, filenames and prerequisites are preserved in registration.

## Saves and resume

`user://campaign_progress.json` retains its original format and IDs. Recompletion preserves unknown record fields as well as best results and accumulated awards. Chapter completion counts derive from individual completed records, separately for each chapter.

`user://campaign_state.json` stores the version, started flag, introduction-skipped flag, current chapter/level, and last visited introduction/main levels. Skipping only writes route state; it does not create completion records. A new campaign offers Play Introduction or Skip Introduction. The menu Campaign action resumes an existing campaign; Level Select remains available from the puzzle HUD and completion window.

Legacy saves without route state infer an existing campaign and resume at the first incomplete introductory level, or Chapter 1 if all ten are complete. This inference preserves all original records and suppresses the new-player choice. All tests use isolated user directories; production player saves are untouched.

## Chapter 1 content brief

Chapter 1 needs separately authored and physics-verified engineering puzzles. Prefer multiple viable layouts under limited inventory, route planning across elevations, managing speed and momentum, and interactions between gates, sensors, diverters, launchers, fans, and elevators. Combine several constraints in each puzzle rather than presenting isolated component demonstrations. Preserve reference solutions separately from starting layouts, make success depend on the authored objectives, and use optional efficiency awards rather than award-gated progression.

Skip Introduction opens the registered Chapter 1 route without completing tutorials. Completing Introduction reaches that same route. Further campaign content still requires separate authoring and playtesting.

## Verification

Use the GUT panel or `godot --headless --path . --script addons/gut/gut_cmdln.gd -gexit`. Campaign suites cover stable IDs, migration, Introduction choice and skipping, chapter grouping, unlocks, resume, authoring metadata, and all ten positive/negative physics cases. Fixtures isolate player saves; tests never republish puzzle files.

GUT persistence fixtures redirect application saves through `SavePaths` and `MARBLE_ENGINEER_TEST_DATA`, and restore them with the shared fixture lifecycle. Logs can be written under `.godot/`; the old custom runner is no longer used.

The original chapter UI was verified when this restructure was introduced. Its ZIP/Python checks described the former distribution workflow and have been replaced by native GUT promotion/import tests. The current campaign also contains four published Chapter 1 puzzles; the earlier empty-chapter observations are historical.
