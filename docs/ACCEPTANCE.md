# Acceptance sweep — spec §18

Status of every §18 checklist line as of roadmap step 12.
Legend: **[x]** verified · **[U]** deliberately deviates (U-number in `docs/PLAN.md`) · **[HW]** needs real hardware · **[ ]** open.
"core test" = suite in `BallastCore/Tests`; "BVxxx" = headless hook run (`App/Services/TestHooks.swift`); "visual" = screenshot-verified in the step noted.

## Library file

- [U] Opens `MyLibrary.json` / `MyLibrary2.json` — **deviation by fixed decision**: no JSON compatibility, fresh GRDB/SQLite schema (`docs/PLAN.md` Fixed decisions).
- [U] Writes pretty-printed JSON with ISO-8601 dates — n/a, SQLite persistence.
- [x] A new library contains the six default keyword groups with the exact §8.3 colours (core `SchemaTests`, step 2). Empty-arrays part is n/a (SQLite).
- [U] Every mutation updates `metadata.lastModifiedDate` — not carried over; SQLite WAL makes the freshness signal unnecessary. No consumer in the app.
- [x] Killing the app mid-edit never leaves a truncated catalogue (D3): kill -9 during a 300-write rating churn → `PRAGMA integrity_check` ok, clean reopen (step 10).

## Lifecycle

- [x] Last opened library reopens automatically at launch (BVTEST, step 3).
- [x] *Close Library* prevents auto-reopen, recents stay (BVTEST, step 3).
- [x] Recents hold max 10, most recent first, deduped (step 3; visible in Open Recent menu).

## Import

- [x] Exactly the eleven §5.3 extensions (`FolderScanner`, core `ImportTests`).
- [x] Re-import adds only new files, matched by absolute path (core + BVTEST rescan, step 4).
- [x] One `importBatchId` per invocation; LAST IMPORT shows that batch (steps 4/7).
- [x] Empty rescan leaves LAST IMPORT unchanged (Q7; by construction — no batch row without new photos; core test).
- [x] Keywords/rating/orientation read at import (core `MetadataReaderTests`, XMP first, IPTC fallback).

## Metadata

- [x] File keywords uppercased, de-duplicated, sorted (core test).
- [x] Writing never recompresses — decoded pixels byte-identical before/after (core `MetadataWriterTests`).
- [x] Rating survives Save → Load (D1; core round trip + BVS10 through the app path).
- [x] Unassigned vocabulary survives Load (D2; BVS10 `unusedSurvivesLoad=true`).
- [x] Rotation is library-only until Save Metadata (Q5 display transform; BVS10 file check).
- [x] Rotation cycle 1→6→3→8→1, other values jump to 6 (core `RotationCycleTests`).

## Query engine

- [x] Full §7.3 matrix incl. false-returning operators (table-driven core `QueryEngineTests`).
- [x] No rules → matches everything (Q6, core test).
- [x] `keywordGroup` matches nested keywords (C2; core test via `effectiveGroupId`).
- [U] Seven pseudo-collections with exact §7.5 UUIDs — **U: no magic UUIDs**; pseudo-collections are `SidebarItem` enum cases, same behaviour (Q8/Q9 tested).
- [x] Star rows filter and count on exact rating (Q9; BVQUERY).
- [x] LAST IMPORT empty before first import (Q8, real match-nothing; core test).
- [x] Counts update live via per-photo deltas (BVCULL badge check, step 7).

## Keywords

- [x] `ANNA` → `PEOPLE > ANNA` when the node exists, else creates `ANNA` (Q16; core resolver tests + BVKEY).
- [x] Input field forces uppercase per keystroke (Q15; InspectorView, visual step 8).
- [x] Autocomplete offers intermediate nodes (Q17; core `KeywordAutocomplete`).
- [x] Chips sort group order → alpha, ungrouped last (Q18; core `KeywordChipBuilder` tests).
- [x] Chip colour follows the leaf's effective group (C2; core test).
- [x] Right panel shows the selection's intersection (Q14; BVKEY).
- [x] ↓ wraps, ↑ leaves at first, ↑ from none jumps last (core `AutocompleteHighlight` tests).

## Selection and navigation

- [x] Click / shift / cmd per §9.3 (`SelectionModel` core tests; visual step 5).
- [x] Next/Previous stop at ends (core + BVCULL).
- [x] Move up/down steps by column count (`moveAnchorByRow`).
- [x] Collection switch auto-selects first photo (BVQUERY `anchorIsFirst=true`).
- [x] **Neighbour rule Q1** (core `NeighbourRuleTests` + BVCULL live in a rules-based unrated collection).

