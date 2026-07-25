# BallastViewer — Complete Functional Specification

| Marker | Meaning |
| --- | --- |
| **[QUIRK]** | Deliberate, non-obvious behaviour. Reproduce it. Users depend on it. |
| **[BUG]** | Defect in the original. Documented so the behaviour is understood, with a recommended fix. Decide per item whether to replicate or repair. |
| **[DEAD]** | Code that exists but never runs, or files never read. Do **not** port. |
| **[PLATFORM]** | Behaviour currently tied to a macOS API. Ported code needs an equivalent; candidates are named. |

**Source references** are given as `File.swift:line` against the original tree at `BALLASTVIEW/BALLASTVIEW/`.

**Requirement language.** MUST / MUST NOT / SHOULD are used in the RFC sense. Statements are phrased as testable assertions so they can be turned directly into acceptance tests.

---

## Table of Contents

1. [Product Summary](#1-product-summary)
2. [Architecture](#2-architecture)
3. [Data Model & JSON Schema](#3-data-model--json-schema)
4. [Library Lifecycle](#4-library-lifecycle)
5. [Import](#5-import)
6. [Metadata I/O](#6-metadata-io)
7. [Smart Collections & Query Engine](#7-smart-collections--query-engine)
8. [Keywords](#8-keywords)
9. [User Interface](#9-user-interface)
10. [Selection & Navigation Model](#10-selection--navigation-model)
11. [Sorting & Search](#11-sorting--search)
12. [Keyboard Shortcuts](#12-keyboard-shortcuts)
13. [MIDI Subsystem](#13-midi-subsystem)
14. [Application Menus](#14-application-menus)
15. [Settings & Persistence Keys](#15-settings--persistence-keys)
16. [Quirks, Bugs & Recommendations](#16-quirks-bugs--recommendations)
17. [Reimplementation Notes](#17-reimplementation-notes)
18. [Acceptance Checklist](#18-acceptance-checklist)

---

## 1. Product Summary

### 1.1 What it is

BALLASTVIEW is a **photo culling and keywording tool**. It is not an editor: it never modifies pixels (this is important! NEVER MODIFY PIXELS!). It manages a *catalogue* of photos that live wherever the user already keeps them, and it lets the user move through them fast, assigning **star ratings (0–5)**, **keywords**, and **rotation** — then optionally writes those three attributes back into the image files themselves.

The mental model is Adobe Lightroom's Library module, reduced to the culling essentials, plus one thing Lightroom does not have: **hardware MIDI control with LED feedback**. The user can wire a pad controller (Launchpad, Akai APC, or any MIDI device) so that physical buttons rate photos and toggle keywords, and the pads *light up* to show the current photo's rating and assigned keywords. This is the app's defining feature and the reason the sandbox requests USB access.

### 1.2 Who it is for

A photographer or picture editor working through hundreds of images in one sitting: culling a shoot, tagging a match-day set, sorting an archive. The design optimises for **keeping both hands on controls and never touching the mouse**: full keyboard remapping, MIDI mapping, a rating-first left sidebar, and rules-based Smart Collections that update live as ratings and keywords change.

### 1.3 The end-to-end workflow

1. **Create a library.** `Library ▸ New Library…` writes a single `.json` file wherever the user chooses. That file *is* the catalogue — there is no hidden database, no package format, no sidecar files.
2. **Add folders.** `Library ▸ Add Folder…` scans a chosen folder for image files, creates a `Photo` record for each new file, and reads existing keywords/rating/orientation out of the file's metadata. Each run of the importer is tagged with an **import batch id** so the user can immediately jump to "what I just added".
3. **Browse.** The centre pane shows either a **grid** (1–10 columns, adjustable live) or a **single large image**. The left sidebar offers ALL PHOTOS, LAST IMPORT, one entry per star rating, and any number of user-defined **Smart Collections** grouped into named sections.
4. **Cull and tag.** Arrow keys (or MIDI pads) move through the set. Number keys `0`–`5` set the rating. Space rotates. Keywords are added in the right panel — with autocomplete over both the keyword tree and every keyword already in use — or bound to a key or MIDI pad for one-press toggling. Every change is written to the library JSON **immediately**; there is no explicit Save.
5. **Filter.** Smart Collections re-evaluate continuously. Rating a photo 5 stars makes it appear in the "5 Stars" list the same instant. Photo counts next to every collection update live.
6. **Pull metadata to disk.** `Library ▸ Load Metadata from Files` does pulling in changes made by other applications.

### 1.4 Explicit non-goals

The app does **not**: edit or develop images; move, copy, rename or delete files on disk; support video; support multiple simultaneously open libraries; sync to any cloud service;

---

## 2. Architecture

### 2.1 Layers

The original is a four-layer SwiftUI/Combine application. The layering is worth preserving in any port because the reactive contract in §2.2 depends on it.

| Layer | Files | Responsibility |
| --- | --- | --- |
| **Models** | `Photo.swift`, `Library.swift` | Plain serialisable value types. No behaviour. |
| **Services** | `LibraryManager.swift`, `LibraryManager+Keywords.swift`, `PersistenceService.swift`, `FileSystemService.swift`, `MetadataService.swift`, `EXIFWriter.swift`, `QueryEngine.swift`, `ShortcutService.swift`, `MIDIService.swift` | All I/O and all rules. `LibraryManager` is the single owner of mutable state. |
| **ViewModels** | `LibraryViewModel.swift`, `LeftPanelViewModel.swift`, `RightPanelViewModel.swift` | Derive presentation state from the library; hold selection, filter, sort. |
| **Views** | `ContentView.swift`, `CenterView.swift`, `LeftPanelView.swift`, `RightPanelView.swift`, `SettingsView.swift`, `KeywordsSettingsView.swift`, `SmartCollectionEditor.swift`, `LibraryCommands.swift`, `PhotoCommands.swift`, `ViewCommands.swift` | Rendering and input only. |
| **Extensions** | `Color+Hex.swift`, `ScrollBarModifier.swift` | Hex↔colour conversion; scrollbar cosmetics. |

Three long-lived service objects are created once at application start and injected into the whole view tree (`BALLASTVIEWApp.swift:12-14`): `LibraryManager`, `ShortcutService`, `MIDIService`. `ShortcutService` and `MIDIService` are **library-independent** — their mappings live in application preferences and survive closing or switching libraries.

### 2.2 The central data-flow contract

This is the single most important architectural fact, and a port that ignores it will behave subtly differently everywhere:

> **The entire `Library` is one value. Every mutation replaces the whole value, republishes it, and rewrites the whole JSON file synchronously.**

Concretely, every mutating operation follows this exact shape (`LibraryManager.swift:217-226` is the canonical example):

```
1. copy currentLibrary into a local mutable value
2. mutate the copy
3. set library.metadata.lastModifiedDate = now
4. assign the copy back to the published currentLibrary
5. call saveCurrentLibrary()  →  encode entire JSON  →  write entire file
```

Consequences the reimplementation MUST be aware of:

- **There is no Save command and no dirty state.** Setting one star on one photo rewrites the complete catalogue file. The app is crash-safe in the sense that nothing is ever unsaved — but see the atomicity **[BUG]** in §16.
- **Every mutation invalidates every derived view.** Publishing `currentLibrary` causes `LibraryViewModel` to re-filter and re-sort all photos, and `LeftPanelViewModel` to recompute the match count of *every* Smart Collection against *every* photo (`LeftPanelViewModel.swift:144-169`). One keystroke therefore costs `O(photos × collections)` plus a full JSON serialise.
- **This is fine at a few thousand photos and collapses beyond that.** §17.4 gives the recommended replacement strategy.
- **Ordering is stable.** Because photos are stored and republished as an array, and appended on import, the array order is the import order. Sorting happens downstream in the view model and never rewrites the stored order.

### 2.3 Who owns what state

| State | Owner | Persisted where | Survives app restart |
| --- | --- | --- | --- |
| Photos, folders, collections, keyword tree | `LibraryManager.currentLibrary` | The library `.json` | Yes |
| Which library is open | `LibraryManager` | `UserDefaults` (security-scoped bookmark) | Yes — reopened automatically |
| Recent libraries (max 10) | `LibraryManager.recentLibraries` | `UserDefaults` | Yes |
| Selected photos, sort order, view mode, search text, column count | `LibraryViewModel` | Nowhere | **No** — resets every launch |
| Selected collection | `LeftPanelViewModel` | `UserDefaults` | Yes |
| Collapsed sidebar groups | `LeftPanelViewModel` | `UserDefaults` | Yes |
| Keyboard map | `ShortcutService` | `UserDefaults` | Yes |
| MIDI map | `MIDIService` | `UserDefaults` | Yes |
| Panel visibility, grid spacing, background colour, MIDI debounce | View-level app storage | `UserDefaults` | Yes |

Note the asymmetry: sort order and view mode are *not* remembered across launches, but the selected collection *is*. Reproduce this exactly — it is what the original does.

### 2.4 Concurrency model

All state mutation happens on the main thread. Three kinds of work are pushed off it:

- **Directory scanning** — one detached task (`FileSystemService.swift:13`).
- **Metadata extraction** — one detached task per file, fanned out through a task group with no concurrency limit (`LibraryManager.swift:233`, `:277`, `:347`). On a large library this starts as many concurrent file reads as there are photos. **[PLATFORM]** A port SHOULD bound this (e.g. 8–16 concurrent reads).
- **Image decoding** — one detached task per thumbnail or full image (`CenterView.swift:277`, `:359`).

Results are always merged back on the main thread, and merges re-look-up photos **by id**, not by index, precisely because the library may have changed while the work was in flight (`LibraryManager.swift:372`).

---

## 3. Data Model & JSON Schema

### 3.1 File format

- One UTF-8 JSON document per library. Default filename offered by the save dialog: `MyLibrary.json`. Extension is enforced as `.json` by the file dialogs but nothing in the loader depends on it.
- Encoded **pretty-printed** (`PersistenceService.swift:15`). Human readability is a stated design goal — the path is stored as a plain string "for JSON readability and strict requirement" (`Photo.swift:5`).
- All dates are **ISO-8601** strings, UTC, second precision: `"2025-12-28T23:29:10Z"` (`PersistenceService.swift:16,18`).
- Key order in the output is unspecified (the original's encoder does not sort keys — real files show `folders` before `metadata` before `photos`). A port MUST NOT depend on key order and SHOULD consider sorting keys for cleaner diffs.
- **[BUG]** The file is written with a plain non-atomic write (`PersistenceService.swift:23`). See §16.

### 3.2 `Library` (root object)

| Field | Type | Required on read | Notes |
| --- | --- | --- | --- |
| `metadata` | `LibraryMetadata` | Yes | See §3.3 |
| `folders` | `[ImportedFolder]` | Yes | May be empty |
| `photos` | `[Photo]` | Yes | May be empty |
| `smartCollectionGroups` | `[SmartCollectionGroup]` | Yes | May be empty |
| `allKeywords` | `[String]` | Yes | Global keyword index, always sorted ascending |
| `keywordDefinitions` | `[KeywordDefinition]` | **No** (optional) | The keyword tree |
| `keywordGroups` | `[KeywordGroupDefinition]` | **No** (optional) | Coloured groups |
| `lastImportId` | `UUID` | **No** (optional) | Batch id of the most recent import |
| `lastImportDate` | date | **No** (optional) | Written but never read by any code path |

The four optional fields were added after v1 shipped. Older files (`MyLibrary.json`, `MyLibrary2.json` in the repo both predate them) load without error. **A reimplementation MUST tolerate all four being absent.**

A newly created library is initialised with empty arrays for the required fields, an empty `keywordDefinitions`, and `keywordGroups` seeded with the **six default groups** in §8.3 (`Library.swift:17-25`).

**[QUIRK] Inconsistent nil-handling of `keywordGroups`.** When the field is absent, `LibraryManager+Keywords.swift` substitutes the six defaults (`:97`, `:107`, `:119`, `:129`), but `LeftPanelViewModel.swift:34` substitutes an empty array. So on an old library the Smart Collection editor's "Keyword Group" dropdown is empty while the Settings ▸ Keywords tab shows six groups. A port SHOULD pick one behaviour — substituting the defaults everywhere is the better one — and note that this changes visible behaviour on legacy files.

### 3.3 `LibraryMetadata`

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `version` | int | `1` | **Never read.** No migration logic exists anywhere in the codebase. |
| `createdDate` | date | now | Set once at creation |
| `lastModifiedDate` | date | now | Updated on nearly every mutation |
| `name` | string | `"My Library"` | **Never displayed.** The UI shows the *filename* instead (`LibraryCommands.swift:10`). |

### 3.4 `Photo`

| Field | Type | Default | Notes |
| --- | --- | --- | --- |
| `id` | UUID | generated | Stable identity for the record; regenerated if the same file is imported into a different library |
| `path` | string | — | **Absolute** POSIX path. This is the de-duplication key. |
| `rating` | int | `0` | 0–5. Nothing clamps values read from file metadata — see §6.2. |
| `keywords` | `[String]` | `[]` | Uppercase by convention; may contain hierarchy paths like `"PEOPLE > ANNA"` |
| `orientation` | int | `1` | EXIF orientation, but only 1/3/6/8 are ever produced by the app |
| `dateAdded` | date | now | Time the record was created, i.e. import time — **not** the file's capture date |
| `importBatchId` | UUID | absent | Groups all photos added by one run of the importer |

**[DEAD]** `Photo.swift:17` carries the comment *"Custom coding keys to stop saving metadata in JSON"*, but the `CodingKeys` enum below it lists every field including `rating`, `keywords` and `orientation`. Metadata **is** persisted. The comment records an abandoned experiment (git `2a0347e` removed persistence, `9b67c57` and later restored it). Ignore the comment; trust the field list.

There is no capture date, no camera/lens, no dimensions, no file size, no hash. Everything the app knows about a photo is in the seven fields above.

### 3.5 `ImportedFolder`

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID | |
| `path` | string | Absolute folder path |
| `dateAdded` | date | |
| `bookmarkData` | base64 blob, optional | **[PLATFORM]** macOS security-scoped bookmark. Sandboxed apps lose filesystem access on relaunch unless they resolve a bookmark captured at the moment the user picked the folder. On a non-sandboxed platform this field is unnecessary — keep the field in the schema for compatibility, ignore it. |

### 3.6 `SmartCollectionGroup` and `SmartCollection`

```
SmartCollectionGroup { id: UUID, name: String, collections: [SmartCollection] }
SmartCollection      { id: UUID, name: String, rules: [CollectionRule], matchAll: Bool }
```

`matchAll` is `true` for AND, `false` for OR. Groups are ordered; collections within a group are ordered; both orders are user-editable by drag and are persisted as array order.

### 3.7 `CollectionRule`

```
CollectionRule { type: RuleType, operation: RuleOperator, value: String }
```

All three are strings in JSON. Every rule value is serialised as a string regardless of semantic type — ratings as `"5"`, dates as a Unix timestamp string, group references as a UUID string. See §7 for the full matrix.

`RuleType` ∈ `keyword`, `keywordGroup`, `rating`, `filename`, `keywordCount`, `dateRange`, `importBatch`
`RuleOperator` ∈ `contains`, `equals`, `greaterThan`, `lessThan`, `doesNotContain`, `doesNotEqual`

Unknown enum values cause the **entire library load to fail** (Swift's `Codable` throws on unknown raw values, and the error is swallowed by `try?` at the call site — the library simply does not open). A port SHOULD instead skip unrecognised rules and log, so a file written by a newer version degrades gracefully.

### 3.8 `KeywordDefinition` and `KeywordGroupDefinition`

```
KeywordGroupDefinition { id: UUID, name: String, color: String }   // color = "#RRGGBB"
KeywordDefinition      { id: UUID, name: String, groupID: UUID, children: [KeywordDefinition] }
```

`keywordDefinitions` is a **flat top-level array whose elements nest arbitrarily deep via `children`**. Group membership is expressed by `groupID` on each node.

**[QUIRK] Only top-level nodes are filtered by group.** The Settings ▸ Keywords tab lists, under each group, the top-level definitions whose `groupID` matches, then renders their entire `children` subtree regardless of the children's own `groupID` (`KeywordsSettingsView.swift:134-146`). A child created through the UI inherits its parent's `groupID` (`:198`), so in practice the tree is homogeneous — but a hand-edited file can contain a child belonging to another group, and it will be displayed under its parent's group while *colouring* itself by its own group (§8.5). Replicate the display rule; do not attempt to "fix" it silently.

### 3.9 Complete example

A minimal but complete file exercising every field:

```json
{
  "metadata": {
    "version": 1,
    "createdDate": "2025-12-28T23:16:05Z",
    "lastModifiedDate": "2026-01-06T00:10:41Z",
    "name": "My Library"
  },
  "folders": [
    {
      "id": "6582402E-5363-479A-A7AE-CE1A80D659C3",
      "path": "/Users/code/Pictures/Match",
      "dateAdded": "2025-12-28T23:29:10Z",
      "bookmarkData": "Ym9va8wCAAAAAAUQQAAAA…"
    }
  ],
  "photos": [
    {
      "id": "5278B4B6-1747-4388-BAC5-D9D6F2E8B44A",
      "path": "/Users/code/Pictures/Match/_auswahl/9417788.jpg",
      "rating": 2,
      "keywords": ["PEOPLE > ANNA", "YEAR > 2025"],
      "orientation": 8,
      "dateAdded": "2025-12-28T23:29:10Z",
      "importBatchId": "0E9A1C22-4F0B-4C1E-9C2F-6B7A9D1E3F44"
    }
  ],
  "smartCollectionGroups": [
    {
      "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "name": "Best Of",
      "collections": [
        {
          "id": "3d813cbb-47fb-42ba-91df-5319909fc2a3",
          "name": "Keepers",
          "matchAll": true,
          "rules": [
            { "type": "rating",  "operation": "greaterThan", "value": "3" },
            { "type": "keyword", "operation": "contains",    "value": "ANNA" }
          ]
        }
      ]
    }
  ],
  "allKeywords": ["PEOPLE > ANNA", "YEAR > 2025"],
  "keywordGroups": [
    { "id": "B1000000-0000-0000-0000-000000000001", "name": "YEAR",   "color": "#007AFF" },
    { "id": "B1000000-0000-0000-0000-000000000003", "name": "PEOPLE", "color": "#BF5AF2" }
  ],
  "keywordDefinitions": [
    {
      "id": "C1000000-0000-0000-0000-000000000001",
      "name": "PEOPLE",
      "groupID": "B1000000-0000-0000-0000-000000000003",
      "children": [
        {
          "id": "C1000000-0000-0000-0000-000000000002",
          "name": "ANNA",
          "groupID": "B1000000-0000-0000-0000-000000000003",
          "children": []
        }
      ]
    }
  ],
  "lastImportId": "0E9A1C22-4F0B-4C1E-9C2F-6B7A9D1E3F44",
  "lastImportDate": "2025-12-28T23:29:10Z"
}
```

**[DEAD]** The repo also contains `BALLASTVIEW/library_example.json`, a hand-written sample from before `orientation` and `importBatchId` existed. **No code reads it.** It is documentation debris — do not port it, and do not treat it as authoritative for the schema.

---

## 4. Library Lifecycle

### 4.1 Creating a library

`Library ▸ New Library…` (`⇧⌘N`) opens a save dialog titled *"Create New Library"*, restricted to JSON, pre-filled with `MyLibrary.json` (`LibraryCommands.swift:83-93`).

On confirmation the app MUST: construct an empty `Library` (§3.2 defaults, including the six default keyword groups), write it to the chosen path, then immediately open it. If the write fails the error is swallowed and **nothing visible happens** — no alert, no state change. A port SHOULD surface the error.

### 4.2 Opening a library

`Library ▸ Open Library…` (`⇧⌘O`) opens a single-selection JSON open dialog.

Loading sequence (`LibraryManager.swift:58-93`):
1. Release access to the previously open library file.
2. Acquire access to the new one. **[PLATFORM]** macOS security scope.
3. Decode the JSON. **On any decode failure, access is released and the error is thrown** — and the caller discards it, so a corrupt file silently does nothing. A port SHOULD show an error.
4. On success: set current library and URL, persist "last opened" for auto-reopen, push onto the recents list, and re-acquire access to every imported folder by resolving its stored bookmark.

**[DEAD]** A metadata re-sync at open time exists but is commented out (`LibraryManager.swift:79-84`). The comment states why: *"Removed automatic sync to respect offline edits and manual sync workflow."* Metadata refresh is user-initiated only (§6.4). **Do not port an auto-sync at open** — it would silently overwrite in-app edits with whatever is on disk.

### 4.3 Auto-reopen at launch

At construction, `LibraryManager` loads the recents list and then attempts to reopen the last library (`LibraryManager.swift:48-49`, `:490-497`). Failure is silent, leaving the app in the empty state. A port MUST reopen the last library at start-up.

### 4.4 Closing a library

`Library ▸ Close Library` (visible only when a library is open) releases access to every folder and to the library file, clears current library and URL, and **removes the "last opened" preference** so the next launch starts empty (`LibraryManager.swift:95-106`). It does *not* clear the recents list.

### 4.5 Recent libraries

- Maximum **10** entries, most recent first (`LibraryManager.swift:513`).
- Opening a library that is already in the list moves it to the front rather than duplicating it (matched by path).
- Rendered under `Library ▸ Open Recent` showing each entry's filename, with a trailing `Clear Menu` item when non-empty.
- **[PLATFORM]** Persisted as an array of security-scoped bookmarks, resolved back to paths at launch. Entries that no longer resolve are dropped silently.

### 4.6 Empty state

With no library open, the window centres two lines of text (`ContentView.swift:19-26`):

```
No Library Loaded                       (title font)
Use File > New Library or Open Library  (secondary colour)
```

**[BUG]** The message says *File* but the menu is called *Library*. Fix the wording.

### 4.7 Global alert channel

`LibraryManager` exposes `alertMessage` / `showAlert`, rendered by `ContentView.swift:29-33` as an alert titled **"Metadata Sync"** with a single OK button. It is used only by the two metadata sync commands (§6.4). Any port keeping this channel should note the title is hard-coded regardless of message.

---

## 5. Import

### 5.1 The command

`Library ▸ Add Folder…` (`⇧⌘I`, disabled when no library is open) opens a folder-picker that allows **multiple selection**; each chosen folder is imported sequentially (`LibraryCommands.swift:108-124`).

### 5.2 Folder registration

A folder is added to `library.folders` only if no existing entry has the identical `path` string (`LibraryManager.swift:142`). Re-adding an already-registered folder skips registration but **still runs the scan**, which is how the user rescans a folder for new files.

**[PLATFORM]** On registration the app captures a security-scoped bookmark and begins accessing the folder immediately.

### 5.3 Scanning

`FileSystemService.scanDirectory` (`FileSystemService.swift:12-46`):

- **Non-recursive.** It lists the folder's direct contents only. **[BUG]** — see §16. Subfolders are silently ignored, so importing a shoot organised into subfolders yields zero photos with no error. Git `8595a3f` deliberately changed this from a recursive enumerator; the reason is not recorded. **Recommendation: make it recursive, or add an explicit "include subfolders" toggle.**
- Skips hidden files and package descendants.
- Accepts only regular files whose lowercased extension is in this set (`FileSystemService.swift:10`):

  `jpg`, `jpeg`, `png`, `heic`, `tiff`, `tif`, `raw`, `cr2`, `nef`, `arw`, `dng`

  Note the RAW formats are listed but the app has no RAW-specific handling — it relies entirely on the OS image framework to decode them. `webp`, `gif`, `bmp`, `avif` and Fuji/Olympus/Panasonic RAW (`raf`, `orf`, `rw2`) are **not** accepted.
- Per-file errors are swallowed and the file skipped.

### 5.4 Creating records

For the whole `Add Folder` invocation, **one** `importBatchId` UUID is generated (`LibraryManager.swift:164`). Then for each scanned file:

1. If any existing photo has the identical absolute `path`, skip it entirely. **Deduplication is by exact path string** — the same file reachable via a symlink or a different case counts as a different photo.
2. Otherwise create a `Photo` with a fresh id, the absolute path, `dateAdded = now`, and the batch id.
3. Read keywords, rating and orientation out of the file (§6.1) and store them on the record. If extraction fails, the record keeps its defaults (`rating 0`, no keywords, `orientation 1`).

Afterwards, if at least one photo was created: append them, set `lastImportId` and `lastImportDate`. **[QUIRK]** When a scan finds nothing new, `lastImportId` is left pointing at the *previous* batch — so LAST IMPORT keeps showing the older set rather than going empty. This is the desirable behaviour; keep it.

Finally the global keyword index is updated as `sorted(set(existing ∪ all keywords of new photos))`, `lastModifiedDate` is stamped, and the library is saved.

### 5.5 Removing a folder

`Library ▸ Remove Folder ▸ <path>` (a submenu listing every registered folder by full path) removes the folder record **and every photo whose path starts with the folder's path** (`LibraryManager.swift:207`).

**[BUG] Prefix matching without a separator.** Removing `/Photos/Trip` also deletes photos under `/Photos/Trip2024`. **Fix: compare against `folderPath + "/"`, or compare path components.**

There is **no confirmation dialog** — one menu click destroys catalogue records for potentially thousands of photos, with no undo. The files on disk are untouched, and the ratings/keywords survive only if they were previously written into the files. A port SHOULD add a confirmation showing the affected count.

---

## 6. Metadata I/O

This is the area with the most subtlety, and the area where the original is internally inconsistent. Read §6.3 carefully.

### 6.1 Reading (`MetadataService.swift`)

For a given file the app reads exactly three things (`MetadataService.swift:15-49`):

| Attribute | Source |
| --- | --- |
| Orientation | Top-level image property `Orientation`; default `1` if absent |
| Keywords | **IPTC** `Keywords` — accepted as either an array of strings or a single string |
| Rating | **IPTC** `StarRating` — integer; default `0` |

Keywords are then normalised: **uppercased, de-duplicated, sorted ascending** (`MetadataService.swift:46`). This is why the whole app is uppercase-centric.

If the file cannot be opened or has no properties, the result is `(keywords: [], rating: 0, orientation: 1)` — an *empty success*, not an error. **[QUIRK]** This matters: an unreadable file looks exactly like a file with no metadata, so a sync can wipe in-app data if the reader is the authority (see §6.4).

**[PLATFORM]** Original uses ImageIO (`CGImageSourceCopyPropertiesAtIndex`). Ports need any library that reads EXIF/IPTC/XMP — ExifTool (most complete), `exiv2`, `libexif`, Python `Pillow` + `piexif`, Node `exifr`/`sharp`.

### 6.2 Writing (`EXIFWriter.swift`)

Writing is intentionally **lossless** — the image data is copied byte-for-byte and only the metadata block is rewritten (`EXIFWriter.swift:35-65`). The app never recompresses.

Sequence:
1. Open the source image; abort if the file type cannot be determined.
2. Create a destination in the system temp directory with a random UUID name and the source's extension.
3. Build a metadata patch with exactly three entries:
   - `tiff:Orientation` ← the photo's orientation
   - `xmp:Rating` ← the photo's rating
   - `dc:subject` ← the photo's keyword array
4. Copy source → destination in **merge mode**, so all other existing metadata is preserved.
5. Atomically replace the original file with the temp file. On failure, delete the temp file and propagate the error.

Note that keywords are written **verbatim** — no uppercasing, no sorting, no de-duplication on the write side. The values are already uppercase in practice because they entered the library through the reader or through the uppercase-forcing input field (§8.4).

### 6.3 **[BUG] The read and write paths do not use the same schema**

| Attribute | Written to | Read from | Round-trips? |
| --- | --- | --- | --- |
| Orientation | `tiff:Orientation` | top-level `Orientation` | Yes |
| Keywords | `dc:subject` (XMP) | IPTC `Keywords` | **Only if the imaging library mirrors XMP→IPTC** |
| Rating | `xmp:Rating` (XMP) | IPTC `StarRating` | **Frequently not** |

The writer's comment claims *"ImageIO automatically syncs XMP changes to legacy IPTC/Exif where possible"* (`EXIFWriter.swift:36-37`). That mirroring is format-dependent and not guaranteed. The practical failure mode:

> Rate a photo 5 → `Save Metadata into Files` → `Load Metadata from Files` → **the rating reverts to 0**, and because the loader is authoritative, the library's 5 is destroyed.

`xmp:Rating` is what Lightroom, Bridge and Capture One actually use, so the *writer* is the correct half. **Recommended fix: read `xmp:Rating` first, fall back to IPTC `StarRating`; read `dc:subject` first, fall back to IPTC `Keywords`. Keep writing XMP.** This preserves interoperability with the rest of the industry and closes the data-loss hole.

Also note `rating` is never clamped on the read path. A file carrying `StarRating: 7` produces a photo with rating 7, which renders as five filled stars and matches `rating greaterThan 5`. Clamp to 0…5 on read.

### 6.4 The two manual sync commands

Both live under the `Library` menu, both are disabled without an open library, both process **every photo in the library** (not the selection, not the current collection), both fan out one concurrent task per photo, and both end by showing the alert **"Updated N files."** — with the same wording for opposite directions, which is confusing (`LibraryManager.swift:266`, `:320`).

**`Save Metadata into Files`** (`LibraryManager.swift:229-268`)
For each photo: read the file's current metadata; if orientation, rating, or the keyword *set* differs from the library, write the library's values into the file. Files already in sync are skipped, so repeated runs are cheap. **[QUIRK]** If a file cannot be read, it is skipped rather than written — so a file with damaged metadata can never be repaired by this command. Counter counts files actually written.

**`Load Metadata from Files`** (`LibraryManager.swift:271-322`)
For each photo: read the file; if anything differs, **overwrite the library's values with the file's**. The file always wins. Then:

**[BUG]** The global keyword index is rebuilt as `sorted(set(keywords of all photos))` (`LibraryManager.swift:312-313`) — which **discards every keyword that exists in the library but is not currently assigned to a photo**. A user who prepared a vocabulary in advance loses it on the first sync. **Fix: union with the existing `allKeywords` instead of replacing it.** (`addFolder` does this correctly at `:191` — the two paths simply disagree.)

**[QUIRK]** Comparison uses `Set` for keywords in `Save` (order-insensitive) but plain array `!=` in `Load` (`:300` uses sets, `:376` in the lazy path uses arrays). The lazy path therefore reports a change when only the order differs. Harmless but worth normalising.

### 6.5 Lazy metadata refresh

`loadMetadata(for: Set<UUID>)` (`LibraryManager.swift:338-405`) refreshes a subset of photos from disk and merges by id. **[DEAD]** in effect: *nothing in the shipped UI calls it.* The function is fully implemented and correct; it was built for "refresh metadata when photos are selected" and never wired up. A port may implement selection-triggered refresh deliberately — but be aware the original does **not** do it, so in the original, external changes to files are invisible until the user runs the explicit Load command.

### 6.6 Rotation semantics

Rotation is a **library-only** operation until metadata is written. Pressing rotate advances the stored orientation through the cycle:

```
1 (normal) → 6 (90° CW) → 3 (180°) → 8 (90° CCW) → 1 …
```

Any other stored value jumps to `6` (`LibraryViewModel.swift:262-269`). Values 2, 4, 5, 7 (the mirrored EXIF orientations) are therefore read from files, honoured for display, but destroyed by the first rotation.

Because the file is untouched, rotation is instant and non-destructive; it reaches disk only via `Save Metadata into Files`.

**[QUIRK] Display honours the stored orientation, not the file's.** Both the thumbnail loader and the full-size loader explicitly request **no** automatic EXIF transform and then rotate the decoded bitmap themselves according to `photo.orientation` (`CenterView.swift:280`, `:287`, `:363`). This is what makes rotation appear instantly. A port MUST do the same — decode unrotated, rotate by the stored value — or rotation will appear to do nothing until the file is rewritten.

---

## 7. Smart Collections & Query Engine

### 7.1 Concept

A **Smart Collection** is a saved filter: a name, a list of rules, and a match mode. It contains no photo references. Membership is recomputed from scratch every time the library changes, so a photo appears and disappears live as it is rated or tagged.

Collections are organised into **groups** — named, collapsible, reorderable sections in the left sidebar. A collection belongs to exactly one group. Groups have no rules of their own; they are purely organisational.

### 7.2 Evaluation (`QueryEngine.swift`)

```
matches(photo, collection):
    if collection.rules is empty        → true
    if collection.matchAll              → every rule must match
    else                                → at least one rule must match
```

**[QUIRK] An empty rule list matches everything** (`QueryEngine.swift:5-7`). A freshly created collection has no rules, so it immediately shows the entire library. This is deliberate — it lets the user create the collection, see all photos, and narrow down. Keep it, but consider showing a hint in the UI.

The engine is pure and stateless. It receives the whole `Library` as an optional second argument, needed only by the `keywordGroup` rule to resolve group membership; when absent, that rule returns `false`.

### 7.3 Rule matrix

This table is the complete contract. Any operator not listed for a type returns **`false`** (not an error, not "match everything").

| Type | `value` encoding | Supported operators | Semantics |
| --- | --- | --- | --- |
| `keyword` | plain string | `contains`, `equals`, `doesNotContain`, `doesNotEqual` | Case-insensitive. `contains` = *any* keyword contains the substring. `equals` = *any* keyword equals it exactly. The negatives are the exact logical negations. |
| `rating` | integer as string | `equals`, `greaterThan`, `lessThan` | Strict comparison against `photo.rating`. Non-numeric value → no match. |
| `filename` | plain string | `contains`, `equals`, `doesNotContain`, `doesNotEqual` | Case-insensitive, against the **last path component only** (`IMG_0042.JPG`), including extension. |
| `keywordCount` | integer as string | `equals`, `greaterThan`, `lessThan` | Against `photo.keywords.count`. Enables "untagged photos" as `keywordCount equals 0`. |
| `keywordGroup` | group **UUID** as string | `doesNotContain` / `doesNotEqual` → negated; **all others → positive** | True when the photo carries at least one keyword belonging to the named group. |
| `dateRange` | Unix timestamp (seconds) as string | `greaterThan`, `lessThan` | Compares `photo.dateAdded` — i.e. *import* time, not capture time. |
| `importBatch` | batch **UUID** as string | any (operator ignored) | True when `photo.importBatchId` equals the value. |

Two notes on the negative operators:

- For `rating` and `keywordCount`, `doesNotEqual` is **not supported** and silently returns `false`. Under AND this makes the collection empty; under OR it is a no-op. The editor UI never offers these combinations, so it is only reachable via a hand-edited file. **Recommendation: implement them.**
- For `keywordGroup`, the operator check is inverted-by-exception: only `doesNotContain` and `doesNotEqual` negate; `contains`, `equals`, `greaterThan` and `lessThan` all behave as plain "has a keyword in this group".

### 7.4 **[BUG] `keywordGroup` fails on hierarchical keywords**

`collectKeywords` gathers the bare `name` of every definition in the group, lowercased (`QueryEngine.swift:83-92`), and intersects with the photo's lowercased keywords. But photos store **resolved paths** — the keyword input resolves `"ANNA"` to `"PEOPLE > ANNA"` before assigning it (§8.4). `"people > anna"` is not in `{"people", "anna"}`, so the intersection is empty and the rule never matches.

The rule only works for keywords that are top-level definitions with no ancestors *and* were assigned by their bare name.

**Fix:** compare against the resolved path of each definition (reuse the same path-building logic as §8.2), or normalise the photo's keywords to their leaf component before intersecting. The first is correct; the second is lossier but simpler.

### 7.5 Built-in pseudo-collections

The left sidebar shows six entries that look like Smart Collections but are synthesised in code (`LeftPanelViewModel.swift:89-142`). Their ids are **hard-coded constants** so that the "last selected collection" preference survives restarts. A reimplementation MUST use these same UUIDs if it wants to read an existing installation's preference.

| Sidebar entry | UUID | Synthesised rule |
| --- | --- | --- |
| ALL PHOTOS | `3d4895d4-1de7-4909-98a3-bbdf184e6159` | none — sets the active filter to `nil` |
| LAST IMPORT | `38e90349-a6ea-4357-8f2e-abf4af80b99d` | `importBatch equals <library.lastImportId>` |
| ★ (1 star) | `b396fdbe-5581-4d45-922c-c79e31ff84a0` | `rating equals 1` |
| ★★ | `24fbefdc-6d57-418c-bc41-081488cbba94` | `rating equals 2` |
| ★★★ | `7c0b22f0-c393-4649-94d3-7dcb4edc0424` | `rating equals 3` |
| ★★★★ | `a2c116a0-021f-4475-9027-2f481ece826a` | `rating equals 4` |
| ★★★★★ | `da9ada91-5311-48c3-8be0-26f46e16829a` | `rating equals 5` |

Note the star filters are **exact match**, not "N or more". The sidebar counts match: the count next to ★★★ is the number of photos rated exactly 3 (`LeftPanelViewModel.swift:154-161`).

**[QUIRK] The empty-LAST-IMPORT hack.** When the library has never been imported into, `lastImportId` is absent, and the code synthesises a deliberately unsatisfiable rule — `keyword equals "___impossible___"` — so the list renders empty rather than showing everything (`LeftPanelViewModel.swift:114-120`). This exists because of the empty-rules-match-all behaviour in §7.2. A port with a proper "match nothing" primitive should use that instead, but the observable behaviour must be identical: LAST IMPORT is empty before the first import.

Selecting ALL PHOTOS sets the active collection to `nil`, which the filter treats as "no filtering" — it does not build an all-matching rule.

### 7.6 Live counts

Every published change to the library recomputes the match count of **every** collection in **every** group against **every** photo, plus the five rating counts and the last-import count (`LeftPanelViewModel.swift:144-169`). Counts are rendered as pill badges in the sidebar.

ALL PHOTOS shows `library.photos.count`. Rating rows show a badge only when a count exists for that rating (always, in practice). Smart Collections show a badge only when their id is present in the count dictionary.

### 7.7 Managing collections and groups

All operations write straight through to the library and save (`LeftPanelViewModel.swift:171-245`).

| Action | Trigger | Behaviour |
| --- | --- | --- |
| New group | Folder+ button at the bottom of the sidebar | Text-field alert titled *"New Group"*. Appends to the end. **No name validation** — empty names and duplicates are accepted. |
| Rename group | Right-click ▸ *Rename Group* | Alert pre-filled with the current name. |
| Delete group | Right-click ▸ *Delete Group* (destructive style) | **No confirmation.** Deletes the group and all its collections. |
| Reorder groups | Drag a group header onto another | Live reorder while dragging (`LeftPanelView.swift:262-276`). |
| New collection | `+` button in a group header (visible only when the group is expanded) | Alert titled *"New Smart Collection"*. Creates it with **no rules and `matchAll = true`**, then auto-selects it — so it immediately shows the whole library (§7.2). |
| Edit collection | Right-click ▸ *Edit Smart Collection* | Opens the rule editor sheet (§9.7). |
| Delete collection | Right-click ▸ *Delete* | **No confirmation.** Clears the selection if the deleted collection was active. |
| Reorder collections | Drag within a group | Moves within the group only; there is no drag-between-groups. |
| Collapse group | Click the group header | Collapsing hides the collections **and** the group's `+` button. Persisted (§15). |

**[QUIRK]** Saving an edited collection that is currently active immediately re-applies it to the photo list (`LeftPanelViewModel.swift:242-244`), so the grid updates the moment the sheet closes.

---

## 8. Keywords

Keywords are the app's richest subsystem: a **controlled vocabulary** (an editable tree with coloured groups) layered on top of **free-text tagging** (anything the user types is accepted).

### 8.1 The two keyword stores

| Store | Field | What it holds |
| --- | --- | --- |
| **Vocabulary** | `library.keywordDefinitions` | The curated tree. Nodes have identity, a group, and children. Editing lives in Settings ▸ Keywords. |
| **Index** | `library.allKeywords` | A flat, sorted, de-duplicated list of every keyword string that has ever been used or added. Drives autocomplete. |

A photo's `keywords` array holds plain strings. There is **no reference** from a photo to a `KeywordDefinition` — the link is purely by string matching. Renaming a definition therefore does **not** rename it on the photos that carry it. This is a significant limitation; see §16.

Autocomplete draws on the **union** of the flattened vocabulary paths and the index (`RightPanelViewModel.swift:41-45`).

### 8.2 Path notation

A nested keyword is rendered and stored as its ancestors joined by `" > "` (space, greater-than, space), **uppercased**:

```
PEOPLE > TEAM > ANNA
```

Two path builders exist and differ:
- `getFullPath(for: UUID)` preserves each node's stored case (`LibraryManager+Keywords.swift:164-175`) — **[DEAD]**, no caller.
- `flattenKeywords` uppercases every component (`:182-194`) — this is the one that feeds autocomplete, and it emits **every node, not just leaves**, so `PEOPLE`, `PEOPLE > TEAM` and `PEOPLE > TEAM > ANNA` are all offered as assignable keywords.

### 8.3 Groups

A group is a name plus a hex colour. Six are seeded into every new library (`Library.swift:35-44`); their UUIDs are generated per library, not fixed:

| Name | Colour |
| --- | --- |
| YEAR | `#007AFF` |
| META | `#34C759` |
| PEOPLE | `#BF5AF2` |
| LOCATION | `#FF3B30` |
| EVENT | `#AF52DE` |
| MISC | `#FF9500` |

Group **order matters** — it determines the sort priority of keyword chips in the right panel (§8.5). Order is user-editable by drag in Settings ▸ Keywords.

The colour picker offers a fixed nine-colour palette (`KeywordsSettingsView.swift:297`): `#FF3B30`, `#FF9500`, `#FFCC00`, `#4CD964`, `#5AC8FA`, `#007AFF`, `#5856D6`, `#FF2D55`, `#8E8E93`. Arbitrary colours cannot be chosen for groups (unlike the canvas background, which uses a full colour picker).

**[BUG] Deleting a group orphans its keywords.** `removeKeywordGroup` deletes only the group (`LibraryManager+Keywords.swift:117-125`). Every definition keeps a `groupID` pointing at nothing: the definitions vanish from Settings (nothing lists them), their chips lose their colour, and any `keywordGroup` rule referencing the dead id silently matches nothing — yet the data remains in the JSON forever. **Fix: on delete, either reassign the definitions to a fallback group or delete them, and warn if any Smart Collection rule references the group.**

### 8.4 Assigning keywords to photos

Entry point is the **ADD KEYWORD** field at the top of the right panel. Behaviour (`RightPanelViewModel.swift:145-163`, `RightPanelView.swift:27-42`):

1. Every keystroke is **forced to uppercase** in the field itself (`RightPanelView.swift:31`). The user cannot type lowercase.
2. Typed text filters the autocomplete list (case-insensitive substring over the union list).
3. On commit, the raw text is trimmed. Empty → no-op.
4. **Path resolution:** the text is looked up by name (case-insensitive) across the entire vocabulary tree, depth-first, and **replaced by the full path of the first match**. `"ANNA"` becomes `"PEOPLE > TEAM > ANNA"`. If there is no match, the text is used **uppercased** as-is (`LibraryManager+Keywords.swift:145-149`).
   - **[QUIRK]** First-match-wins: if two branches contain a node named `ANNA`, the user cannot express which one they meant by typing. Depth-first order over the stored (name-sorted) tree decides.
5. If the resolved string is not already in the index, it is appended to `allKeywords` and the list re-sorted.
6. If it is not already assigned to the selection, it is assigned.

Assignment applies to **all selected photos** (`RightPanelViewModel.swift:113-143`). Each photo's keywords are treated as a set, then written back **sorted ascending**. So the stored order of a photo's keywords is always alphabetical after any edit through the panel — but *not* after a MIDI/keyboard toggle, which appends (`LibraryViewModel.swift:328`). **[QUIRK]** Two code paths, two ordering behaviours; both are functionally equivalent since order is never semantically meaningful.

**Removal** is the same toggle: clicking the `✕` on a chip, or pressing the bound key/pad again, removes it from all selected photos. Removing a keyword does **not** remove it from `allKeywords` — the vocabulary only grows. There is no UI anywhere to delete an entry from the index.

### 8.5 Displaying assigned keywords

The right panel shows the keywords **common to all selected photos** — the set intersection, not the union (`RightPanelViewModel.swift:98-109`). With a mixed selection, a keyword on only some photos is invisible; toggling a visible one affects everything selected.

Chips are ordered by (`RightPanelViewModel.swift:188-207`):
1. the index of the keyword's group in `library.keywordGroups` (ascending), with ungrouped keywords sorted last (priority 999);
2. then alphabetically.

A chip's colour is its group's colour; ungrouped keywords render in the secondary/grey colour (`RightPanelViewModel.swift:180-186`).

Group lookup walks the path: the string is split on `" > "`, the tree is descended component by component (case-insensitive), and the **leaf node's** `groupID` is used (`LibraryManager+Keywords.swift:196-232`). So a nested keyword takes its colour from its own group, which may differ from its parent's.

**[DEAD]** `getKeywordGroup` contains a nonsensical conditional cast (`LibraryManager+Keywords.swift:205`) whose two branches do the same thing. Simplify on port.

### 8.6 Editing the vocabulary — Settings ▸ Keywords

A tree editor (`KeywordsSettingsView.swift`):

- Each group renders as a disclosure row: `NAME (n)` in bold, where **n counts only the group's top-level definitions**, not the whole subtree; a colour dot that opens the nine-colour popover; and a `+` button adding a keyword to the group. All groups start expanded.
- Right-click a group: *Rename* (opens the group sheet: name field, colour palette, preview dot — 300×380) · *Delete Group*.
- Double-click the group name also opens the edit sheet.
- Keywords render as an outline tree. Right-click a keyword: *Rename* (a text alert) · *Add Sub-keyword* · *Delete*. Double-click renames.
- New nodes are created named **`"New Keyword"`** / **`"New Sub-Keyword"`**, saved immediately, and then the rename dialog opens after a 100 ms delay (`KeywordsSettingsView.swift:185-204`). **[QUIRK]** Cancelling that dialog leaves a node literally named "New Keyword" in the library.
- Deleting a node deletes its entire subtree (`LibraryManager+Keywords.swift:54-69`).
- Siblings are kept **sorted by name** on every insert (`:20`, `:34`); the user cannot impose a custom order on keywords (unlike groups, which are drag-ordered).

None of these operations touch photos: renaming `ANNA` does not update the 400 photos tagged `PEOPLE > ANNA`, which keep the stale string and lose their colour. See §16 for the recommended fix.

---

## 9. User Interface

### 9.1 Window and overall layout

- Minimum window size **800 × 600** (`ContentView.swift:28`).
- Three horizontally resizable panes in a split view (`ContentView.swift:54-92`):

```
┌────────────┬───────────────────────────────┬─────────────┐
│ Left panel │         Centre                │ Right panel │
│ 200–300 px │         min 400 px            │ 250–350 px  │
│            │                               │             │
│ collections│   grid  /  single image       │ metadata    │
│            ├───────────────────────────────┤ keywords    │
│            │  bottom bar (mode, tools)     │ actions     │
└────────────┴───────────────────────────────┴─────────────┘
```

- Each side panel can be hidden. When visible, a small chevron **handle** sits on the panel's inner edge; when hidden, the handle sits on the corresponding edge of the centre pane so the panel can be brought back (`ContentView.swift:56-91`, `:147-191`). The handle is a 12 × 32 capsule inside a 20 × 44 hit area, with an 8 pt bold chevron; the capsule background is invisible until hover.
- Panel visibility is persisted and also toggleable from the View menu and by shortcut (§12, §14).

### 9.2 Left panel — collections sidebar

A single flat list (`LeftPanelView.swift`), rendered in this order:

1. Section label **`LIBRARY`** (caption, semibold, secondary colour).
2. **`ALL PHOTOS`** + count badge.
3. **`LAST IMPORT`** + count badge.
4. Five rating rows, **descending from ★★★★★ to ★** (`LeftPanelView.swift:79`), each drawn as *n* filled star glyphs at caption-2 size, plus count badge.
5. One block per user group: a header row (group name, caption, semibold, secondary; plus a `+` button when expanded), then its collections.
6. A footer bar with a single *new group* button (folder-badge-plus icon).

Row metrics: min height 30, 5 px horizontal padding, `EdgeInsets()` row insets (i.e. flush), separators hidden throughout.

**Selection styling:** the selected row's background is the accent colour, its text turns white, and its count badge becomes white-at-20 %-opacity with white-at-80 % text. Unselected badges are secondary-at-20 % with secondary text.

Group headers are click-to-collapse with animation. Collapsed groups hide their collections *and* their `+` button.

**[PLATFORM]** Reordering groups uses drag-and-drop carrying the group's UUID as plain text, with reordering performed live in `dropEntered` rather than on drop (`LeftPanelView.swift:242-277`). A port can use any equivalent; the visible behaviour is that rows shuffle under the cursor as you drag.

### 9.3 Centre — grid view

- A lazy vertical grid of **N equal flexible columns**, N from the column slider (1–10, default 5) (`CenterView.swift:178-234`).
- Cell size is computed as `(width − 2×spacing − (N−1)×spacing) / N`, floored at 10 px. **The same spacing value is used for both inter-item gaps and the outer padding**, so the layout stays visually uniform (`CenterView.swift:186-189`).
- Cells are **square** (`aspectRatio(1)`), and images fill the square with `contentMode: .fill`, **top-aligned**, clipped (`CenterView.swift:247-255`). Portrait photos are therefore cropped at the bottom, landscape photos cropped left/right — deliberate, so faces near the top stay visible.
- The selected cell gets a 3 pt accent-coloured rounded border (radius 4). There is no shadow, no filename, no rating overlay, no badge of any kind in the grid. **The grid shows pixels only.**
- Thumbnails are requested at **2× the cell size** in the longest dimension, decoded on a background task, and re-decoded whenever the cell size or the photo's orientation changes (`CenterView.swift:261-291`). While loading, the cell is transparent — no placeholder, no spinner.
- **There is no thumbnail cache.** Scrolling back re-decodes. **[PLATFORM]** Any port should add an LRU cache; the original's omission is a performance defect, not a design choice worth preserving.
- Selection changes scroll the grid to the selected item with animation (`CenterView.swift:224-229`).

**Mouse interaction** (`CenterView.swift:201-215`):

| Gesture | Result |
| --- | --- |
| Click | Select only this photo |
| Shift-click | Select the range from the anchor to this photo |
| Cmd-click | Toggle this photo in/out of the selection |
| Double-click | Switch to single view (after a 50 ms delay) |

### 9.4 Centre — single view

Shows the currently selected photo scaled to **fit**, centred, at its natural size limit (`CenterView.swift:294-319`). A spinner shows while decoding; a red warning triangle shows on failure. If nothing is selected: *"No Photo Selected"* in secondary colour.

The full image is decoded at full resolution every time the photo changes — no downsampling to the view size, no cache. On large RAW files this is slow. See §17.

### 9.5 Centre — empty state and background

When the filtered set is empty, the centre shows a standard empty-state block: photo icon, **"No Photos Found"**, and *"No photos match the current selection."* (`CenterView.swift:18-35`).

The centre background is a **user-configurable colour**, default `#1E1E1E` (dark grey), set in Settings ▸ Appearance with a full colour picker (`CenterView.swift:10`, `:48`).

### 9.6 Centre — bottom bar

Hidden when the bottom panel is toggled off. Contents depend on the view mode (`CenterView.swift:65-118`):

**Always:** a segmented control switching grid ⟷ single (icons: 2×2 grid, rectangle).

**In grid mode, additionally:**
- A **search field** (200 px) with autocomplete over all keywords (§11.3).
- A **column slider**, range 1–10, step 1, width 150.
- A **sort picker** with the four options of §11.1.

**In single mode, additionally:**
- A right-aligned position indicator `"<index+1> / <total>"` in monospaced digits, secondary colour.

Bar padding is 8 px, background is the system control colour, and it sits above the content in z-order.

### 9.7 Smart Collection editor (sheet)

Minimum 500 × 400 (`SmartCollectionEditor.swift:67`). Layout:

- **Name** — labelled text field.
- **Match** — segmented control *All* / *Any* (bound to `matchAll`).
- **Rule list** — one row per rule, swipe/menu-deletable.
- **Footer** — *Add Rule* (`+`), spacer, *Cancel* (bound to Escape), *Save* (bound to Return, default button).

Each rule row is three controls (`SmartCollectionEditor.swift:71-121`):

1. **Type picker, 130 px** — offering exactly five of the seven types: `Keyword`, `Keyword Group`, `Rating`, `Filename`, `Keyword Count`. **[DEAD]** `dateRange` and `importBatch` are implemented in the engine but **not selectable in the UI**; `importBatch` is used only internally for LAST IMPORT. A port may expose them (a date rule is genuinely useful) — noting that `dateRange` compares *import* date.
2. **Operator picker, 120 px** — contents depend on the type: for `rating` and `keywordCount` it offers *Equals* / *Is Bigger* / *Is Lower*; otherwise *Contains* / *Equals* / *Does Not Contain* / *Does Not Equal*. Changing the type resets the operator to `equals` (numeric types) or `contains` (others), so a rule can never be left in an unsupported combination through the UI.
3. **Value control** — a five-star clickable rating widget for `rating`; a group dropdown (with a *"Select Group…"* empty entry) for `keywordGroup`; a plain text field otherwise.

New rules default to `keyword contains ""` — which matches every photo, since every string contains the empty string.

**[QUIRK]** The star widget cannot express **zero**: it sets values 1–5 only (`SmartCollectionEditor.swift:132-137`). `rating equals 0` (unrated photos) cannot be built in the UI; the user must use `rating lessThan 1`.

**[QUIRK]** The sheet edits a **copy**. Cancel discards; Save writes back through a wrapper (`LeftPanelView.swift:206-225`). Rules deleted and re-added are not undoable within the sheet.

### 9.8 Right panel — metadata and keywords

Top to bottom (`RightPanelView.swift:9-168`):

1. **Filename**, title font, selectable text. With no selection: *"No Selection"*. With multiple: *"N Photos Selected"* (`RightPanelViewModel.swift:76-96`).
2. **Rating** — five tappable stars, title-2 size, filled+yellow up to the current rating, otherwise outline+secondary. **Tapping the star that equals the current rating clears the rating to 0** (`RightPanelView.swift:289`) — that is the only mouse route to "unrated".
   With a multi-selection, the displayed rating is the shared value if all selected photos agree, otherwise **0** (`RightPanelViewModel.swift:89-95`). **[QUIRK]** A mixed selection therefore looks unrated; the user cannot tell "unrated" from "mixed".
3. **ADD KEYWORD field** with a `+` button (disabled while empty), inside a rounded 8 px container with a subtle border. The autocomplete dropdown overlays *below* the field (offset 45 px), height `min(count × 35, 150)`, translucent material background, rounded, shadowed.
4. **Assigned keyword chips**, one per row, full width, in the order of §8.5. Each chip: title-3 text, `✕` button, background = group colour at 20 % opacity, 1 pt border in the group colour, radius 8. With none assigned: *"No keywords assigned"* in italic caption, secondary colour.
5. **Footer bar** with two icon buttons, right-aligned: **Reveal in Finder** (folder icon; acts on the **first** selected photo only) and **Share** (system share sheet with all selected photos). Both disabled with an empty selection.

**Autocomplete keyboard control** (`RightPanelView.swift:345-392`, `RightPanelViewModel.swift:211-244`):

| Key | Behaviour |
| --- | --- |
| ↓ | Move highlight down; **wraps** from the last entry to the first |
| ↑ | Move up; from the first entry it returns to "no highlight" (focus back in the field); from "no highlight" it jumps to the **last** entry |
| Return | Accept the highlighted suggestion if one is highlighted, otherwise accept the raw typed text |

Typing anything resets the highlight to "none". The highlighted row is tinted accent-at-30 % and auto-scrolled into view.

**[PLATFORM]** This is implemented with a global key-event monitor that only intercepts when suggestions exist and a text editor has focus. Any port needs equivalent care: arrow keys must reach the suggestion list, not the photo grid.

### 9.9 Settings window

Fixed **600 × 500**, three tabs (`SettingsView.swift:17-161`).

**Appearance**
- *Spacing between images* — slider 0–50, step 1, with a live `"N px"` readout.
- *Background Color* — full colour picker for the centre pane.
- *MIDI ▸ Debounce Time* — numeric field in milliseconds, hint text *"Prevents double-triggering"*.

**Keywords** — the vocabulary editor of §8.6.

**Shortcuts** — two sections:
- *Application Shortcuts*: one row per action (§12.2), each with a **key recorder** and a **MIDI recorder**.
- *Keyword Shortcuts*: one row per keyword that has a key or MIDI binding, with both recorders and a red trash button clearing both. Below them, an "add" row: keyword name field + both recorders + *Add* button (enabled only when a name and at least one binding are present).
- Footer: hint text *"Click 'None' or the existing key to record a new shortcut."* and a **Reset Defaults** button that resets the key map to the defaults of §12.1 **and clears the MIDI map entirely**.

**Recorder widgets** (both 80 × 20, monospaced):
- **Key recorder** — shows the current binding uppercased, or `None`. Click → shows `Press…`, accent background; the next key press is captured and stored.
- **MIDI recorder** — shows `CH<n> N:<note>` (1-based channel) or `None`. Click → shows `MIDI…`, orange background; the next incoming MIDI note is captured. **Pressing Return while recording clears the binding.**
Both stop recording when focus is lost.

**[BUG]** The key recorder constructs a throwaway `ShortcutService()` on every keystroke merely to format the key string (`SettingsView.swift:269`). Harmless but wasteful — each construction re-reads preferences. Use the injected instance.

### 9.10 Scrollbars

**[PLATFORM]** A view modifier reaches into the native view hierarchy to set every scroll view to overlay style with mini-size scrollers (`ScrollBarModifier.swift`). Applied to the sidebar, the grid, and the right panel. Purely cosmetic — a thin, auto-hiding scrollbar. Reproduce the *look*; the mechanism is macOS-specific and fragile (it searches three different places in the view tree for a scroll view).

---

## 10. Selection & Navigation Model

### 10.1 State

Two pieces of state (`LibraryViewModel.swift:26-27`):
- `selectedPhotoIds` — the full selection set.
- `lastSelectedPhotoId` — the **anchor**: the "current" photo, used for range selection, for the right panel's single-photo display, for MIDI LED feedback, and as the target of the keyboard rating/rotation actions.

The two can disagree: cmd-clicking the anchor out of the selection sets the anchor to `nil` while other photos remain selected (`LibraryViewModel.swift:208-218`).

### 10.2 Selection operations

| Operation | Effect |
| --- | --- |
| `selectSingle(id)` | Anchor = id; selection = `{id}`. With `nil`, clears both. |
| `toggleSelection(id)` | If present: remove; and if it was the anchor, anchor becomes `nil`. If absent: insert and make it the anchor. |
| `selectRange(to: id)` | Selection = every photo between the anchor and `id` **in the current sort order**, inclusive; anchor moves to `id`. If there is no anchor, degrades to `selectSingle`. |

Range selection operates on the *sorted, filtered* list — so shift-clicking selects what the user sees, including in random sort order.

### 10.3 Navigation

| Action | Behaviour |
| --- | --- |
| Next photo | Move the anchor one position forward in the sorted list. **Stops at the end** — no wrap. With no anchor, selects the **first** photo. |
| Previous photo | One position back. Stops at the start. With no anchor, selects the **last** photo. |
| Move up / Move down | Move by ± the current column count — i.e. one grid row. Out-of-range moves are ignored (no clamping to the edge). **Only active in grid mode** when triggered by keyboard (`CenterView.swift:152-155`); via MIDI they work in both modes (`ContentView.swift:122-123`). |

All navigation collapses the selection to a single photo.

### 10.4 Automatic selection

**On collection change** (`LibraryViewModel.swift:83-95`): switching sidebar entries automatically selects the **first** photo of the new list, or clears the selection if empty. The user is never left with nothing current after switching.

**On filter change — the neighbour rule** (`LibraryViewModel.swift:118-156`). This is the app's most thoughtful piece of interaction design and MUST be reproduced:

> When the currently selected photo drops out of the visible list — because the user just changed a rating or keyword that excluded it from the active Smart Collection — the app does **not** jump to the top of the list. It looks in the *previous* list order for the nearest surviving photo **after** the removed one and selects that; failing that, the nearest surviving photo **before** it; failing that, the first photo; failing that, nothing.

This is what makes rating-based culling flow: sitting in "Unrated", rating a photo removes it from view and the app advances to the next unrated photo automatically. Without this rule the user would be thrown back to the top of the list after every keystroke.

### 10.5 Focus

**[PLATFORM]** The centre pane grabs keyboard focus on appear, 50 ms after any view-mode change, and 100 ms after any collection change (`CenterView.swift:49-62`). The delays work around SwiftUI focus timing. A port needs the *behaviour* — after switching modes or collections, keyboard shortcuts must keep working without a click — but not the delays.

Keyboard shortcuts are suppressed entirely while the grid search field has focus (`CenterView.swift:125`), so the user can type `5` into search without rating the photo.

---

## 11. Sorting & Search

### 11.1 Sort options

Four options in a bottom-bar picker, default **Filename** (`LibraryViewModel.swift:46`, `:158-197`):

| Option | Comparator |
| --- | --- |
| **Filename** | Ascending by **full absolute path**, not by filename. **[QUIRK]** With several folders imported, photos group by directory, and `/b/001.jpg` sorts after `/a/999.jpg`. Users expecting name-only sorting will find this surprising. Document it or change it deliberately. |
| **Rating** | Descending by rating; ties broken ascending by full path. |
| **Date Added** | **Descending** — newest import first. |
| **Random** | See §11.2. |

Sorting is applied after filtering, and its result is what every navigation, range selection and index display refers to.

### 11.2 **[QUIRK] Random is stable**

Naïve random sorting reshuffles on every state change, which would make the list jump under the user's hands after every rating change. The original avoids this (`LibraryViewModel.swift:173-195`):

- A persistent `randomOrder` list of photo ids is kept in memory.
- On each re-sort: ids no longer in the filtered set are dropped; ids newly in the set are **shuffled and appended at the end**; the rest keep their existing positions.
- The order is re-rolled **only** when the user switches *to* Random from another option (`LibraryViewModel.swift:48-50`) — re-selecting Random while already in Random does nothing.
- The order is **not persisted**; it is new on every launch.

A port MUST implement this. Plain `shuffle()` on every update is a materially worse experience.

### 11.3 Search

A search field in the grid-mode bottom bar filters the photo list (`LibraryViewModel.swift:105-110`).

- Matches **keywords only** — case-insensitive substring. It does **not** search filenames, despite the presence of a filename rule in the query engine. **[QUIRK]**, and a likely source of user confusion; consider extending it to filenames.
- Applies **on top of** the active collection (AND).
- Applies immediately on every keystroke.
- **Not persisted**; cleared on relaunch. Also **not** cleared when switching collections — a stale search silently keeps filtering the new collection.
- The field is only present in grid mode, so switching to single view hides the control while the filter stays active. **[BUG]** — the user can end up with an invisible filter. **Fix: show the field in both modes, or clear the search when leaving grid mode.**

**Autocomplete** (`CenterView.swift:401-455`): typing shows a dropdown of matching keywords, fixed 150 px tall and 200 px wide, positioned **above** the field. Clicking a suggestion replaces the search text with the full keyword. Submitting closes the list.

---

## 12. Keyboard Shortcuts

### 12.1 The mapping model

`ShortcutService` holds a single dictionary: **key string → action string** (`ShortcutService.swift:49`), persisted in preferences.

**Action string grammar** — two namespaces:

```
app:<actionName>        e.g. app:rate3, app:nextPhoto
keyword:<KEYWORD>       e.g. keyword:ANNA, keyword:PEOPLE > ANNA
```

The keyword namespace is what makes one-press tagging possible: any keyword, whether or not it exists in the vocabulary, can be bound to a key. The text after `keyword:` is used verbatim as the keyword to toggle — including spaces and `>` separators.

**Key string grammar** (`ShortcutService.swift:140-149`):

```
[ctrl+][opt+][shift+][cmd+]<key>
```

The modifier order is **fixed and significant** — the map is a plain dictionary keyed by the exact assembled string, so `cmd+opt+l` and `opt+cmd+l` are different keys and only the first is ever produced. `<key>` is either a lowercased single character or one of these exact PascalCase names: `UpArrow`, `DownArrow`, `LeftArrow`, `RightArrow`, `Space`, `Escape`, `Return`, `Delete`, `Tab`. **Case is significant** in both directions.

### 12.2 Actions

Nineteen actions exist (`ShortcutService.swift:5-46`). The *Display name* column is what the Settings tab shows.

| Action id | Display name | Effect |
| --- | --- | --- |
| `nextPhoto` | Next Photo | Anchor forward one |
| `previousPhoto` | Previous Photo | Anchor back one |
| `moveUp` | Move Up | Anchor back one grid row |
| `moveDown` | Move Down | Anchor forward one grid row |
| `rotate` | Rotate Selection | Advance orientation (§6.6) |
| `viewGrid` | Grid View | Switch to grid |
| `viewSingle` | Single View | Switch to single |
| `toggleViewMode` | Toggle View Mode | Flip between them |
| `rate0` | Rate: Unrated | Set rating 0 |
| `rate1` | Rate: 1 Star | Set rating 1 |
| `rate2` | Rate: 2 Stars | Set rating 2 |
| `rate3` | Rate: 3 Stars | Set rating 3 |
| `rate4` | Rate: 4 Stars | Set rating 4 |
| `rate5` | Rate: 5 Stars | Set rating 5 |
| `ratingUp` | Increase Rating | +1, capped at 5 |
| `ratingDown` | Decrease Rating | −1, floored at 0 |
| `toggleLeftPanel` | Toggle Left Panel | Show/hide |
| `toggleRightPanel` | Toggle Right Panel | Show/hide |
| `toggleBottomPanel` | Toggle Bottom Panel | Show/hide |

### 12.3 Default key map

Written on first launch and restored by *Reset Defaults* (`ShortcutService.swift:67-87`):

| Key | Action |
| --- | --- |
| `→` | Next photo |
| `←` | Previous photo |
| `↑` | Move up one row |
| `↓` | Move down one row |
| `Space` | Rotate |
| `Escape` | Grid view |
| `Return` | Single view |
| `0` … `5` | Set rating 0–5 |
| `⌘⌥L` | Toggle left panel |
| `⌘⌥R` | Toggle right panel |
| `⌘⌥B` | Toggle bottom panel |

No defaults exist for `toggleViewMode`, `ratingUp`, `ratingDown`, or any keyword.

### 12.4 Binding rules

**Strictly 1:1 in both directions** (`ShortcutService.swift:93-107`). Assigning key K to action A:
1. removes any existing binding of K, then
2. removes **every other key bound to A**, then
3. binds K → A.

So an action can never have two keys, and a key can never have two actions. There is **no conflict warning** — the previous binding silently disappears. **Recommendation: warn before overwriting, and consider allowing multiple keys per action.**

### 12.5 Dispatch and the coverage gap

Key presses are handled by the centre pane (`CenterView.swift:120-174`):

1. If the search field has focus → ignore everything.
2. Assemble the key string from the pressed key and modifiers; look it up. No match → ignore (the event passes on to the menu system).
3. `keyword:` action → toggle that keyword on the anchor photo.
4. `app:` action → dispatch.

**[QUIRK] The centre pane's switch does not handle every action** (`CenterView.swift:149-168`). It covers `nextPhoto`, `previousPhoto`, `moveUp`, `moveDown`, `rotate`, `viewGrid`, `viewSingle`, `toggleViewMode` and `rate0`–`rate5`. It **falls through to a no-op** for `ratingUp`, `ratingDown`, `toggleLeftPanel`, `toggleRightPanel`, `toggleBottomPanel`.

The three panel toggles still work, because they are *also* declared as menu-item shortcuts in the View menu, and the menu system handles them before the view does. But **`ratingUp` and `ratingDown` are unreachable from the keyboard entirely** — they have no menu item and the view ignores them. They work only via MIDI. Binding a key to "Increase Rating" in Settings produces a binding that does nothing. **Fix: handle all nineteen actions in the dispatcher.**

Also note `moveUp`/`moveDown` are guarded to grid mode in the keyboard path (`CenterView.swift:152-155`) but not in the MIDI path — a small inconsistency.

### 12.6 Fixed menu shortcuts

Three shortcuts are hard-coded on menu items and are **not** remappable (`LibraryCommands.swift`): `⇧⌘N` New Library, `⇧⌘O` Open Library, `⇧⌘I` Add Folder.

### 12.7 Keyword shortcuts

Created in Settings ▸ Shortcuts ▸ Keyword Shortcuts by typing a keyword name and recording a key and/or a MIDI note. The keyword text is used **exactly as typed** — no uppercasing, no path resolution, no validation against the vocabulary.

**[BUG]** This differs from the right panel, which uppercases and resolves paths (§8.4). Binding a key to `anna` assigns the literal keyword `anna` to photos, while typing `anna` in the panel assigns `PEOPLE > ANNA`. The same intent produces two different keywords and only one of them will be found by group rules or colouring. **Fix: run the shortcut's keyword through the same normalise-and-resolve pipeline before storing the binding, or at minimum uppercase it.**

Toggling via a keyword shortcut applies to the **anchor photo only** (`LibraryViewModel.swift:321-334`), not to the whole selection — unlike the right panel, which applies to all selected. See §16.

---

## 13. MIDI Subsystem

The MIDI layer is what makes BALLASTVIEW distinctive: a hardware pad controller becomes a dedicated culling console, with the pads lit to mirror the current photo's state.

### 13.1 Mapping model

`MIDIService` holds a dictionary **note string → action string**, persisted in preferences (`MIDIService.swift:6`).

**Note string grammar:**

```
note:<channel>:<noteNumber>        e.g. note:0:60
```

`channel` is **0-based** (0–15) as it appears on the wire; `noteNumber` is 0–127. The UI displays it 1-based as `CH1 N:60` (`MIDIService.swift:255-265`).

Action strings use the **same two namespaces as keyboard shortcuts** (§12.1), so a note and a key can be bound to the same action, and both mechanisms share the action vocabulary exactly.

Binding is **strictly 1:1** in the same way as keys (`MIDIService.swift:38-51`). There are **no MIDI defaults** — the map starts empty and *Reset Defaults* clears it entirely.

### 13.2 Input

**[PLATFORM]** At start-up the service creates a MIDI client, an input port and an output port, then connects the input port to **every MIDI source present at that moment** (`MIDIService.swift:69-113`).

- **No hot-plug support.** Devices connected after launch are never seen; the app must be restarted. The code even contains a `midiSetupChanged` handler for this — **[DEAD]**, it is never registered or called (`MIDIService.swift:103-105`). **Fix: register for setup-change notifications and reconnect.**
- It also does not disconnect anything, so unplugging is handled by the OS.

### 13.3 Message parsing

Only Note On and Note Off are understood (`MIDIService.swift:140-200`). The parser walks the byte stream:

| Status | Handling |
| --- | --- |
| `0x9n` (Note On) with velocity > 0 | **Trigger.** Consumes 3 bytes. |
| `0x9n` (Note On) with velocity = 0 | Treated as **Note Off** (the standard running-status convention). Consumes 3 bytes. |
| `0x8n` (Note Off) | Note Off. Consumes 3 bytes. |
| anything else | Skipped **one byte at a time** |

Control Change, Program Change, pitch bend, aftertouch and clock are all ignored — a knob or fader cannot be mapped. **[QUIRK]** Skipping unknown messages byte-by-byte means a CC message's data bytes are re-examined as potential status bytes; a CC whose data happens to look like `0x9n` could in principle fabricate a phantom note. Rare, but a port SHOULD parse by message length rather than scanning.

Velocity is used **only** as an on/off discriminator — it is never used as a value, so pressure-sensitive pads behave as plain switches.

### 13.4 Debounce

Optional, from the `midiDebounceTime` preference in milliseconds, default **0 = disabled** (`MIDIService.swift:165-173`).

When enabled, a triggered action is ignored if the **same action** fired less than N ms ago. The window is **per action, not per note** — two different pads bound to the same action share one window. This exists because some controllers emit duplicate Note On messages.

### 13.5 Dispatch

A triggered action is published to the UI, which dispatches it (`ContentView.swift:116-144`) covering **all nineteen actions** — including `ratingUp`, `ratingDown` and the three panel toggles that the keyboard path drops (§12.5). Keyword actions toggle the keyword on the anchor photo.

The MIDI path also does **not** restrict `moveUp`/`moveDown` to grid mode.

### 13.6 LED feedback protocol

This is the subsystem's centrepiece and the part most likely to be missed in a reimplementation. The app **sends** MIDI back to the controller so pads light up.

**Transport:** "on" is Note On with velocity **127**; "off" is Note On with velocity **0** (not `0x8n`) — the convention understood by Launchpad-class devices (`MIDIService.swift:345-353`). Messages are sent to **every MIDI destination on the system**, not to the device the input came from (`MIDIService.swift:375-379`). **[QUIRK]** With several MIDI devices attached, all of them receive the lighting messages. A port SHOULD offer device selection.

**Feedback is recomputed on four triggers** (`ContentView.swift:93-104`):
1. the anchor photo changes,
2. the photo list changes in any way (rating, keywords, import…),
3. the view mode changes,
4. the window appears.

The state broadcast is *(the anchor photo's keywords, the anchor photo's rating)*, or *([], 0)* when there is no anchor (`ContentView.swift:107-114`).

**Lighting rules** (`MIDIService.swift:300-343`):

| Bound action | Pad is lit when |
| --- | --- |
| `keyword:X` | The anchor photo carries keyword `X` (exact string match) |
| `app:rate0` | The anchor photo's rating is exactly **0** |
| `app:rate1` … `app:rate5` | The anchor photo's rating is **≥ N** |
| `app:viewGrid` | Currently in grid mode |
| `app:viewSingle` | Currently in single mode |
| `app:toggleViewMode` | Currently in **single** mode |

**[QUIRK] Star pads light cumulatively.** A photo rated 4 lights pads 1, 2, 3 and 4 — the controller renders a star meter, not a radio button. The source comments record this as an explicit user request (`MIDIService.swift:331-332`). Rate-0 is the exception: it lights only at exactly zero, so it reads as "unrated" rather than "at least zero".

All other actions (navigation, rotate, panel toggles) have **no** lighting; their pads stay dark permanently.

### 13.7 **[QUIRK] Re-assert on Note Off**

This is the non-obvious mechanism that makes the whole thing work, and it MUST be reproduced.

Many controllers extinguish a pad's LED themselves when the pad is released. Without intervention, every lit pad would go dark the moment the user let go. So on **every Note Off**, the app immediately re-sends the correct LED state for that note (`MIDIService.swift:202-253`) — using the last known keywords/rating/view mode cached inside the service.

The Note Off handler mirrors the lighting rules of §13.6 exactly (keywords, cumulative stars, rate-0, and the three view-mode actions). A reimplementation that forgets this will appear to work at first — pads light on selection change — and then mysteriously go dark as the user works.

### 13.8 Recording a MIDI binding

The MIDI recorder widget (§9.9) works by observing the service's *last received note*: click the widget, press a pad, the note is captured. Pressing **Return** while armed clears the binding instead. The service publishes every incoming note for this purpose, whether or not it is mapped (`MIDIService.swift:162`).

---

## 14. Application Menus

Three custom top-level menus, in addition to the standard system menus (`BALLASTVIEWApp.swift:23-27`).

### 14.1 Library menu (`LibraryCommands.swift`)

| Item | Shortcut | Enabled when | Notes |
| --- | --- | --- | --- |
| `Current: <library filename>` | — | never (always disabled) | Header showing the open library, filename without extension. Followed by a separator. Hidden when no library is open. |
| New Library… | `⇧⌘N` | always | §4.1 |
| Open Library… | `⇧⌘O` | always | §4.2 |
| Open Recent ▸ | — | always | One item per recent library, labelled with its **filename including extension**. Plus separator and *Clear Menu* when non-empty. |
| Close Library | — | library open | §4.4 |
| — separator — | | | |
| Add Folder… | `⇧⌘I` | library open | §5.1 |
| — separator — | | | |
| Save Metadata into Files | — | library open | §6.4 |
| Load Metadata from Files | — | library open | §6.4 |
| Remove Folder ▸ | — | library open | One item per imported folder, labelled with its **full path**. No confirmation (§5.5). |

**[QUIRK]** The header uses the filename without extension while Open Recent uses it with — inconsistent labelling of the same thing.

### 14.2 Photo menu (`PhotoCommands.swift`)

Every item is disabled when there is no anchor photo. Each item's keyboard shortcut is taken **live from the user's key map**, so remapping in Settings updates the menu.

| Item | Bound action |
| --- | --- |
| Next Photo | `app:nextPhoto` |
| Previous Photo | `app:previousPhoto` |
| — separator — | |
| Rotate Clockwise | `app:rotate` |
| Rating ▸ 0–5 Stars | `app:rate0` … `app:rate5` |

**[BUG]** The Rating submenu items are **not** individually disabled — only the submenu is (`PhotoCommands.swift:24`), and the guard is on `selectedPhotoId`. Harmless in practice since the underlying action is a no-op without a selection.

### 14.3 View menu (`ViewCommands.swift`)

Three items whose titles toggle with state and whose shortcuts come from the key map:

| Item title (state-dependent) | Bound action |
| --- | --- |
| *Hide Left Panel* / *Show Left Panel* | `app:toggleLeftPanel` |
| *Hide Right Panel* / *Show Right Panel* | `app:toggleRightPanel` |
| *Hide Bottom Panel* / *Show Bottom Panel* | `app:toggleBottomPanel` |

As noted in §12.5, these menu items are the only reason the panel-toggle shortcuts work at all.

---

## 15. Settings & Persistence Keys

### 15.1 Application preferences

Every key the app reads or writes outside the library file. A port MUST provide equivalent storage; the key names matter only if it should interoperate with an existing installation.

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `LastOpenedLibraryBookmark` | blob | — | The library reopened at launch. **[PLATFORM]** a security-scoped bookmark; a plain path suffices elsewhere. Removed by *Close Library*. |
| `RecentLibraryBookmarks` | array of blobs | `[]` | Recents list, most recent first, max 10. |
| `AppKeyMap` | dict string→string | the defaults of §12.3 | Keyboard bindings. |
| `AppMidiMap` | dict string→string | `{}` | MIDI bindings. |
| `LastSelectedCollection` | string (UUID) | — | Restored sidebar selection; falls back to ALL PHOTOS. |
| `CollapsedGroups` | array of strings (UUIDs) | `[]` | Collapsed sidebar groups. |
| `isLeftPanelVisible` | bool | `true` | |
| `isRightPanelVisible` | bool | `true` | |
| `isBottomPanelVisible` | bool | `true` | |
| `gridSpacing` | double | `12.0` | Grid gap **and** grid outer padding, in points. |
| `centerViewBackgroundColor` | string | `"#1E1E1E"` | Centre pane background, `#RRGGBB` or `#RRGGBBAA`. |
| `midiDebounceTime` | int | `0` | Milliseconds; 0 disables debounce. |

**[DEAD]** `ShortcutService` declares an unused constant `"KeywordShortcuts"` (`ShortcutService.swift:51`) — a leftover from an earlier design where keyword bindings lived in their own store. Nothing reads or writes it.

### 15.2 Colour encoding

Colours are `#RGB`, `#RRGGBB` or `#AARRGGBB` (`Color+Hex.swift`). Note the 8-digit form is parsed **alpha-first** but *written* alpha-**last** (`Color+Hex.swift:15` vs `:44`) — **[BUG]**: a colour saved with transparency reloads with its alpha and red channels swapped. In practice only the background colour picker can produce alpha, so it is nearly unreachable. **Fix: agree on one order — `#RRGGBBAA` is the web convention.** Unparseable strings fall back to `(a:1, r:1, g:1, b:0)` in raw units, i.e. very nearly black at 1/255 alpha — effectively invisible.

### 15.3 Sandbox entitlements

**[PLATFORM]** `BALLASTVIEW.entitlements` requests:

| Entitlement | Why |
| --- | --- |
| `com.apple.security.app-sandbox` | Sandbox on |
| `com.apple.security.files.user-selected.read-write` | Read *and write* the user's photo folders — write is required by `Save Metadata into Files` |
| `com.apple.security.device.usb` | USB MIDI controllers |
| `com.apple.security.device.audio-input` | Requested but **not needed** — the app captures no audio. It appears to be a misunderstanding of what CoreMIDI requires. **Recommendation: drop it**; it triggers a user-visible microphone permission prompt for no reason. |

### 15.4 Build configuration

Bundle id `ballast.BALLASTVIEW`, marketing version `1.0`, build `1`, Swift 5, no development team set (unsigned/local builds), Info.plist generated. The deployment target appears twice in the project file (`14.6` and `26.1`) — the effective one is 26.1.

---

## 16. Quirks, Bugs & Recommendations

This section consolidates everything flagged above. **Read it before writing a line of code** — these are the items an LLM reimplementing from a feature list would get wrong.

### 16.1 Data-loss defects — fix these

| # | Issue | Where | Effect | Recommended fix |
| --- | --- | --- | --- | --- |
| D1 | **Read/write metadata schema mismatch** | `MetadataService.swift:33-42` vs `EXIFWriter.swift:43-51` | Ratings are written as `xmp:Rating` but read as IPTC `StarRating`. *Save to Files* followed by *Load from Files* can silently reset every rating to 0 — and the load path is authoritative, so the library's data is destroyed. | Read XMP first (`xmp:Rating`, `dc:subject`), fall back to IPTC. Keep writing XMP — it is what Lightroom/Bridge/Capture One use. |
| D2 | **Load Metadata discards unused keywords** | `LibraryManager.swift:312-313` | The global keyword index is rebuilt purely from photos, deleting every vocabulary entry not currently assigned. A prepared tag list vanishes on first sync. | Union with the existing index instead of replacing it — `addFolder` already does this correctly at `:191`. |
| D3 | **Non-atomic library write** | `PersistenceService.swift:23` | The whole catalogue is rewritten on every single keystroke with a plain write. A crash or power loss mid-write truncates the file and loses everything. | Write to a temp file and rename atomically; keep one generation of backup. |
| D4 | **Folder removal uses bare prefix matching** | `LibraryManager.swift:207` | Removing `/Photos/Trip` also deletes all records under `/Photos/Trip2024`. No confirmation, no undo. | Compare against `path + "/"` (or compare path components) and add a confirmation showing the affected count. |
| D5 | **Rating is never clamped on read** | `MetadataService.swift:40` | A file with `StarRating: 7` yields rating 7 — five filled stars, and it matches `rating greaterThan 5`. | Clamp to 0…5 on read. |
| D6 | **Unknown enum values abort the whole load** | `Library.swift:92-109` | A rule type written by a future version makes the library fail to open — and the failure is silent (§4.2). | Skip unrecognised rules, log, and continue. |

### 16.2 Correctness defects

| # | Issue | Where | Effect | Recommended fix |
| --- | --- | --- | --- | --- |
| C1 | **Folder import is not recursive** | `FileSystemService.swift:22` | Adding a folder organised into subfolders imports **zero** photos, with no error or warning. Git `8595a3f` made this change deliberately; no reason is recorded. | Make it recursive, or add an explicit "include subfolders" checkbox to the import dialog. |
| C2 | **`keywordGroup` rules never match hierarchical keywords** | `QueryEngine.swift:83-92` | The rule compares bare node names against photos' resolved paths (`"PEOPLE > ANNA"`), so it matches nothing except top-level keywords assigned by bare name. | Build the resolved path for each definition and compare that, reusing the §8.2 path builder. |
| C3 | **Deleting a keyword group orphans its keywords** | `LibraryManager+Keywords.swift:117-125` | Definitions keep a dead `groupID`: they disappear from Settings, lose their chip colour, and any Smart Collection rule referencing the group silently matches nothing — while the data lingers in the JSON. | On delete, reassign definitions to a fallback group or delete the subtree; warn if any rule references the group. |
| C4 | **Renaming a keyword does not rename it on photos** | `LibraryManager+Keywords.swift:71-91` | Photos reference keywords by string, not by id. Renaming `ANNA` leaves 400 photos carrying the stale string, now uncoloured and unmatched by group rules. | On rename, rewrite the string on every photo carrying the old path (and its descendants' paths), and update the index. This is the single biggest structural weakness of the keyword system. |
| C5 | **`ratingUp` / `ratingDown` are unreachable by keyboard** | `CenterView.swift:167` | The dispatcher's `default: break` swallows them and they have no menu item. A key bound in Settings does nothing. Only MIDI reaches them. | Handle all nineteen actions in the dispatcher. |
| C6 | **Search field disappears while its filter stays active** | `CenterView.swift:86-103` | The field exists only in grid mode. Switching to single view hides the control but keeps the filter — the user sees a truncated set with no visible cause. Switching collections does not clear it either. | Show the field in both modes, or clear the search when leaving grid mode; ideally show an active-filter indicator. |
| C7 | **Keyword shortcuts bypass normalisation** | `SettingsView.swift:124` | Binding a key to `anna` stores the literal keyword `anna`, whereas typing `anna` in the right panel stores `PEOPLE > ANNA`. Same intent, two different keywords; only one is coloured and matched by group rules. | Run the shortcut's keyword through the same uppercase + path-resolution pipeline (§8.4). |
| C8 | **Hex colour alpha order is inconsistent** | `Color+Hex.swift:15` vs `:44` | 8-digit colours are parsed `#AARRGGBB` but written `#RRGGBBAA` — alpha and red swap on every round trip. Only reachable via the background colour picker. | Standardise on `#RRGGBBAA`. |
| C9 | **MIDI parser skips unknown messages one byte at a time** | `MIDIService.swift:196-198` | Data bytes of an ignored message are re-examined as status bytes; a Control Change can in principle fabricate a phantom note trigger. | Parse by message length using the status byte. |
| C10 | **No MIDI hot-plug** | `MIDIService.swift:97-101` | Devices connected after launch are invisible until restart. A handler for this exists but is never registered. | Register for MIDI setup-change notifications and reconnect sources. |
| C11 | **`keywordGroups == nil` handled two ways** | `LeftPanelViewModel.swift:34` vs `LibraryManager+Keywords.swift:97` | On a pre-v2 library the Smart Collection editor's group dropdown is empty while Settings shows six groups. | Substitute the defaults everywhere. |
| C12 | **Two selection semantics for the same operations** | `LibraryViewModel.swift:256-334` vs `RightPanelViewModel.swift:113-173` | Rating, rotation and keyword toggling from the keyboard/MIDI affect **only the anchor photo**; the same operations from the right panel affect **all selected photos**. Users batch-select and then press a key, expecting batch behaviour. | Decide one semantic — batch is the useful one — and route both paths through it. |
| C13 | **Empty state names the wrong menu** | `ContentView.swift:22` | Says "Use File > New Library" but the menu is called *Library*. | Fix the string. |
| C14 | **Destructive actions have no confirmation** | `LeftPanelViewModel.swift:204-228`, `LibraryManager.swift:200-215`, `LibraryManager+Keywords.swift:46-52` | Deleting a group, a collection, a keyword subtree, or a folder's photos is one click with no confirmation and no undo. | Add confirmations for anything affecting more than one record; consider an undo stack. |

### 16.3 Deliberate quirks — reproduce these

| # | Behaviour | Where | Why it matters |
| --- | --- | --- | --- |
| Q1 | **The neighbour rule.** When the selected photo drops out of the filter, select the nearest *surviving* photo after it in the previous order (then before it, then the first). | `LibraryViewModel.swift:118-156` | The single most important interaction detail in the app. It is what makes rating-based culling flow instead of throwing the user back to the top of the list after every keystroke. |
| Q2 | **Stable random order.** Random survives filter changes; new photos are appended shuffled; re-rolls only when switching *to* Random. | `LibraryViewModel.swift:173-195` | Naïve shuffling makes the grid jump under the user's hands on every edit. |
| Q3 | **Re-assert LEDs on Note Off.** After every pad release, immediately resend that pad's correct lit state. | `MIDIService.swift:202-253` | Without it, every pad goes dark the moment it is released and the whole feedback feature appears broken. |
| Q4 | **Star pads light cumulatively.** Rating 4 lights pads 1–4; rate-0 lights only at exactly 0. | `MIDIService.swift:321-341` | An explicit user request recorded in the source. The controller reads as a meter, not a radio button. |
| Q5 | **Display decodes unrotated, then rotates by the stored orientation.** | `CenterView.swift:280`, `:287`, `:363` | This is what makes rotation instant without touching the file. Skip it and rotation appears to do nothing. |
| Q6 | **Empty rule list matches everything.** | `QueryEngine.swift:5-7` | A new collection shows the whole library until rules are added. Deliberate: create → see everything → narrow down. |
| Q7 | **LAST IMPORT keeps the previous batch when a rescan finds nothing.** | `LibraryManager.swift:183-187` | Rescanning a folder does not blank the user's "what I just added" list. |
| Q8 | **LAST IMPORT before any import is an unsatisfiable dummy rule.** | `LeftPanelViewModel.swift:114-120` | A workaround for Q6. The observable requirement: the list is empty, not full. |
| Q9 | **Rating star rows are exact matches, not "N or more".** | `LeftPanelViewModel.swift:98-108`, `:154-161` | ★★★ means exactly three, and the badge count agrees. |
| Q10 | **Filename sort uses the full path.** | `LibraryViewModel.swift:163` | With several folders, photos group by directory. Surprising, but it is the shipped behaviour — change only deliberately. |
| Q11 | **Search matches keywords only**, never filenames. | `LibraryViewModel.swift:105-110` | Users will try filenames. Document it or extend it — but know the original does not. |
| Q12 | **Tapping the current star rating clears it to 0.** | `RightPanelView.swift:289` | The only mouse route to "unrated". |
| Q13 | **A mixed-rating selection displays 0 stars.** | `RightPanelViewModel.swift:89-95` | Indistinguishable from "all unrated". Worth improving, but note it is a change. |
| Q14 | **The right panel shows the *intersection* of the selection's keywords.** | `RightPanelViewModel.swift:98-109` | Not the union. Toggling a shown chip affects every selected photo. |
| Q15 | **The keyword field forces uppercase on every keystroke.** | `RightPanelView.swift:31` | The whole app is uppercase-centric because the metadata reader uppercases too. |
| Q16 | **Typed keywords resolve to their full path, first match wins.** | `LibraryManager+Keywords.swift:145-162` | `ANNA` → `PEOPLE > TEAM > ANNA`. Ambiguous names cannot be disambiguated by typing. |
| Q17 | **Autocomplete offers every tree node, not just leaves.** | `LibraryManager+Keywords.swift:182-194` | `PEOPLE`, `PEOPLE > TEAM` and `PEOPLE > TEAM > ANNA` are all assignable. |
| Q18 | **Chips sort by group order, then alphabetically; ungrouped last.** | `RightPanelViewModel.swift:188-207` | Group order in Settings is therefore semantically meaningful, not cosmetic. |
| Q19 | **Keyword siblings are always name-sorted; groups are drag-ordered.** | `LibraryManager+Keywords.swift:20`, `:127-135` | Two different ordering models in one editor. |
| Q20 | **Shortcut binding is strictly 1:1 in both directions, silently.** | `ShortcutService.swift:93-107`, `MIDIService.swift:38-51` | Assigning a key steals it from its old action *and* removes the action's old key, with no warning. |
| Q21 | **Shortcuts are suppressed while the search field has focus.** | `CenterView.swift:125` | Otherwise typing `5` would rate the photo. |
| Q22 | **Grid cells are square, fill-cropped, top-aligned.** | `CenterView.swift:247-255` | Portraits crop at the bottom — deliberate, keeps faces visible. |
| Q23 | **Grid spacing doubles as outer padding.** | `CenterView.swift:187-188` | One slider controls both; the layout stays visually uniform. |
| Q24 | **Sort order and view mode reset every launch; the selected collection does not.** | §2.3 | Asymmetric on purpose. |
| Q25 | **Collapsing a sidebar group hides its `+` button too.** | `LeftPanelView.swift:361-371` | |
| Q26 | **Metadata sync alerts read "Updated N files." in both directions.** | `LibraryManager.swift:266`, `:320` | Same wording for opposite operations. Improve the wording, keep the reporting. |
| Q27 | **`Save Metadata` skips unreadable files rather than repairing them.** | `LibraryManager.swift:237` | A file with damaged metadata can never be fixed by the command. |
| Q28 | **The star widget in the rule editor cannot express 0.** | `SmartCollectionEditor.swift:132-137` | "Unrated" must be built as `rating lessThan 1`. |

### 16.4 Dead code and debris — do not port

| # | Item | Where |
| --- | --- | --- |
| X1 | `synchronizeMetadata()` — fully implemented, call site commented out at library open. The comment explains why: it would overwrite in-app edits. **Do not re-enable.** | `LibraryManager.swift:79-84`, `:409-482` |
| X2 | `loadMetadata(for:)` — complete, correct, **never called**. Built for selection-triggered refresh that was never wired up. | `LibraryManager.swift:338-405` |
| X3 | `midiSetupChanged()` — hot-plug handler, never registered. | `MIDIService.swift:103-105` |
| X4 | `getFullPath(for:)` — case-preserving path builder with no callers. | `LibraryManager+Keywords.swift:140-143` |
| X5 | `keyEquivalent(for:)` — marked deprecated in a comment, no callers. | `ShortcutService.swift:186-188` |
| X6 | `SimpleFlowLayout` — a complete custom flow layout, unused (chips are laid out vertically instead). | `RightPanelView.swift:298-343` |
| X7 | `MetadataRow` — a metadata label/value row view, never instantiated. The right panel shows no EXIF beyond the filename. | `RightPanelView.swift:231-246` |
| X8 | `commitEditingGroup` / `commitEditingKeyword` — explicit no-ops left from an inline-editing design. | `KeywordsSettingsView.swift:163-179` |
| X9 | `toggleGroupCollapse` — superseded by inline logic in the view; never called. | `LeftPanelViewModel.swift:72-79` |
| X10 | An empty `onReceive` handler with only a comment in its body. | `RightPanelView.swift:43-47` |
| X11 | Redundant conditional cast whose branches are identical. | `LibraryManager+Keywords.swift:205-212` |
| X12 | `library_example.json` — a hand-written sample predating `orientation` and `importBatchId`. **No code reads it.** Not authoritative for the schema. | `BALLASTVIEW/library_example.json` |
| X13 | The `"KeywordShortcuts"` preference key constant — never read or written. | `ShortcutService.swift:51` |
| X14 | `Photo.swift`'s comment claiming metadata is not saved, contradicted by the `CodingKeys` immediately below. | `Photo.swift:17` |
| X15 | `metadata.version` — written, never read. No migration logic exists. A port **should** actually use it. | `Library.swift:66` |
| X16 | `lastImportDate` — written, never read. | `Library.swift:15` |
| X17 | The `audio-input` sandbox entitlement — the app captures no audio. | `BALLASTVIEW.entitlements` |
| X18 | `MyLibrary.json` / `MyLibrary2.json` in the repo root — the developer's test catalogues, pointing at `/Users/code/Desktop/temp-delete-bilder`. Useful as schema samples, not part of the product. | repo root |

### 16.5 Performance characteristics to design away

Not bugs in the sense of wrong output, but the reason the original will not scale past a few thousand photos:

| Issue | Where | Cost |
| --- | --- | --- |
| The entire catalogue is re-serialised and rewritten to disk on **every** rating keystroke, keyword toggle and rotation. | §2.2 | `O(library size)` per keystroke. At 20k photos this is several MB of JSON per keypress. |
| Every published change recomputes the match count of every collection against every photo. | `LeftPanelViewModel.swift:144-169` | `O(photos × collections)` per keystroke. |
| Every published change re-filters and re-sorts the full photo array. | `LibraryViewModel.swift:98-197` | `O(n log n)` per keystroke. |
| **No thumbnail cache whatsoever** — every cell decodes from the original file on appear, and re-decodes on resize or rotation. | `CenterView.swift:272-291` | Dominates scrolling cost, especially for RAW. |
| Single view decodes the image at **full resolution** with no downsampling to the display size. | `CenterView.swift:358-365` | Seconds per image on high-resolution RAW. |
| Metadata sync fans out one concurrent file read per photo, unbounded. | `LibraryManager.swift:233`, `:277` | Thousands of concurrent reads on a large library. |

---

## 17. Reimplementation Notes

### 17.1 What is genuinely platform-independent

Everything in §3 (schema), §5 (import rules), §6.6 (rotation cycle), §7 (query engine), §8 (keyword model, path resolution, colouring, sort priority), §10 (selection and the neighbour rule), §11 (sorting incl. stable random, search), §12.1–12.4 (shortcut model), §13.1 and §13.6–13.7 (MIDI mapping and LED protocol). This is the product. It can be built identically on any stack and is where reimplementation effort should go.

### 17.2 What is macOS-bound, and what to use instead

| Original | Purpose | Replacement candidates |
| --- | --- | --- |
| ImageIO (`CGImageSource*`) | Read EXIF/IPTC metadata | **ExifTool** (most complete, subprocess), `exiv2`, `libexif`; Python `Pillow` + `piexif`/`pyexiv2`; Node `exifr` |
| ImageIO (`CGImageDestinationCopyImageSource` + `CGImageMetadata`) | **Lossless** metadata write — copies image data untouched | **ExifTool** is the only widely available tool that reliably does this across formats. `sharp` recompresses — unsuitable. Losslessness is a hard requirement, not a nicety. |
| ImageIO thumbnails | Downsampled decode | `sharp` (Node), `Pillow` (Python), `vips`, or the platform's own image pipeline. Add the LRU cache the original lacks. |
| CoreMIDI | Note in/out incl. LED feedback | **Web MIDI API** (browser/Electron — supports output, which is essential), **RtMidi** (C++/Python/Node bindings), `python-rtmidi`, `node-midi`, `webmidi.js` |
| Security-scoped bookmarks | Persistent folder access under sandbox | Unnecessary outside the macOS sandbox — keep the schema field, ignore it. On Windows/Linux, plain absolute paths suffice. |
| `NSOpenPanel` / `NSSavePanel` | File dialogs | Any native/electron dialog |
| `NSWorkspace.selectFile` | Reveal in Finder | `shell.showItemInFolder` (Electron), `xdg-open`/`explorer /select,` |
| `NSSharingServicePicker` | Share sheet | Platform share API, or drop the feature |
| SwiftUI `HSplitView`, `LazyVGrid`, `List`, `OutlineGroup` | Layout | Any UI framework — §9 specifies the metrics |
| `UserDefaults` / `@AppStorage` | Preferences | Any key-value store — §15.1 lists every key |
| `NSScrollView` scroller styling | Thin overlay scrollbars | CSS `scrollbar-width: thin` or equivalent |

### 17.3 Recommended build order

The dependency structure makes one order clearly best:

1. **Schema + persistence** (§3, §4) — load and save the existing `MyLibrary.json` files unchanged. This immediately proves compatibility.
2. **Import + metadata read** (§5, §6.1) — fix C1 (recursion) and D5 (clamping) now.
3. **Grid + selection + navigation** (§9.3, §10) — including the neighbour rule Q1 from the start; retrofitting it is painful.
4. **Rating + rotation + right panel** (§6.6, §9.8) — decide C12 (batch vs. anchor semantics) here, once, for both paths.
5. **Query engine + sidebar** (§7, §9.2) — fix C2 (keyword group paths) while writing it.
6. **Keywords** (§8) — fix C4 (rename propagation) here; it dictates whether photos store strings or ids. **This is the one decision that is expensive to change later.**
7. **Shortcuts** (§12) — fix C5 (complete dispatch) and C7 (normalisation).
8. **MIDI** (§13) — input first, then the LED protocol; Q3 (re-assert on Note Off) last and explicitly tested with real hardware.
9. **Settings, menus, polish** (§9.9, §14, §15).
10. **Metadata write** (§6.2) — last, because it is the only destructive operation. Fix D1 (schema symmetry) before shipping it.

### 17.4 The one architectural change worth making

Keep the JSON file as the on-disk format — it is a genuine feature (human-readable, diffable, portable, no lock-in). Change **when** it is written and **what** is recomputed:

- **Debounce persistence.** Write at most once every ~500 ms of idle, plus on window close/quit, instead of on every keystroke. Fixes the write amplification and, combined with an atomic write, fixes D3.
- **Index instead of scanning.** Keep a `photoId → Photo` map and a keyword inverted index. Recompute collection counts incrementally for the photos that actually changed, not for the whole library.
- **Cache thumbnails.** An on-disk thumbnail cache keyed by `(path, mtime, size, orientation)` plus an in-memory LRU. This is the single biggest perceived-performance win.
- **Downsample the single view** to roughly the display size instead of decoding full resolution.
- **Bound concurrency** on metadata fan-out to 8–16.

If photos should keep referring to keywords by **id** rather than by string (which fixes C4 properly), that decision must be made at step 6 of §17.3. The compatible migration: keep the string array in the JSON for readability, but treat it as a projection of an id list that is also stored.

### 17.5 Things worth adding that the original lacks

Not required for parity, but every one of them addresses a real gap visible in the code: undo/redo (there is none, anywhere); confirmation dialogs for the destructive operations of C14; a visible indicator when a search or collection filter is active (C6); ratings/keyword badges in grid cells (the grid shows pixels only); capture date in the model (only import date exists, so `dateRange` rules are far less useful than they sound); multiple key bindings per action (Q20); and MIDI output device selection instead of broadcasting to every destination (§13.6).

---

## 18. Acceptance Checklist

Each line is directly testable against the original. Group headers map to the sections above.

**Library file**
- [ ] Opens both `MyLibrary.json` and `MyLibrary2.json` from the original repo without error, including their missing `keywordDefinitions` / `keywordGroups` / `lastImportId` fields.
- [ ] Writes pretty-printed JSON with ISO-8601 UTC dates.
- [ ] A new library contains empty arrays plus the six default keyword groups with the exact colours of §8.3.
- [ ] Every mutation updates `metadata.lastModifiedDate`.
- [ ] Killing the app mid-edit never leaves a truncated catalogue (fix D3).

**Lifecycle**
- [ ] The last opened library reopens automatically at launch.
- [ ] *Close Library* prevents auto-reopen but leaves the recents list intact.
- [ ] The recents list holds at most 10 entries, most recent first, no duplicates.

**Import**
- [ ] Accepts exactly the eleven extensions of §5.3.
- [ ] Re-importing a folder adds only files not already present (matched by absolute path).
- [ ] One `importBatchId` per *Add Folder* invocation; LAST IMPORT shows exactly that batch.
- [ ] A rescan that finds nothing new leaves LAST IMPORT unchanged (Q7).
- [ ] Keywords, rating and orientation are read from each file at import.

**Metadata**
- [ ] Keywords read from files are uppercased, de-duplicated and sorted.
- [ ] Writing metadata does not recompress the image — verify by byte-comparing the pixel data before and after.
- [ ] Rating survives *Save to Files* → *Load from Files* (fix D1).
- [ ] Vocabulary keywords not assigned to any photo survive *Load from Files* (fix D2).
- [ ] Rotation changes only the library until metadata is explicitly written.
- [ ] The rotation cycle is exactly 1 → 6 → 3 → 8 → 1, and any other value jumps to 6.

**Query engine**
- [ ] Every cell of the §7.3 matrix behaves as specified, including operators that return false.
- [ ] A collection with no rules matches every photo (Q6).
- [ ] `keywordGroup` matches photos carrying nested keywords (fix C2).
- [ ] The seven pseudo-collections use the exact UUIDs of §7.5.
- [ ] Star rows filter and count on **exact** rating.
- [ ] LAST IMPORT is empty before the first import (Q8).
- [ ] Counts update live: rating a photo 5 increments the ★★★★★ badge immediately.

**Keywords**
- [ ] Typing `ANNA` assigns `PEOPLE > ANNA` when that node exists; otherwise assigns `ANNA`.
- [ ] The input field forces uppercase on every keystroke.
- [ ] Autocomplete offers intermediate nodes as well as leaves.
- [ ] Chips sort by group order, then alphabetically, with ungrouped last.
- [ ] Chip colour follows the **leaf** node's group.
- [ ] The right panel shows the intersection of the selection's keywords.
- [ ] ↓ wraps to the top; ↑ from the first suggestion returns focus to the field; ↑ from no-highlight jumps to the last.

**Selection and navigation**
- [ ] Click / shift-click / cmd-click behave as in §9.3.
- [ ] Next/Previous stop at the ends without wrapping.
- [ ] Move up/down step by exactly the current column count.
- [ ] Switching collections auto-selects the first photo.
- [ ] **The neighbour rule (Q1):** in a collection filtered to unrated photos, rating the current photo advances to the next unrated one — never back to the top of the list.

**Sorting and search**
- [ ] Filename sorts by full path; Rating sorts descending with path as tie-break; Date Added sorts newest first.
- [ ] Random survives filter changes and re-rolls only on switching *to* Random (Q2).
- [ ] Search matches keywords case-insensitively and stacks with the active collection.

**Shortcuts**
- [ ] The default map of §12.3 is written on first launch and restored by *Reset Defaults*.
- [ ] Key strings are assembled as `ctrl+opt+shift+cmd+<key>` in that exact order.
- [ ] Binding a key removes both the key's previous action and the action's previous key.
- [ ] All nineteen actions respond to a bound key (fix C5).
- [ ] No shortcut fires while the search field has focus.

**MIDI**
- [ ] Note On with velocity > 0 triggers; velocity 0 is treated as Note Off.
- [ ] Notes map as `note:<0-based channel>:<note>` and display as `CH<1-based> N:<note>`.
- [ ] Debounce, when set, suppresses repeats of the **same action** within the window.
- [ ] A photo rated 4 lights star pads 1–4; the rate-0 pad lights only at rating 0.
- [ ] View-mode pads light per §13.6, including `toggleViewMode` lighting in **single** mode.
- [ ] Keyword pads light exactly when the anchor photo carries that keyword.
- [ ] **Releasing a pad does not extinguish it** when it should stay lit (Q3).
- [ ] Changing the selection updates all LEDs within one frame.

**UI**
- [ ] Window minimum 800 × 600; panels 200–300 / min 400 / 250–350.
- [ ] Panels hide and show, and the state persists across launches.
- [ ] Grid columns 1–10 via slider; cells square, fill-cropped, top-aligned; 3 pt accent border on selection.
- [ ] Grid spacing controls both gaps and outer padding.
- [ ] Centre background colour is configurable and persists.
- [ ] Empty filtered set shows "No Photos Found".
- [ ] Single view shows `<n> / <total>` in the bottom bar.
- [ ] Tapping the current star rating clears it to 0.
- [ ] The rule editor offers exactly the five rule types of §9.7 and resets the operator when the type changes.
- [ ] The Settings window is 600 × 500 with the three tabs of §9.9.

**Menus**
- [ ] `⇧⌘N`, `⇧⌘O`, `⇧⌘I` work and are not remappable.
- [ ] Photo and View menu items display the user's current key bindings and update when they change.
- [ ] Items are enabled/disabled exactly per §14.

