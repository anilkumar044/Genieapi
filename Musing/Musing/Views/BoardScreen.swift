import SwiftUI
import PhotosUI
import PencilKit

private struct InkTarget: Identifiable {
    let id: UUID
}

/// One board: an infinite, zoomable canvas of cards plus the tools to add and arrange them.
struct BoardScreen: View {
    let boardID: UUID
    @Binding var path: [UUID]
    let zoomNamespace: Namespace.ID

    @Environment(BoardStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var viewport = Viewport()
    @State private var didLoadViewport = false
    @State private var canvasSize: CGSize = .zero
    @State private var panBase: CGSize?
    @State private var zoomBase: Viewport?

    @State private var selection: UUID?
    @State private var editingTextID: UUID?
    @State private var dropTargetID: UUID?
    @State private var suppressTapsUntil = Date.distantPast
    @State private var placementNudge = 0

    @State private var inkTarget: InkTarget?
    @State private var showPhotoPicker = false
    @State private var photoItem: PhotosPickerItem?
    @State private var showLinkPrompt = false
    @State private var linkDraft = ""
    @State private var confirmDeleteBoard = false

    private let space = "board-canvas"

    private var board: Board? { store.board(boardID) }
    private var selectedCard: Card? { selection.flatMap { store.card($0, in: boardID) } }

    var body: some View {
        GeometryReader { geometry in
            canvas
                .onAppear {
                    canvasSize = geometry.size
                    loadViewportIfNeeded()
                }
                .onChange(of: geometry.size) { _, size in canvasSize = size }
        }
        .ignoresSafeArea(edges: .bottom)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .navigationTitle(titleBinding)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { topToolbar }
        .safeAreaInset(edge: .bottom) {
            if editingTextID == nil { bottomBar }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            Task { await importPhoto(item) }
        }
        .alert("Add Link", isPresented: $showLinkPrompt) {
            TextField("https://example.com", text: $linkDraft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { linkDraft = "" }
            Button("Add", action: addLinkFromDraft)
        }
        .confirmationDialog("Delete this board and everything inside it?", isPresented: $confirmDeleteBoard, titleVisibility: .visible) {
            Button("Delete Board", role: .destructive, action: deleteSelection)
        }
        .fullScreenCover(item: $inkTarget) { target in
            InkEditor(
                initialDrawing: store.card(target.id, in: boardID)?.drawing
                    .flatMap { try? PKDrawing(data: $0) } ?? PKDrawing(),
                onDone: { drawing in
                    finishInk(target.id, drawing: drawing)
                    inkTarget = nil
                },
                onCancel: {
                    cancelInk(target.id)
                    inkTarget = nil
                }
            )
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.impact(weight: .light), trigger: dropTargetID) { _, new in new != nil }
        .onDisappear { persistViewport() }
    }

    // MARK: - Canvas

    @ViewBuilder
    private var canvas: some View {
        if let board {
            ZStack(alignment: .topLeading) {
                DotGrid(viewport: viewport)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { location in
                        addText(centeredAt: viewport.toCanvas(location))
                    }
                    .onTapGesture { clearSelection() }
                    .gesture(panGesture)

                ZStack(alignment: .topLeading) {
                    ForEach(board.cards) { card in
                        cardView(card)
                    }
                }
                .scaleEffect(viewport.scale, anchor: .topLeading)
                .offset(viewport.offset)

                if board.cards.isEmpty {
                    emptyHint
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .coordinateSpace(.named(space))
            .simultaneousGesture(zoomGesture)
        } else {
            ContentUnavailableView("Board Not Found", systemImage: "questionmark.square.dashed")
        }
    }

    private func cardView(_ card: Card) -> some View {
        CardView(
            card: card,
            boardID: boardID,
            scale: viewport.scale,
            isSelected: selection == card.id,
            isEditing: editingTextID == card.id,
            isDropTarget: dropTargetID == card.id,
            zoomNamespace: zoomNamespace,
            coordinateSpace: space,
            onTap: { tap(card) },
            onLongPress: { longPress(card) },
            onDragChanged: { origin in drag(card, to: origin) },
            onDragEnded: { endDrag(card) },
            onResize: { size in resize(card, to: size) },
            onResizeEnded: { store.scheduleSave() }
        )
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.largeTitle)
            Text("Double-tap anywhere to add a note,\nor use the toolbar below.")
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    // MARK: - Pan & zoom

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(space))
            .onChanged { value in
                // A pinch owns the viewport while it is active.
                guard zoomBase == nil else {
                    panBase = nil
                    return
                }
                let base = panBase ?? viewport.offset - value.translation
                panBase = base
                viewport.offset = base + value.translation
            }
            .onEnded { _ in
                panBase = nil
                persistViewport()
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0.005)
            .onChanged { value in
                let base = zoomBase ?? viewport
                zoomBase = base
                let anchor = value.startLocation
                let scale = (base.scale * value.magnification).clamped(to: Viewport.minScale...Viewport.maxScale)
                // Keep the canvas point under the fingers fixed while zooming.
                let pinned = base.toCanvas(anchor)
                viewport = Viewport(
                    offset: CGSize(width: anchor.x - pinned.x * scale, height: anchor.y - pinned.y * scale),
                    scale: scale
                )
            }
            .onEnded { _ in
                zoomBase = nil
                persistViewport()
            }
    }

    private func loadViewportIfNeeded() {
        guard !didLoadViewport else { return }
        didLoadViewport = true
        if let saved = board?.viewport {
            viewport = saved
        } else {
            zoomToFit(animated: false)
        }
    }

    private func persistViewport() {
        store.setViewport(viewport, for: boardID)
    }

    private func zoomToFit(animated: Bool = true) {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return }
        var target = Viewport()
        if let bounds = board?.cards.bounds {
            let margin: CGFloat = 32
            let scale = min(
                (canvasSize.width - margin * 2) / bounds.width,
                (canvasSize.height - margin * 2) / bounds.height,
                1
            ).clamped(to: Viewport.minScale...Viewport.maxScale)
            target = Viewport(
                offset: CGSize(
                    width: canvasSize.width / 2 - bounds.midX * scale,
                    height: canvasSize.height / 2 - bounds.midY * scale
                ),
                scale: scale
            )
        }
        if animated {
            withAnimation(.snappy) { viewport = target }
        } else {
            viewport = target
        }
        persistViewport()
    }

    private func zoomToActualSize() {
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let pinned = viewport.toCanvas(center)
        withAnimation(.snappy) {
            viewport = Viewport(offset: CGSize(width: center.x - pinned.x, height: center.y - pinned.y), scale: 1)
        }
        persistViewport()
    }

    /// Pans (and zooms in if needed) so a note being edited sits above the keyboard.
    private func revealForEditing(_ card: Card) {
        let top = viewport.toScreen(CGPoint(x: card.x, y: card.y))
        let needsZoom = viewport.scale < 0.8
        let offscreen = top.y > canvasSize.height * 0.35 || top.y < 0
            || top.x < 0 || top.x + card.width * viewport.scale > canvasSize.width
        guard needsZoom || offscreen else { return }
        let scale = max(viewport.scale, 1)
        withAnimation(.snappy) {
            viewport = Viewport(
                offset: CGSize(
                    width: canvasSize.width / 2 - (card.x + card.width / 2) * scale,
                    height: 110 - card.y * scale
                ),
                scale: scale
            )
        }
    }

    // MARK: - Card interaction

    private func tap(_ card: Card) {
        guard Date.now >= suppressTapsUntil else { return }
        if card.kind == .board, let childID = card.boardID {
            setEditing(nil)
            selection = nil
            persistViewport()
            path.append(childID)
            return
        }
        if selection == card.id {
            activate(card)
        } else {
            setEditing(nil)
            selection = card.id
        }
    }

    private func longPress(_ card: Card) {
        suppressTapsUntil = .now.addingTimeInterval(0.6)
        setEditing(nil)
        selection = card.id
    }

    /// Second tap on a selected card: edit text, open the sketchpad or follow the link.
    private func activate(_ card: Card) {
        switch card.kind {
        case .text:
            setEditing(card.id)
            revealForEditing(card)
        case .ink:
            inkTarget = InkTarget(id: card.id)
        case .link:
            if let string = card.url, let url = URL(string: string) { openURL(url) }
        case .image, .board:
            break
        }
    }

    private func drag(_ card: Card, to origin: CGPoint) {
        guard zoomBase == nil else { return }
        if selection != card.id {
            setEditing(nil)
            selection = card.id
        }
        store.update(card.id, in: boardID) {
            $0.x = origin.x
            $0.y = origin.y
        }
        let center = CGPoint(x: origin.x + card.width / 2, y: origin.y + card.height / 2)
        dropTargetID = board?.cards.last { other in
            other.id != card.id && other.kind == .board && other.frame.contains(center)
        }?.id
    }

    private func endDrag(_ card: Card) {
        defer { dropTargetID = nil }
        if let targetID = dropTargetID,
           let target = store.card(targetID, in: boardID),
           let childBoardID = target.boardID {
            withAnimation(.snappy) {
                store.move(card.id, from: boardID, into: childBoardID)
                selection = nil
            }
        } else {
            store.bringToFront(card.id, in: boardID)
        }
    }

    private func resize(_ card: Card, to size: CGSize) {
        store.update(card.id, in: boardID) { card in
            card.width = max(size.width, 80)
            if card.kind == .image, let name = card.imageFile, let image = store.image(named: name), image.size.width > 0 {
                card.height = card.width * Double(image.size.height / image.size.width)
            } else {
                card.height = max(size.height, 50)
            }
        }
    }

    private func clearSelection() {
        setEditing(nil)
        selection = nil
    }

    /// Switches which text card is being edited, tidying up the one that was.
    private func setEditing(_ cardID: UUID?) {
        if let previous = editingTextID, previous != cardID, let card = store.card(previous, in: boardID) {
            if card.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.delete(previous, in: boardID)
                if selection == previous { selection = nil }
            } else {
                let needed = BoardStore.textHeight(card.text, width: card.width)
                if needed > card.height {
                    store.update(previous, in: boardID) { $0.height = needed }
                }
            }
        }
        editingTextID = cardID
    }

