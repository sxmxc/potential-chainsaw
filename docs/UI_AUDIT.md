# UI review record

Review date: 2026-10-15. This replaces the earlier assumption that inspecting the main menus covered the interface. The repository contains 33 UI scenes, including nested widgets. Coverage below distinguishes rendered layouts from source inspection and unverified behavior. This is a review and an initial correction pass, not a claim that the entire interface has reached its final visual quality.

## Method and evidence

Rendered the actual application host and its existing scenes with Godot 4.7.2 Forward+ at 1920x1080. Also inspected Settings, tracks, Campaign, and the authoring workspace at 1024x720. Review data used an isolated fixture directory. The existing editor remained open; no editor import process was launched and no UID was manufactured.

Temporary review captures, isolated fixture data, capture script, and diagnostic logs were removed after review. Online/account and completion screens were deliberately opened as layout fixtures: they do not establish working authentication, publication, download, or puzzle completion.

## Scene and state coverage

Paths below are relative to `scenes/ui/`. Rendered means the resulting image was inspected, not merely saved.

| Scene or group | Inspected states | Findings and current status |
| --- | --- | --- |
| `main_menu.tscn` | Logo, navigation, Steam identity, animated machine background | Preserved logo/showcase. Full entrance/exit timing and every focus state still require hands-on assessment. |
| `dialogs/settings_dialog.tscn` | Camera, Audio, Display, Controls, binding capture; 1080p and 1024x720 | Replaced top tabs with category navigation and a scrolling page; preserved settings and binding behavior. |
| `track_browser.tscn` | Examples, personal saves empty/populated, rename, delete confirmation; two resolutions | Better list/preview proportions and footer action placement; empty saves hide irrelevant controls. Corrected initial wrapped-text sizing that inflated the window. |
| `puzzle_browser.tscn` | Campaign chapters/list/detail, installed community empty state, import dialog; two resolutions | Shared spacing and modal framing. Long titles/descriptions and populated community fixtures subsequently reviewed at 1024x720 with bounded text. Every locked/completed route variant remains unverified visually. |
| `community_online.tscn` | Populated results, unavailable message, share-code section, account section as layout fixtures | Bounded scrolling page with persistent primary action and service feedback; long description and account fixtures reviewed. Live authentication/loading/retry/download/publication remain unverified. |
| `dialogs/workspace_menu.tscn` | Sandbox, Authoring, Player, Player Test | Shared spacing/backdrop reviewed in each context; context actions remain with their existing owner. |
| `dialogs/name_dialog.tscn` | Save-name prompt | Content-fitting window and shared spacing reviewed. Interrupted dismissal/reopen covered by GUT. |
| `dialogs/unsaved_dialog.tscn` | Cancel/discard/save prompt | Corrected excessive initial height using native wrapping and an authored text width. |
| `dialogs/message_dialog.tscn` | Informational/error-style message | Corrected initial sizing; long messages now use bounded selectable text with native scrolling. The action remains visible at 1024x720, verified by a regression test. |
| `puzzle_completion.tscn` | Player and Player Test result layouts | Content fitting reviewed. Fixture success is not successful-test proof; failure variants remain unverified visually. |
| `workspace_hud.tscn`, `toolbars/file_toolbar.tscn`, `toolbars/edit_toolbar.tscn`, `toolbars/build_toolbar.tscn` | Sandbox, selection, authoring, player build, paused simulation; smaller authoring window | Existing actions retained. At 1024x720 with both side panels open, bottom controls form an awkward narrow vertical strip. Resolved by a full-width bottom dock below the columns. Removed catalog minimum-height feedback that prevented shrinking after a larger window; verified at 1024x720. |
| `toolbox.tscn`, `widgets/piece_card.tscn` | Normal catalogue, authoring inventory, constrained player build, extension list | Shared surface padding now consistent. Cards now reserve a consistent three-line caption region, use the original display name, and share thumbnail alignment. Removed per-ID caption substitutions. Long names can still ellipsize; full names remain in tooltips. |
| `inspector.tscn` | Sensor, elevator, single/group permissions, expanded permission section | Increased useful width. Added section hierarchy, vertical label/value fields, and two-column permission actions. Boolean and string settings were rendered on actual gate/release pieces. Inspector content scrolls within a bounded height. |
| `puzzle_authoring.tscn` | All five pages; setup advanced, campaign settings upper/lower, inventory restrictions, boundary dimensions, objectives, publish | Five navigation tabs now fit one row. Setup now separates details, starting view, rules, awards, and campaign placement with shared heading/field styles. Campaign fields stay grouped under the existing destination permission. |
| `widgets/guidance_editor.tscn` | Player hints and expanded marker/timing controls in Objectives | Rendered with the actual owner. Added heading hierarchy, paired labels/fields, and a descriptive Marker and timing disclosure. |
| `widgets/inventory_row.tscn` | Authoring inventory quantities/restrictions | Reviewed in the drawer rather than in isolation. Large inventories and all disabled states remain unverified. |
| `puzzle_bar.tscn` | Player build goal/hints presentation | Reviewed in context. Every objective/progress/error message combination remains unverified. |
| `widgets/extension_picker.tscn` | Actual compatible track list and search layout | Corrected giant saved size, removed obsolete offsets, constrained wrapped hint width. Fixed empty search excluding every compatible piece. Search/reset regression test added. |
| `widgets/mechanism_wiring.tscn`, `widgets/wiring_terminal.tscn` | Existing links, fan-out, elevation, pending connection menu | Slender channelled conduits, lower arcs, distinct terminals, precise input snapping, persistent pending wire. Dense real-machine composition and perceived motion still need human evaluation. |
| `widgets/construction_preview.tscn` | Track and Campaign previews | Rendered actual registered geometry in existing preview host. Unusual large/tall machines remain unverified. |
| `widgets/chapter_button.tscn` | Introduction and Chapter 1 cards | Reviewed in Campaign. Additional chapter counts and long names remain unverified. |
| `widgets/key_binding.tscn` | Controls page and active binding capture | Reviewed with settings owner; category switching cancels capture without modifying values. |
| `widgets/mechanism_number.tscn`, `widgets/setting_slider.tscn` | Inspector numeric settings and Settings sliders | Rendered in their hosts. Full pointer/keyboard adjustment and every value format not exercised in this pass. |
| `widgets/compact_tooltip.tscn` | Multiline tooltip layout fixture | Layout inspected. Actual hover timing, viewport-edge placement, and keyboard tooltip behavior remain unverified. |
| `widgets/selection_overlay.tscn` | Scene/source inspected; selected construction visible in host | Did not comprehensively exercise connector placement, marquee, trajectories, invalid placement, or all overlay states visually. |
| `widgets/piece_flag.tscn`, `widgets/piece_text.tscn` | Scene/source inspected | Boolean and string settings were subsequently rendered in actual gate/release inspectors. Checkboxes now use explicit outlined/checked vector icons rather than the low-contrast default square. |

