# UI refinement audit

Historical refinement audit. The approved [UI overhaul](UI_OVERHAUL_PROPOSAL.md) supersedes its font and layout direction; see [delivery notes](UI_OVERHAUL_DELIVERY.md) for the implemented result.

The existing teal/mint Theme, display fonts, logo, model thumbnails and animated
3D showcase remain the visual foundation. No global control or font reduction.

| Screen / task | Essential, always visible | Contextual / secondary | Removed redundancy |
| --- | --- | --- | --- |
| Main menu / choose how to play | Logo, campaign, build, saved tracks | Examples, settings, quit | Two competing slogans |
| Campaign / build and test a solution | Puzzle title, goal, objective progress, test, history, menu | Introduction hint while learning; restart and levels in menu | Second full-width puzzle panel, repeated title |
| Sandbox / construct a machine | Track title, save action/status, history, test, menu | Placement/drag feedback; selection actions and properties | Idle shortcut paragraph, “new construction” status |
| Construction tools / place and edit | Pieces toggle, grid, snap, grouped height controls, fit view | Rotate during placement; group actions during selection | Scattered tool labels |
| Toolbox / choose a piece | Model cards, selected state, collapse | Search/categories for larger inventories, scrolling | Counts and hover instructions; full-height empty panel |
| Campaign browser / choose a level | Chapters beside levels, chapter progress, selected goal | Resume, optional Introduction choice, locked requirement | Design-document chapter descriptions; empty list region |
| Mode menu / leave or manage work | Resume, settings, main menu | Sandbox files; campaign restart/levels; editor authoring/test/save | Sandbox management during campaign |
| Inspector / change selected properties | Piece name and applicable settings | Height/group properties, mechanism links | Duplicate selection heading and generic instructions |
| Settings / adjust camera or find controls | Settings title, camera and control tabs | Camera reset and shortcut reference | Promotional heading and redundant camera prose |
| Completion / continue or inspect | Result, next level / level select | Editor validation actions, awards | Reassurance about unchanged construction |

At idle, the construction viewport should remain unobstructed below the top bar
and tools except for the content-sized toolbox. During simulation, building UI
retracts. Guidance is a small, dismissible workspace card, never a permanent
full-width banner. Introduction display copy is separate from validated puzzle
data so IDs, progression, physical solutions and fingerprints remain intact.

Regression risks: modal focus restoration, menu actions by mode, toolbox sizing
after filters/viewport changes, hint dismissal after edits, objective refresh on
reset, and toolbar width with selection at 1280×720. Verify these in the shared
World; do not change construction or physics to accommodate UI.

## Toolbox and construction toolbar follow-up

The browser now grows downward from a stable left position. Its header, search,
and category controls stay fixed across filters; two-column cards retain their
dimensions when scrolling. All pieces is the default category.
Search, category, remembered scroll positions, and active placement survive
browsing and collapse/expand. The construction controls retain their position
when the browser closes. An unboxed placement row combines piece identity, Rotate, and Cancel.
Feedback appears only for connector snapping or invalid placement. Fan display names distinguish paddle,
standing, and upward variants without changing catalog IDs or behavior.

Verification: 73 scripts validated; UI workflows (606 checks), construction
(169), campaign permissions (24), and puzzle authoring workflow (29) passed.
Hera screenshots were inspected at 1280×720, 1600×900, and 1920×1080 for catalog
categories, scrolling, small inventories, search results, empty results,
collapse/expand, and active placement while browsing or collapsed. The final
Hera error log was empty. Native blocked/snapped feedback was not separately
visually verified; construction checks cover the underlying placement rules.