    // MARK: - Adding cards

    /// Where a card added from the toolbar goes: the visible center, nudged so repeats don't stack exactly.
    private func nextPlacement() -> CGPoint {
        let center = viewport.toCanvas(CGPoint(x: canvasSize.width / 2, y: canvasSize.height * 0.42))
        let nudge = CGFloat(placementNudge % 5) * 20
        placementNudge += 1
        return CGPoint(x: center.x + nudge, y: center.y + nudge)
    }

    private func addText(centeredAt point: CGPoint) {
        let card = store.addText(centeredAt: point, in: boardID)
        selection = card.id
        setEditing(card.id)
        revealForEditing(card)
    }

    private func addInk() {
        clearSelection()
        let card = store.addInk(centeredAt: nextPlacement(), in: boardID)
        selection = card.id
        inkTarget = InkTarget(id: card.id)
    }

    private func addBoard() {
        clearSelection()
        let card = store.addBoard(centeredAt: nextPlacement(), in: boardID)
        selection = card.id
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        clearSelection()
        selection = store.addImage(image, centeredAt: nextPlacement(), in: boardID).id
    }

    private func addLinkFromDraft() {
        defer { linkDraft = "" }
        guard let url = Self.webURL(from: linkDraft) else { return }
        clearSelection()
        selection = store.addLink(url, centeredAt: nextPlacement(), in: boardID).id
    }