## Design findings still requiring work

The common problem is weak hierarchy: many surfaces give headings, secondary explanation, fields, and actions similar visual weight. Shared teal surfaces alone cannot make a deliberate game interface. This pass establishes more consistent modal framing, spacing, navigation, and action placement, and fixes concrete broken layouts.

The follow-up polish pass implemented authoring groups, a full-width dock, stable catalog resizing, consistent card captions, clearer checkbox states, and vertical inspector fields. Populated community, account, error, and long-description fixtures were rendered at 1024x720. The scrolling community page keeps its primary action and feedback visible. Long Campaign titles/descriptions are bounded as well. These layout fixtures do not establish live-service behavior. Selection/placement feedback, controller navigation, and subjective visual evaluation remain separate checks.

## Validation and limits

Focused GUT results: Settings/input 2/2; world guidance 7/7; workspace input 4/4; wiring presentation 6/6; real-renderer UI surfaces 3/3. The latter checks content growth, interrupted modal dismissal, category/binding behavior, and extension search/reset. Headless window sizing cannot substitute for the renderer because its dummy display reports 1x1 windows.

The first broader test run caught a stale halo-shader UID reference. Removed that stale reference and kept the resource path; the repeated affected tests pass. Initial layout captures also exposed wrapped-text sizing errors, which were corrected and recaptured. Restricted capture runs reported unavailable Steam/certificate/log access and audio resources retained at forced exit; the final focused capture with normal runtime access and music cleanup exited without those errors.

These checks do not verify all hover/focus states, controller navigation, live community operations, every resolution, gameplay completion, or subjective visual quality. Human visual evaluation remains necessary, particularly for wiring motion and crowded machines.

## Follow-up polish verification

The temporary polish captures and runtime logs were inspected during the review and subsequently removed during cleanup; this record retains the findings and verification results. The initial toolbar scene/script base-type mismatch was caught and corrected before the final review. A missing community page height constraint and catalog resize feedback were also caught in rendered review and fixed.

Current focused checks: world guidance 7/7; puzzle distribution 4/4; real-renderer UI surfaces 5/5 (including catalog shrink and long-message overflow). Workspace input is 3/4: its remaining failure is GUT treating the recurring stale halo-shader UID fallback warning as an unexpected engine warning. The material reference was rewritten with that UID again during the open-editor session; do not manufacture a replacement UID or run a competing editor import to force a clean result. No gameplay assertion failure was reported by that suite.

The new checkbox SVGs were imported automatically by the already-open editor. No manual import or UID generation was performed. Live community authentication/download/publication were not exercised; fixtures changed only isolated local presentation data. Human visual review is the handoff for this pass.
