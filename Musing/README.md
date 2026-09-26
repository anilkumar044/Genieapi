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
- **Offline & private** — boards are stored locally in the app's Documents folder (`library.json` + `Images/`).
- **AI actions (optional, runs on AWS)** — powered by Claude on Amazon Bedrock through the backend in [`backend/`](backend/README.md):
  - ✨ menu on any board: **Summarize Board**, **Organize Board** (groups cards into titled columns, with Undo), **Ask About Board**
  - ✨ on a selected card: **Expand with AI** (notes), **Read Handwriting** (sketches), **Photo to Notes** (photos)
  - Results arrive as new cards on the canvas. The AI runs on AWS, not on the phone, and only the current board is sent,
    only when you tap an action.

## Requirements

- A Mac with **Xcode 16** or newer
- An iPhone (or iPad) on **iOS 18** or newer
- An **Apple Developer Program** membership. The app uses Sign in with Apple for its AI features, and that
  capability isn't available to free Apple IDs. (To try the app on a free Apple ID without AI, delete
  `Musing.entitlements` and the `CODE_SIGN_ENTITLEMENTS` build setting.)
- For AI features: an AWS account with Amazon Bedrock. See [`backend/README.md`](backend/README.md)

## Run it on your iPhone

1. Open `Musing/Musing.xcodeproj` in Xcode.
2. Select the **Musing** target → **Signing & Capabilities** → choose your **Team** (add your Apple ID under
   *Xcode → Settings → Accounts* if needed). If Xcode complains the bundle ID is taken, change
   `com.example.musing` to something unique like `com.yourname.musing`.
3. Plug in your iPhone (or pair it over Wi-Fi), select it as the run destination, and press **⌘R**.
4. First time only: on the iPhone, enable **Settings → Privacy & Security → Developer Mode**, and trust your
   developer certificate under **Settings → General → VPN & Device Management**.

You can also press ⌘R with an iPhone simulator selected to try it without a device. To test Sign in with Apple
there, sign in to an Apple ID in the simulator's Settings app.

### Turn on AI features

1. Deploy the backend: follow [`backend/README.md`](backend/README.md) (`npx cdk deploy -c bundleId=<your bundle ID>`).
2. Paste the `ApiUrl` output into `Musing/AI/AIConfig.swift`.
3. Run the app and tap ✨. The first time, Musing explains what gets shared, asks permission, and asks you to
   Sign in with Apple.

### App Store readiness (already handled)

- **Consent before sharing** (guideline 5.1.2): the setup screen says exactly what is sent and to whom
  (Anthropic's Claude on Amazon Bedrock), and nothing is sent without permission. The permission can be turned
  off in **✨ → AI Account**.
- **Account deletion** (5.1.1(v)): **AI Account → Delete Account** removes the server-side account and revokes Sign in with Apple.
- **Privacy manifest**: `PrivacyInfo.xcprivacy` declares the user ID and the content sent for app functionality.
  Match these in App Store Connect's privacy labels.

## Project layout

```
Musing/
├── Musing.xcodeproj
└── Musing/
    ├── MusingApp.swift          App entry point, saves when backgrounded
    ├── AI/AIConfig.swift        Backend URL (paste after deploying)
    ├── AI/MusingAPI.swift       HTTP client + request/result types for the backend
    ├── AI/AccountStore.swift    Sign in with Apple session, consent, usage
    ├── AI/BoardAIController.swift  Builds AI requests from a board and turns results into cards
    ├── Views/AIViews.swift      AI setup (consent + sign-in) and AI Account screens
    ├── Model/Models.swift       Card, Board, Viewport, Library (Codable)
    ├── Store/BoardStore.swift   Observable store: CRUD, move/duplicate, persistence, image & ink caches
    ├── Views/RootView.swift     NavigationStack of boards with zoom transitions
    ├── Views/BoardScreen.swift  The canvas: pan/zoom, selection, drag-to-file, toolbars
    ├── Views/CardView.swift     Card rendering (note, ink, photo, link, board) + gestures
    ├── Views/InkEditor.swift    PencilKit sketchpad
    ├── Assets.xcassets          App icon and accent color
    ├── Musing.entitlements      Sign in with Apple
    └── PrivacyInfo.xcprivacy    Privacy manifest
backend/                         AWS CDK app: Lambda + DynamoDB + Claude on Amazon Bedrock
```

The Xcode project uses folder-synchronized groups, so any Swift file you add under `Musing/Musing/`
is picked up automatically.

## Ideas for next steps

- iCloud sync (swap the JSON file for SwiftData + CloudKit)
- Share extension to send links/photos from Safari and Photos straight into an inbox board
- Freehand ink directly on the board, connecting lines/arrows between cards
- PDF cards and search across all boards