    private func paste() {
        let pasteboard = UIPasteboard.general
        clearSelection()
        if let image = pasteboard.image {
            selection = store.addImage(image, centeredAt: nextPlacement(), in: boardID).id
        } else if let url = pasteboard.url, let web = Self.webURL(from: url.absoluteString) {
            selection = store.addLink(web, centeredAt: nextPlacement(), in: boardID).id
        } else if let string = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            if !string.contains(" "), !string.contains("\n"), string.contains("."), let url = Self.webURL(from: string) {
                selection = store.addLink(url, centeredAt: nextPlacement(), in: boardID).id
            } else {
                selection = store.addText(string, centeredAt: nextPlacement(), in: boardID).id
            }
        }
    }

    private static func webURL(from input: String) -> URL? {
        var string = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }
        if !string.lowercased().hasPrefix("http://") && !string.lowercased().hasPrefix("https://") {
            string = "https://" + string
        }
        guard let url = URL(string: string), let host = url.host(), host.contains(".") else { return nil }
        return url
    }

    private func finishInk(_ cardID: UUID, drawing: PKDrawing) {
        guard !drawing.strokes.isEmpty else {
            store.delete(cardID, in: boardID)
            if selection == cardID { selection = nil }
            return
        }
        let bounds = drawing.bounds
        store.update(cardID, in: boardID) { card in
            card.drawing = drawing.dataRepresentation()
            if bounds.width > 0 {
                card.height = (card.width * Double(bounds.height / bounds.width)).clamped(to: 60...900)
            }
        }
    }

    private func cancelInk(_ cardID: UUID) {
        // A brand-new ink card that was never drawn on shouldn't linger.
        if store.card(cardID, in: boardID)?.drawing == nil {
            store.delete(cardID, in: boardID)
            if selection == cardID { selection = nil }
        }
    }

    // MARK: - Selection actions

    private func deleteSelection() {
        guard let id = selection else { return }
        setEditing(nil)
        withAnimation(.snappy) {
            store.delete(id, in: boardID)
            selection = nil
        }
    }

    private func requestDelete(_ card: Card) {
        if card.kind == .board, let childID = card.boardID, !(store.board(childID)?.cards.isEmpty ?? true) {
            confirmDeleteBoard = true
        } else {
            deleteSelection()
        }
    }

    // MARK: - Toolbars

    private var titleBinding: Binding<String> {
        Binding(
            get: { store.board(boardID)?.title ?? "" },
            set: { store.rename(boardID, to: $0) }
        )
    }

    @ToolbarContentBuilder
    private var topToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Zoom to Fit", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { zoomToFit() }
                Button("Actual Size", systemImage: "1.magnifyingglass") { zoomToActualSize() }
                if path.count > 1 {
                    Button("Go to Home", systemImage: "house") { path.removeAll() }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") { setEditing(nil) }
                .fontWeight(.semibold)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 2) {
            if let card = selectedCard {
                selectionTools(for: card)
            } else {
                addTools
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.2), value: selection)
    }

    @ViewBuilder
    private var addTools: some View {
        ToolButton("Note", systemImage: "note.text") { addText(centeredAt: nextPlacement()) }
        ToolButton("Ink", systemImage: "scribble.variable", action: addInk)
        ToolButton("Photo", systemImage: "photo") { showPhotoPicker = true }
        ToolButton("Link", systemImage: "link") { showLinkPrompt = true }
        ToolButton("Board", systemImage: "square.stack.3d.up", action: addBoard)
        ToolButton("Paste", systemImage: "doc.on.clipboard", action: paste)
    }

    @ViewBuilder
    private func selectionTools(for card: Card) -> some View {
        switch card.kind {
        case .text:
            ToolButton("Edit", systemImage: "pencil") { activate(card) }
        case .ink:
            ToolButton("Draw", systemImage: "pencil.tip") { activate(card) }
        case .link:
            ToolButton("Open", systemImage: "safari") { activate(card) }
        case .board:
            ToolButton("Open", systemImage: "arrow.up.left.and.arrow.down.right") {
                if let id = card.boardID {
                    selection = nil
                    persistViewport()
                    path.append(id)
                }
            }
        case .image:
            EmptyView()
        }
        if card.kind != .image {
            Menu {
                ForEach(CardColor.allCases) { color in
                    Button {
                        store.update(card.id, in: boardID) { $0.color = color }
                    } label: {
                        Label(color.name, systemImage: color == card.color ? "checkmark.circle.fill" : "circle")
                    }
                }
            } label: {
                ToolIcon(systemImage: "paintpalette")
            }
            .accessibilityLabel("Color")
        }
        ToolButton("Duplicate", systemImage: "plus.square.on.square") {
            if let copy = store.duplicate(card.id, in: boardID) { selection = copy.id }
        }
        if let parentID = board?.parentID {
            ToolButton("Move to Parent Board", systemImage: "arrow.up.square") {
                withAnimation(.snappy) {
                    store.move(card.id, from: boardID, into: parentID)
                    selection = nil
                }
            }
        }
        ToolButton("Delete", systemImage: "trash", role: .destructive) { requestDelete(card) }
        ToolButton("Deselect", systemImage: "xmark") { clearSelection() }
    }
}