## Sorting and search

- [x] Filename = full path; Rating deliberately **removed** in favour of U9's five options (Filename/Path/Capture Date/Date Added/Random — core `SortEngineTests`).
- [x] Random stable across filter changes, re-rolls only on switching to Random (Q2; core `StableRandomOrderTests`).
- [x] Search case-insensitive, stacks with the collection — and includes filenames (U5; core `SearchFilterTests` + BVS9). Typing is debounced 150 ms (deviation from per-keystroke apply: one refilter costs ~185 ms at 50k); clearing applies instantly.

## Shortcuts

- [x] §12.3 defaults on first launch, restored by Reset Defaults (verified against the persisted plist, step 9).
- [x] Key strings `ctrl+opt+shift+cmd+<key>` in fixed order (core `KeyChord` tests).
- [x] Binding removes both previous key and previous action (§12.4; core `KeyMap` tests + live).
- [x] All nineteen actions dispatch (C5; exhaustive switch, BVCULL ratingUp check).
- [x] No shortcut fires while search has focus (Q21; typed digits filter instead of rating, step 9 visual).

## MIDI

- [x] Velocity > 0 triggers, velocity 0 is Note Off (core `MidiParserTests`).
- [x] `note:<0-based ch>:<n>` / `CH<1-based> N:<n>` (core `MidiAddressTests`; visual in Settings).
- [x] Debounce per action (implemented in `MidiService`; window logic straightforward — not separately E2E-tested).
- [x] Rating 4 lights pads 1–4, rate-0 exact (Q4; core `LEDStateComputerTests`).
- [x] View-mode pads incl. toggleViewMode lit in single (core tests).
- [x] Keyword pads exact match (core tests + virtual-controller E2E, step 11).
- [x] Note Off re-assert (Q3; E2E — release re-sent `90 3C 7F`). **[HW]** confirm on a physical pad controller.
- [x] Selection change updates LEDs immediately (Observation-driven diff sends; E2E). **[HW]** "within one frame" on hardware.

## UI

- [x] Window min 800×600; panels 200–300 / min 400 / 250–350 (MainWindow frames).
- [x] Panels hide/show and persist across launches (step 12, defaults-verified).
- [x] Columns 1–10; square cells; fill-crop **top-aligned** (Q22, step 12 visual: red-top portrait shows red; 180° shows blue); 3 pt accent border.
- [x] Grid spacing controls gaps and outer padding (Q23; Appearance slider wired to `GridFlowLayout`).
- [x] Centre background configurable + persists (canonical `#RRGGBBAA`, C8; step 9 visual).
- [x] Empty filtered set shows "No Photos Found" (MainWindow empty state).
- [x] Single view shows `n / total` (step 9 visual "1 / 8").
- [x] Tapping current star clears to 0 (Q12; InspectorView).
- [x] Rule editor: exactly five §9.7 types plus U10's Capture Date; operator resets on type change (step 7).
- [x] Settings 600×500 with three tabs (steps 8/9 visual).

## Menus

- [x] ⇧⌘N / ⇧⌘O / ⇧⌘I fixed, not remappable (LibraryCommands hard-coded).
- [x] Photo/View items show live key bindings and update on change (⌥⌘N appeared instantly, step 9).
- [x] Enable/disable per §14 (Photo menu disabled without anchor; Library items gated on open library).

## Performance (post-hardening gate, 50k synthetic photos)

- select median 9.1 ms, jump median 11.0 ms, **keystroke→UI (rate) median 6.5 ms** (< 16), **keystroke→durable median 6.6 ms** (< 100), one debounced search apply 185 ms, footprint 121 MB.
- Async write-through commits strictly in submission order (WritePipeline); kill -9 WAL guarantee unchanged.
- No main-thread I/O by construction: DB writes on GRDB's pool queues, thumbnail decodes in nonisolated tasks behind an actor, metadata sync in bounded task groups. A formal Instruments pass with 50k *real* photos remains open (fixtures are synthetic PNGs).

## Open items

- Hardware MIDI checklist (§18 MIDI block) on a physical pad controller — including released-pads-stay-lit and USB hot-plug.
- Instruments session with real photo files.
- §9.10 overlay scrollbars applied to the grid; sidebar/inspector keep the system SwiftUI scroller behaviour.
