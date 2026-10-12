# Campaign verification

Verified on Godot 4.7.2, Jolt Physics, 120 physics ticks/second. Run `./tools/verify_campaign.ps1`; it isolates user saves under `.local-user`, restores APPDATA afterwards, and fails on script/runtime errors or failed assertions. The host's certificate-store startup error is the sole excluded environment error.

## Coverage

| Suite | Checks | Result |
| --- | ---: | --- |
| Existing sandbox construction and physics | 169 | Pass |
| Bucket elevator | 62 | Pass |
| Adjustable supports | 1,160 | Pass |
| Functional mechanisms | 53 | Pass |
| Campaign rules, linking and objectives | 24 | Pass |
| End-to-end puzzle authoring/publishing | 29 | Pass |

Mechanism checks exercise all four airflow variants forward/reverse, linked reversal, finite range and reset; both exposed paddle variants transfer physical momentum; the gate blocks, opens and auto-closes; the launcher fires once and retains a marble until an external trigger; a sensor dispatches a persistent link once; the diverter physically routes both exits and alternates successive marbles. Existing elevator coverage includes three simultaneous arrivals, varied heights/orientations, pause, reset, serialization and output snapping.

Campaign rule checks include locked mixed groups, duplicate stock consumption, undo refunds, dimensional boundaries, elevator height limits, link remapping/deletion/undo, multiple physical releases, source-specific objectives, pending-release pause/reset, activation-only success, unlock progression and optional awards. The workflow test creates a draft, authors rules, rejects an untested publish, solves under player restrictions, preserves the reference, restores the baseline, publishes, completes the published level, saves progress and invalidates old proof after a revision.

## Ten bundled puzzles

Every reference is constructed through the shared public construction/configuration commands and run through real physics. Every incomplete baseline is also run and must fail. Reference solutions serve verification and developer authoring only; the gameplay evaluator accepts any physically successful layout that obeys the rules.

| # | Puzzle | Intended lesson | Verified completion |
| --- | --- | --- | ---: |
| 1 | First Connection | Bridge one missing straight | 2.95 s |
| 2 | Around the Bend | Curves, orientation and connector placement | 5.12 s |
| 3 | One Level Down | A ramp connects different elevations | 2.88 s |
| 4 | A Little Push | Directed airflow supplies uphill energy | 2.90 s |
| 5 | Spinning Trouble | Physical paddle rotation controls passage | 2.95 s |
| 6 | The Long Way Up | Connect a 4 m bucket elevator | 12.80 s |
| 7 | Stop and Go | A timed gate releases the marble | 6.81 s |
| 8 | The Fork | Select the correct physical branch/collector | 5.38 s |
| 9 | Remote Control | Sensor Entered opens a remote gate | 3.23 s |
| 10 | The Machine | Elevator, sensor, gate and launcher cross an upper gap | 21.47 s |

Detailed machine results are in `campaign_results.txt` and the individual `*_results.txt` reports. JSON references include engine/timing evidence and a fingerprint of the tested authored content. The runner stages all new proof records and writes them only if the whole campaign passes.

## Rendered review

`tools/campaign_visual_qa.gd` renders the actual game with the Compatibility renderer at 1024×720, 1280×800 and 1920×1080. The 48 framebuffer captures under `campaign-qa/` cover the main menu, level selection, puzzle HUD, physical completion, editor, all seven authoring tabs, Test as Player and return, plus mechanism inspectors. `campaign-qa/evidence.json` lists them. The review caught and corrected small-window toolbar wrapping and panel-height overflow. Hera also checks the existing editor and live game; the exported PNGs are real renders rather than interface mockups.

## Limits

- These are automated physical playtests and rendered UI checks, not a human difficulty/enjoyment study. Timing and success can change with engine/physics versions; rerun the campaign verification before upgrading or shipping.
- A platform executable/export was not produced or tested. Follow the authoring guide's JSON inclusion and export-template instructions.
- The authoring UI supports one selected configuration-key restriction per starting piece, alongside a full-configure permission; numeric inventory limits can cover several keys. It does not yet offer a multi-key checkbox whitelist per starting piece.
- Authoring metadata uses explicit draft saves. Construction and mechanism configuration/link edits use existing undo/redo; metadata forms do not have a separate global undo history.
- The first ten levels introduce one dominant mechanic each and one combined machine. They have verified solutions, but optional awards are left unset for designers to tune after human playtesting.