// MARK: - Small building blocks

private struct ToolIcon: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 19, weight: .medium))
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
    }
}

private struct ToolButton: View {
    let title: String
    let systemImage: String
    var role: ButtonRole?
    let action: () -> Void

    init(_ title: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            ToolIcon(systemImage: systemImage)
        }
        .foregroundStyle(role == .destructive ? Color.red : Color.primary)
        .accessibilityLabel(title)
    }
}

/// The dotted paper the canvas sits on; it moves and scales with the viewport.
struct DotGrid: View {
    let viewport: Viewport

    var body: some View {
        Canvas { context, size in
            var spacing = 28 * viewport.scale
            while spacing < 14 { spacing *= 2 }
            while spacing > 56 { spacing /= 2 }
            let radius: CGFloat = 1.1
            let startX = positiveRemainder(viewport.offset.width, spacing)
            let startY = positiveRemainder(viewport.offset.height, spacing)
            var dots = Path()
            var x = startX
            while x < size.width {
                var y = startY
                while y < size.height {
                    dots.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                    y += spacing
                }
                x += spacing
            }
            context.fill(dots, with: .color(Color(.tertiaryLabel)))
        }
        .background(Color(.systemGroupedBackground))
    }

    private func positiveRemainder(_ value: CGFloat, _ divisor: CGFloat) -> CGFloat {
        let remainder = value.truncatingRemainder(dividingBy: divisor)
        return remainder < 0 ? remainder + divisor : remainder
    }
}
