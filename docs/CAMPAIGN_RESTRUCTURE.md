# Optional Introduction campaign

## Audit and checkpoint

Checkpoint: `436a335` captures the entire pre-restructure working tree, including the existing uncommitted cleanup. The ten puzzles live in `resources/campaign`, with stable IDs `campaign-01` through `campaign-10`. They contain immutable starting layouts, inventory, permissions, objectives, mechanisms, reference solutions, and validation fingerprints. `PuzzleSession.player` loads these records through the existing construction/simulation pipeline. No puzzle files were moved or edited.

Previously `PuzzleStore` returned one global ordered list, implicit unlocking depended on the preceding puzzle, the browser displayed that flat list, and the completion window opened the next global entry. Completion saves were flat dictionaries in `user://campaign_progress.json`, keyed by puzzle ID, with completion, revision, best time, piece count, and optional awards. There was no saved campaign route or chapter metadata.

## Chapters and authoring

`resources/campaign_chapters.json` defines chapter IDs, display names, chapter order, optional/introduction classification, puzzle prerequisites, descriptions, and membership lists. Its Introduction membership assigns the ten existing levels without changing their content or fingerprints. Chapter 1 is a distinct empty collection; no new puzzles were generated.

Puzzle Editor Settings exposes Chapter ID, Chapter display name, Chapter navigation order, Optional chapter, Introduction / tutorial chapter, and Chapter unlock requirements. Reusing a known ID populates its metadata; entering a new ID defines another chapter. The existing Order field orders levels within their chapter. The existing prerequisite selector continues to configure individual puzzle requirements. New drafts default to the main campaign. Metadata is stored in the puzzle's `chapter` dictionary, with explicit membership taking precedence over manifest membership. Published puzzles automatically introduce their chapters into navigation, without navigation-code changes.

Introduction puzzles are independently accessible. Main chapters unlock by their own prerequisites and level sequence; introduction requirements never gate the main route. Awards never unlock levels. On completion, navigation proceeds within a chapter and then through eligible main chapters. The final Introduction level joins the main route. Empty chapters show their description and an explicit lack of published puzzles.

Editor bundles include `campaign_chapters.json`; the importer merges chapter membership while preserving existing assignments. Existing puzzle IDs and filenames remain stable on import.

## Saves and resume

`user://campaign_progress.json` retains its original format and IDs. Recompletion preserves unknown record fields as well as best results and accumulated awards. Chapter completion counts derive from individual completed records, separately for each chapter.

`user://campaign_state.json` stores the version, started flag, introduction-skipped flag, current chapter/level, and last visited introduction/main levels. Skipping only writes route state; it does not create completion records. A new campaign offers Play Introduction or Skip Introduction. The menu Campaign action resumes an existing campaign; Level Select remains available from the puzzle HUD and completion window.

Legacy saves without route state infer an existing campaign and resume at the first incomplete introductory level, or Chapter 1 if all ten are complete. This inference preserves all original records and suppresses the new-player choice. All tests use isolated user directories; production player saves are untouched.

## Chapter 1 content brief

Chapter 1 needs separately authored and physics-verified engineering puzzles. Prefer multiple viable layouts under limited inventory, route planning across elevations, managing speed and momentum, and interactions between gates, sensors, diverters, launchers, fans, and elevators. Combine several constraints in each puzzle rather than presenting isolated component demonstrations. Preserve reference solutions separately from starting layouts, make success depend on the authored objectives, and use optional efficiency awards rather than award-gated progression.

There is no Chapter 1 Level 1 yet. Skip Introduction therefore opens Chapter 1's empty collection. When its first puzzle is published, the saved main route resumes there automatically. Completing Introduction reaches that same collection. Shipping an immediately playable main campaign requires separate content authoring.

## Verification

Use the GUT panel or `godot --headless --path . --script addons/gut/gut_cmdln.gd -gexit`. Campaign suites cover stable IDs, migration, Introduction choice and skipping, chapter grouping, unlocks, resume, authoring metadata, and all ten positive/negative physics cases. Fixtures isolate player saves; tests never republish puzzle files.

The revised runner redirects only application saves through `SavePaths` and `MARBLE_ENGINEER_TEST_DATA`. Logs go into the same uniquely named OS temporary directory. Its `finally` block verifies the cleanup path, removes that invocation's files, and reports their size. `APPDATA` is unchanged; `.local-user` is never created. No project, Godot installation, model imports, or asset caches are copied.

Chapter verification passed 71 checks, including real editor ZIP export and untouched validation fingerprints. `python -B tests/test_campaign_import.py` passed three importer checks for round trips, future chapters, and rejection without partial staging. Hera inspected runtime PID 13660: at 1024×720, the new-campaign choice and empty Chapter 1 showed no screenshot clipping; a click on Skip Introduction removed the choice and selected Chapter 1 with zero introduction completions. The editor's chapter fields were inspected in its existing scrollable Settings tab. The review process exited and its nine temporary files, including three screenshots, were removed (311,836 bytes total).

The headless gate exposed a fragile audio-bus UID lookup; `project.godot` now references the same unchanged audio-bus resource by path. This permits fresh or isolated caches to load it consistently.

Final regression: 71 scripts compiled; music (8), construction (169), elevator (62), supports (1,160), mechanisms (53), campaign rules (24), puzzle workflow (29), and chapter (71) checks all passed. All ten reference solutions completed and all ten incomplete layouts failed as expected. The runner removed its 22 files totaling 8,335 bytes. A Git comparison against checkpoint `436a335` confirmed no changes to any original campaign puzzle file.
