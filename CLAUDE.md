# BallastViewer

macOS photo culling & keywording app (SwiftUI, Swift 6, GRDB/SQLite). Never modifies pixels. Clean-room rebuild of "BALLASTVIEW" — the behavioral contract is `docs/BALLASTVIEW-SPEC.md`, the roadmap and deliberate deviations are `docs/PLAN.md`.

## Build & test

- **Logic tests (fast, preferred):** `./scripts/test.sh` — runs `swift test --package-path BallastCore`. Works without a full Xcode build.
- **App build:** `./scripts/build.sh` — runs `xcodegen generate` then `xcodebuild`. App lands at `build/Build/Products/Debug/BallastViewer.app`.
- `xcode-select` on this machine points at a broken CommandLineTools install (SDK/compiler mismatch); **every** `xcodebuild` AND `swift` invocation needs `DEVELOPER_DIR=/Applications/Xcode.app` (both scripts set it). SourceKit diagnostics in the editor showing "SDK is not supported by the compiler" are this same issue — ignore them; trust the scripts.
- **After adding/removing/renaming files in `App/`:** run `xcodegen generate`. The `.xcodeproj` is generated from `project.yml` and gitignored — edit `project.yml`, never the xcodeproj. (`BallastCore/` is a plain SPM package; no regeneration needed there.)

## Architecture

- `BallastCore/` — local SPM package holding **all platform-independent logic**: models, DB schema/DAOs (GRDB), query engine, keyword tree & path resolution, neighbour rule, stable random order, sort comparators, action grammar, MIDI parser, LED state computer. New logic goes here first so it is testable with `swift test`.
- `App/` — the SwiftUI app target: views, view models, services touching AppKit/ImageIO/CoreMIDI/file panels.
- **Mutation contract (load-bearing):** the in-memory catalog on the MainActor is the authority. Mutations (1) update memory synchronously → instant UI, (2) persist the delta via async `DatabasePool.write` (single-row UPDATEs, WAL mode), (3) emit a `CatalogEvent` so counts/views update incrementally. Never block the main thread on I/O; never recompute all collections for a single-photo change.
- A library on disk is a document package `Name.ballastlib/` containing `library.sqlite`. Thumbnails live in `~/Library/Caches/` (regenerable), keyed by path+mtime+size-bucket — **not** by orientation; rotation happens in the view layer.
- Keywords are rows with identity (`keyword` table, `parent_id` tree); photos reference them by id via `photo_keyword`. Path strings like `PEOPLE > ANNA` are derived, never stored. At UI/metadata boundaries keywords are ALWAYS UPPERCASE.

## Conventions

- Swift 6 strict concurrency; `@Observable` (Observation framework), no Combine.
- UI text in English. App name is "BallastViewer" (bundle id, `.ballastlib` extension and the repo stay lowercase) (the spec's "BALLASTVIEW" is the old name).
- Before touching behavior, read spec §16: tables of bugs to fix (D1–D6, C1–C14) and quirks to keep (Q1–Q28). Deviations U1–U13 are listed in `docs/PLAN.md` and win over the spec.
- Sacred interactions (never regress): Q1 neighbour rule, Q2 stable random order, Q5 instant rotation via stored orientation, Q21 shortcut suppression while search is focused.

## Workflow

- `docs/PLAN.md` has 12 steps with checkboxes. Work **one step per session**; the user is token-conscious — do not run ahead into later steps. When a step is done: check it off in `docs/PLAN.md`, note anything a later step must know, and verify its acceptance criteria.
- **When a step is complete, commit and push** (standing instruction from the user): `git add -A`, commit with a descriptive message + `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`, push to `origin master` (github.com/clubmate/ballastviewer — HTTPS credentials are in the keychain; there is no `gh` CLI).
