<p align="center">
  <img src="App/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="BallastViewer icon">
</p>

<h1 align="center">BallastViewer</h1>

<p align="center">
  Fast photo culling &amp; keywording for macOS — and it will <strong>never, ever touch your pixels</strong>.
</p>

<p align="center">
  <a href="https://github.com/clubmate/BallastViewer/releases/latest"><img src="https://img.shields.io/github/v/release/clubmate/BallastViewer?label=release" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-6-orange" alt="Swift 6">
  <img src="https://img.shields.io/badge/UI-SwiftUI-purple" alt="SwiftUI">
</p>

---

BallastViewer is a keyboard-first tool for the unglamorous part of photography: going through thousands of shots, rating them, keywording them, and throwing the ballast overboard. It is built for speed on large libraries (50,000+ photos), stores everything in a plain SQLite file next to your images, and writes ratings and keywords into your files in Lightroom's metadata format — so nothing is ever locked in.

## Features

### Culling

- **Grid and single view** with instant switching, zoomable thumbnails, and full-resolution single view.
- **Ratings 0–5**, applied to the whole selection at once; batches are one undo step. ⌘A selects every visible photo.
- **The neighbour rule:** rating a photo inside a filtered view advances to its neighbour instead of jumping to the top — cull forward without ever touching the mouse.
- **Stable random order:** a Random sort that keeps its order while you work, so rating a photo never reshuffles the list under your hands.
- **Instant rotation** via stored orientation — display-only, files untouched, no re-decode.
- **Search** matches keywords and filenames, on top of the active collection; space-separated terms combine with OR (`PARIS ROME`), and `LOCATION > ROME` stays one path term.
- **Full undo** for ratings, rotations, keyword changes, and even folder removal.

### Keywords

- **Hierarchical keyword tree** (`PEOPLE > ANNA`) with color-coded keyword groups.
- **Keyword chips** on the selection: type a bare name and it resolves to the full path in your vocabulary; renaming a node updates every photo instantly. Same-named keywords under different parents are distinct — the dropdown's "Create" row makes a new one even when a namesake exists elsewhere.
- **Keyword browser** in the inspector: the whole hierarchy with per-keyword photo counts; click any keyword to filter the library by it (descendants included).
- **Reorganize imported hierarchies:** move a nested keyword to the top level of any group — subtree included, and a same-named keyword absorbs it (photo assignments merge).
- **Keyboard and MIDI shortcuts** for your most-used keywords.

### Smart collections

- Rule-based collections (keyword, rating, filename, keyword count, keyword group, dates) with AND/OR matching, organised in sidebar groups.
- Fixed sidebar filters for every rating level — including UNRATED — plus ALL PHOTOS and LAST IMPORT.

### Metadata — Lightroom-compatible, automatic

- Ratings and keywords are written into your image files **automatically** (debounced, crash-safe): `xmp:Rating`, `dc:subject`, and the hierarchical `lr:hierarchicalSubject` — the exact format Lightroom Classic reads and writes.
- A **bulk progress panel** appears in the sidebar when thousands of files are being written (e.g. after a Lightroom import).

### Lightroom Classic import

- **Library ▸ Import Metadata from Lightroom…** reads a `.lrcat` catalog directly and merges its ratings and keyword hierarchies into photos already in your library — additive, idempotent, and safe: photos are matched by path (with a unique-filename fallback for moved files), anything ambiguous is skipped, tagged with a dated review keyword, and collected in an automatically created smart collection for you to inspect.

### MIDI controllers

- Map any pad or key to ratings, navigation, view switching, or keyword toggles.
- **LED feedback** mirrors the current photo's state on your controller; hot-plugging supported.

### BallastPicker

- A standalone first-pass picker (⇧⌘P): browse a folder tree, step through photos, rotate losslessly, and move keepers into an `_auswahl` subfolder — before anything enters a library.

### Libraries

- A library is a single `Name.ballastlib` package containing one SQLite file — trivially backed up, moved, or inspected.
- Manage any number of libraries; import into closed ones without opening them.
- **Built-in updates:** BallastViewer ▸ Check for Updates… installs new releases in place and relaunches.

## The pixel promise

BallastViewer **never alters image data**. The only thing it ever writes into an image file is metadata (rating, keywords, orientation in the picker) — the compressed image data is copied byte for byte, patched via temp file and atomic replace. This invariant is enforced by tests that compare the JPEG scan / PNG IDAT bytes before and after every write path. Rotation inside a library doesn't even do that: it only touches the database.

## Installation

1. Download the latest `BallastViewer-*.zip` from [Releases](https://github.com/clubmate/BallastViewer/releases/latest) and unzip it into `/Applications`.
2. First launch: the app is ad-hoc signed, so right-click ▸ Open ▸ Open once to get past Gatekeeper.
3. From then on, **BallastViewer ▸ Check for Updates…** keeps you current — updates installed through the app skip the Gatekeeper dance entirely.

Requires macOS 14 or later.

## Building from source

```bash
git clone https://github.com/clubmate/BallastViewer.git
cd BallastViewer

./scripts/build.sh   # xcodegen generate + xcodebuild → build/Build/Products/Debug/BallastViewer.app
./scripts/test.sh    # swift test for BallastCore (fast, no app build needed)
```

Requirements: Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The `.xcodeproj` is generated from `project.yml`.

## Project layout

| Path | What it is |
|---|---|
| `BallastCore/` | SPM package with all platform-independent logic: models, database (GRDB), query engine, keyword tree, sort/culling rules, MIDI parsing, metadata I/O — fully covered by `swift test`. |
| `App/` | The SwiftUI app: views, view models, services (AppKit/ImageIO/CoreMIDI). |
| `docs/BALLASTVIEW-SPEC.md` | The behavioral contract this app is built against. |
| `docs/PLAN.md` | Roadmap and the documented deviations from the spec. |

Built with Swift 6 (strict concurrency), SwiftUI, and [GRDB](https://github.com/groue/GRDB.swift).
