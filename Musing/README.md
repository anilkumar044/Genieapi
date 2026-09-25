# Musing — a Muse-style thinking canvas for iPhone

Musing is a native SwiftUI app inspired by [Muse](https://museapp.com): an infinite, zoomable
canvas where you spread out notes, sketches, photos and links, and nest boards inside boards.

## Features

- **Infinite canvas** — pinch to zoom (10%–600%), drag the background to pan. Each board remembers where you left it.
- **Nested boards** — add a board card, tap it to zoom into it (iOS 18 zoom transition), rename it from the title bar. Boards can go as deep as you like.
- **File by dragging** — drag any card onto a board card to move it inside; use *Move to Parent Board* to bring it back out.
- **Cards**
  - **Notes**: double-tap empty space (or tap *Note*). Tap once to select, tap again to edit.
  - **Ink**: freehand sketches with PencilKit (finger or Apple Pencil), with the full tool picker, undo/redo.
  - **Photos**: from your library via the system photo picker (no permission prompt needed).
  - **Links**: typed or pasted; the page title is fetched automatically. Tap a selected link to open it.
  - **Paste**: images, URLs or text from the clipboard become the right kind of card.
- **Arrange** — drag to move, drag the corner dot to resize (photos keep their aspect ratio), long-press to select, recolor, duplicate (deep-copies nested boards), delete.
- **Offline & private** — everything is stored locally in the app's Documents folder (`library.json` + `Images/`).

## Requirements

- A Mac with **Xcode 16** or newer
- An iPhone (or iPad) on **iOS 18** or newer
- An Apple ID (a free one works for installing on your own device)

## Run it on your iPhone

1. Open `Musing/Musing.xcodeproj` in Xcode.
2. Select the **Musing** target → **Signing & Capabilities** → choose your **Team** (add your Apple ID under
   *Xcode → Settings → Accounts* if needed). If Xcode complains the bundle ID is taken, change
   `com.example.musing` to something unique like `com.yourname.musing`.
3. Plug in your iPhone (or pair it over Wi-Fi), select it as the run destination, and press **⌘R**.
4. First time only: on the iPhone, enable **Settings → Privacy & Security → Developer Mode**, and trust your
   developer certificate under **Settings → General → VPN & Device Management**.

> With a free Apple ID, apps installed this way expire after 7 days — just run it from Xcode again.
> A paid Apple Developer account removes that limit and lets you distribute via TestFlight.

You can also press ⌘R with an iPhone simulator selected to try it without a device.

## Project layout

```
Musing/
├── Musing.xcodeproj
└── Musing/
    ├── MusingApp.swift          App entry point, saves when backgrounded
    ├── Model/Models.swift       Card, Board, Viewport, Library (Codable)
    ├── Store/BoardStore.swift   Observable store: CRUD, move/duplicate, persistence, image & ink caches
    ├── Views/RootView.swift     NavigationStack of boards with zoom transitions
    ├── Views/BoardScreen.swift  The canvas: pan/zoom, selection, drag-to-file, toolbars
    ├── Views/CardView.swift     Card rendering (note, ink, photo, link, board) + gestures
    ├── Views/InkEditor.swift    PencilKit sketchpad
    └── Assets.xcassets          App icon and accent color
```

The Xcode project uses folder-synchronized groups, so any Swift file you add under `Musing/Musing/`
is picked up automatically.

## Ideas for next steps

- iCloud sync (swap the JSON file for SwiftData + CloudKit)
- Share extension to send links/photos from Safari and Photos straight into an inbox board
- Freehand ink directly on the board, connecting lines/arrows between cards
- PDF cards and search across all boards
