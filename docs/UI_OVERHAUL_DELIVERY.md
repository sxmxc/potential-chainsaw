# Approved UI overhaul — delivery

The approved design is implemented in editable Godot scenes and the shared Theme. The original animated 3D showcase and logo remain. Main-menu navigation now follows the approved unboxed left column, with a gold logo and a readable Campaign action.

Final native main-menu and sandbox screenshots were captured and inspected through Hera at a true 1280×720 viewport after the final changes. They are retained in the OS temporary directory as `marble-delivered-menu.png` and `marble-delivered-hud.png`. That run reported zero runtime errors and was stopped after inspection.

The HUD uses separate file/history and test/menu islands, bottom placement/selection controls, a collapsible content-aware piece drawer, and properties only for configurable single pieces. Campaign navigation uses horizontal chapter cards and completion/lock symbols. Puzzle Editor uses a world-side drawer with seven navigation pages, advanced setup disclosure and the existing publication gates. Settings, saves and completion use bounded dialogs. Mode-specific menus, contextual Introduction hints, singular/plural counters and shorter display copy share the existing game systems. Puzzle IDs, authored layouts and solution fingerprints are preserved.

Nunito Sans replaces the ordinary display font; the stylized logo remains. Regular, semibold and bold are saved FontVariation resources. Both font candidates retain their full OFL notices. Native controls were compared with the former font and Rubik; the final Nunito controls were inspected at all three resolutions.

## Verification

`./tools/verify_campaign.ps1` passed in full on Godot 4.7.2, using temporary isolated test data that the runner removed afterward:

After the final button-padding and modal-guard changes, the affected construction, UI and puzzle-workflow gates were run again and passed. The UI total below includes the added modal-guard regression check.

| Gate | Result |
| --- | --- |
| GDScript loading | 73 scripts, 0 failures |
| Music transitions | 8 checks, 0 failures |
| Construction and example physics | 169 checks, 0 failures |
| Bucket elevator | 62 checks, 0 failures |
| Resizable supports | 1160 checks, 0 failures |
| Functional mechanisms | 53 checks, 0 failures |
| Campaign permissions | 24 checks, 0 failures |
| Puzzle authoring workflow | 29 checks, 0 failures |
| Chapter progression | 71 checks, 0 failures |
| UI workflows | 47 checks, 0 failures |
| Introduction simulations | All 10 known-good solutions completed; all 10 incomplete starts rejected |

The construction gate sends real viewport mouse input for selection, dragging, cancellation, marquee selection and UI blocking. UI checks cover mode-specific actions, inventory sizing, group actions, inspector height, all authoring pages at 720p, settings bounds, blank-name prevention, simulation controls and delivery reset. The workflow gates exercise saving, isolated player tests, solution preservation, revision validation and publication rules.

The full check uncovered and corrected a deferred Settings resize that reopened a closed dialog and intercepted world input. A regression check now closes Settings before that resize runs and verifies that the dialog stays closed. Completion labels have a useful wrapping width before their content-height measurement, preventing an oversized initial popup.

A subsequent Hera call incorrectly requested Settings while the campaign browser was still open, after an unsupported semantic click failed to close that embedded Window. That produced an exclusive-child-window error during QA. Settings now preserves any existing exclusive modal; a regression check verifies that it cannot open over the browser. This guard does not replace ordinary navigation or close the player's current dialog.

Native visual inspection used Hera only, with one running game at a time and retries for transient busy responses. Main menu, sandbox typography/properties and the authoring drawer were inspected at 1280×720, 1600×900 and 1920×1080. All seven authoring pages, campaign navigation and its empty state, Camera settings and the Build controls reference were inspected at 720p. Earlier live inspection covered campaign gameplay, group selection and mode states. This is not a claim that every dialog/state was manually clicked at every resolution: save/delete/publication behavior was verified by the isolated workflow tests, and completion behavior by simulation and resource/layout checks. Hera's semantic click command rejected a button in an embedded child Window; no alternate visual runtime was launched.

## Remaining limits

Godot still reports three invalid-UID warnings for the new font-variation references and falls back to their text paths. UID repair, UID-file edits and project upgrades were left alone as explicitly requested. The Windows root-certificate-store error also appears in headless runs; the existing verification runner excludes that environment error. Neither is concealed as a clean warning-free run.

Changes remain uncommitted for review. The approved mockup is retained in [review.html](ui-proposal/review.html), and current conventions are in [UI_DESIGN.md](UI_DESIGN.md).
