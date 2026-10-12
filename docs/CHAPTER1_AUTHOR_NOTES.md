# Author reference — contains spoilers

Keep this document and the `solution` arrays out of the initial blind playtest.

## Service block

Engineering problem: choose when and where to turn around an enclosure while connecting stations at different heights. The inlet has no prebuilt route; the enclosure blocks postponing the turn until near the destination. Both sides and routes above the enclosure remain available under the game's floating-track rules. Inventory offers alternatives rather than prescribing five placements.

Reference: a gentle descending approach, two curves around the east side, a lateral straight and a descending outlet. Completion took about 7.2 seconds of simulated travel. Removing the enclosure permits later turns and different paths through its occupied space. Blind testing should assess whether the enclosure creates enough thought; this is the most approachable candidate and may need revision if immediately obvious.

## Loading loft

Engineering problem: find room to gain height without intersecting the canopy, then return to the elevated destination. The release faces into the covered bay; the collector is above it. Simply placing a lift on the apparent inlet path grows through the canopy. The bay permits low tracks, but a complete lift needs clear space. Long ramp routes are also available; unsupported tracks remain legal.

Reference: a ground route around the east side, a four-metre bucket elevator in the uncovered space, then an upper return route to the loft. Completion took about 25.6 seconds. The opening camera faces the release side of the canopy so both terminals are visible. The Factory machine on the canopy gives the occupied platform a readable industrial purpose; it has no invented mechanism behavior.

## Shared clearance

Engineering problem: route two labelled batches to their own collectors while accounting for a crossbeam and a low destination canopy. A low crossing can conflict with the other route; staying high all the way conflicts with the canopy and destination height. Players can choose where to descend, separate routes laterally or use a lift. The completion system counts source-specific deliveries, so sending both streams to an arbitrary collector cannot win.

Reference: batch A crosses beneath the beam on level track; B crosses above it and descends outside the beam into the lower collector bay. Each release sends two marbles. Both source-specific objectives completed in about 9.9 seconds. The first physics check exposed misplaced beam supports; the supports were moved out of the passage. The destination canopy was raised to provide reliable marble clearance while still blocking a high route.

## Evidence and revision

Reference constructions and physical validation records are separate `solution` and `validation` fields in each draft JSON under `resources/puzzle_drafts/`; authored baselines stay in `pieces`. GUT never rewrites bundled fixtures or publishes puzzles. Records were transferred from successful GUT output during authoring. Revisions must be tested again, then preserved through the existing editor workflow. These are feasibility proofs, not fun or uniqueness claims.

Inspect only the models used: Building Kit wall (0.1 × 2.4 × 2 m), floor (2 × 0.1 × 2 m), column (0.5 × 2.4 × 0.5 m); Factory Kit machine (about 1.2 × 1.3 × 1.5 m). All inspected GLBs have one root mesh at identity, a bottom-centred pivot and Y-up orientation. Wrappers retain original imports, with explicit companion solids. Machine collision fills its main equipment volume; visual recesses are not track passages.
