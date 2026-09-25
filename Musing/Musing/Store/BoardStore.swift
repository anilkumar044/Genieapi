import SwiftUI
import UIKit
import PencilKit
import LinkPresentation

/// Owns the library of boards, persists it as JSON in Documents, and stores image files.
@MainActor
@Observable
final class BoardStore {
    private(set) var library: Library

    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let imageCache = NSCache<NSString, UIImage>()
    @ObservationIgnored private var inkCache: [UUID: (data: Data, image: UIImage)] = [:]

    private static let libraryURL = URL.documentsDirectory.appending(path: "library.json")
    private static let imagesURL = URL.documentsDirectory.appending(path: "Images", directoryHint: .isDirectory)

    init() {
        try? FileManager.default.createDirectory(at: Self.imagesURL, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: Self.libraryURL),
           let saved = try? JSONDecoder().decode(Library.self, from: data),
           saved.boards[saved.rootID] != nil {
            library = saved
        } else {
            library = Self.makeWelcomeLibrary()
            save()
        }
    }

    // MARK: - Boards

    var rootID: UUID { library.rootID }

    func board(_ id: UUID) -> Board? { library.boards[id] }

    func rename(_ boardID: UUID, to title: String) {
        library.boards[boardID]?.title = title
        scheduleSave()
    }

    func setViewport(_ viewport: Viewport, for boardID: UUID) {
        guard library.boards[boardID]?.viewport != viewport else { return }
        library.boards[boardID]?.viewport = viewport
        scheduleSave()
    }

    // MARK: - Cards

    func card(_ cardID: UUID, in boardID: UUID) -> Card? {
        library.boards[boardID]?.cards.first { $0.id == cardID }
    }

    func update(_ cardID: UUID, in boardID: UUID, _ body: (inout Card) -> Void) {
        guard let index = index(of: cardID, in: boardID) else { return }
        body(&library.boards[boardID]!.cards[index])
        scheduleSave()
    }

    @discardableResult
    func add(_ card: Card, to boardID: UUID) -> Card {
        library.boards[boardID]?.cards.append(card)
        scheduleSave()
        return card
    }

    func addText(_ text: String = "", centeredAt center: CGPoint, in boardID: UUID) -> Card {
        let width: Double = 220
        let height = max(110, Self.textHeight(text, width: width))
        var card = Card(kind: .text, x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        card.text = text
        return add(card, to: boardID)
    }

    func addInk(centeredAt center: CGPoint, in boardID: UUID) -> Card {
        add(Card(kind: .ink, x: center.x - 130, y: center.y - 100, width: 260, height: 200), to: boardID)
    }

    func addBoard(centeredAt center: CGPoint, in parentID: UUID) -> Card {
        let child = Board(title: "Untitled Board", parentID: parentID)
        library.boards[child.id] = child
        var card = Card(kind: .board, x: center.x - 90, y: center.y - 75, width: 180, height: 150)
        card.boardID = child.id
        return add(card, to: parentID)
    }

    func addImage(_ image: UIImage, centeredAt center: CGPoint, in boardID: UUID) -> Card {
        let scaled = image.downscaled(maxDimension: 2048)
        let name = UUID().uuidString + ".jpg"
        if let data = scaled.jpegData(compressionQuality: 0.85) {
            try? data.write(to: imageURL(name), options: .atomic)
        }
        imageCache.setObject(scaled, forKey: name as NSString)

        let aspect = Double(scaled.size.height / max(scaled.size.width, 1))
        var width: Double = 240
        var height = width * aspect
        if height > 320 { height = 320; width = height / aspect }
        var card = Card(kind: .image, x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        card.imageFile = name
        return add(card, to: boardID)
    }

    func addLink(_ url: URL, centeredAt center: CGPoint, in boardID: UUID) -> Card {
        var card = Card(kind: .link, x: center.x - 130, y: center.y - 50, width: 260, height: 100, color: .blue)
        card.url = url.absoluteString
        let added = add(card, to: boardID)
        Task { await fetchTitle(for: added.id, in: boardID, url: url) }
        return added
    }

    func delete(_ cardID: UUID, in boardID: UUID) {
        guard let index = index(of: cardID, in: boardID) else { return }
        let card = library.boards[boardID]!.cards.remove(at: index)
        purge(card)
        scheduleSave()
    }

    @discardableResult
    func duplicate(_ cardID: UUID, in boardID: UUID) -> Card? {
        guard let original = card(cardID, in: boardID) else { return nil }
        var copy = deepCopy(original, parentID: boardID)
        copy.x += 24
        copy.y += 24
        return add(copy, to: boardID)
    }

    func bringToFront(_ cardID: UUID, in boardID: UUID) {
        guard let index = index(of: cardID, in: boardID),
              index != library.boards[boardID]!.cards.count - 1 else { return }
        let card = library.boards[boardID]!.cards.remove(at: index)
        library.boards[boardID]!.cards.append(card)
        scheduleSave()
    }

    /// Moves a card from one board into another, placing it below the target's existing content.
    func move(_ cardID: UUID, from boardID: UUID, into targetID: UUID) {
        guard boardID != targetID,
              library.boards[targetID] != nil,
              let index = index(of: cardID, in: boardID) else { return }
        var card = library.boards[boardID]!.cards.remove(at: index)
        if let bounds = library.boards[targetID]!.cards.bounds {
            card.x = bounds.minX
            card.y = bounds.maxY + 32
        } else {
            card.x = 40
            card.y = 40
        }
        if let childID = card.boardID {
            library.boards[childID]?.parentID = targetID
        }
        library.boards[targetID]!.cards.append(card)
        scheduleSave()
    }

    // MARK: - Images & ink

    func image(named name: String) -> UIImage? {
        if let cached = imageCache.object(forKey: name as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: imageURL(name).path) else { return nil }
        imageCache.setObject(image, forKey: name as NSString)
        return image
    }

    /// Renders an ink card's drawing, cached until the drawing changes.
    func inkImage(for card: Card) -> UIImage? {
        guard let data = card.drawing, !data.isEmpty else { return nil }
        if let cached = inkCache[card.id], cached.data == data { return cached.image }
        guard let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return nil }
        var image = UIImage()
        // Cards are always light "paper", so render ink with light-mode colors.
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            image = drawing.image(from: drawing.bounds.insetBy(dx: -8, dy: -8), scale: 3)
        }
        inkCache[card.id] = (data, image)
        return image
    }

    private func imageURL(_ name: String) -> URL {
        Self.imagesURL.appending(path: name)
    }

    // MARK: - Persistence

    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(library)
            try data.write(to: Self.libraryURL, options: .atomic)
        } catch {
            print("Musing: failed to save library: \(error)")
        }
    }

    // MARK: - Helpers

    /// Height a text card needs to show `text` at the card font.
    static func textHeight(_ text: String, width: Double) -> Double {
        guard !text.isEmpty else { return 0 }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width - 24, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: UIFont.systemFont(ofSize: 16)],
            context: nil
        )
        return ceil(rect.height) + 28
    }

    private func index(of cardID: UUID, in boardID: UUID) -> Int? {
        library.boards[boardID]?.cards.firstIndex { $0.id == cardID }
    }

    /// Removes a card's files and, for board cards, the whole nested board tree.
    private func purge(_ card: Card) {
        if let name = card.imageFile {
            try? FileManager.default.removeItem(at: imageURL(name))
            imageCache.removeObject(forKey: name as NSString)
        }
        inkCache[card.id] = nil
        if let childID = card.boardID, let child = library.boards.removeValue(forKey: childID) {
            child.cards.forEach(purge)
        }
    }

    /// Copies a card, including image files and nested boards.
    private func deepCopy(_ card: Card, parentID: UUID) -> Card {
        var copy = card
        copy.id = UUID()
        if let name = card.imageFile {
            let newName = UUID().uuidString + ".jpg"
            try? FileManager.default.copyItem(at: imageURL(name), to: imageURL(newName))
            copy.imageFile = newName
        }
        if let childID = card.boardID, let child = library.boards[childID] {
            var newBoard = Board(title: child.title, parentID: parentID, viewport: child.viewport)
            let newBoardID = newBoard.id
            newBoard.cards = child.cards.map { deepCopy($0, parentID: newBoardID) }
            library.boards[newBoard.id] = newBoard
            copy.boardID = newBoard.id
        }
        return copy
    }

    private func fetchTitle(for cardID: UUID, in boardID: UUID, url: URL) async {
        guard let metadata = try? await LPMetadataProvider().startFetchingMetadata(for: url),
              let title = metadata.title, !title.isEmpty else { return }
        update(cardID, in: boardID) { $0.linkTitle = title }
    }

    private static func makeWelcomeLibrary() -> Library {
        var ideas = Board(title: "Ideas")
        var home = Board(title: "Home")
        ideas.parentID = home.id

        var nested = Card(kind: .text, x: 40, y: 40, width: 240, height: 120, color: .green)
        nested.text = "Boards can hold other boards — go as deep as you like.\n\nTap ‹ Home to zoom back out."
        ideas.cards = [nested]

        var welcome = Card(kind: .text, x: 40, y: 40, width: 270, height: 150, color: .yellow)
        welcome.text = "Welcome to Musing ✨\n\nAn infinite canvas for your thinking. Pinch to zoom, drag the background to pan."
        var notes = Card(kind: .text, x: 340, y: 40, width: 240, height: 150)
        notes.text = "Double-tap empty space to write a note.\n\nTap a card to select it, tap again to edit. Drag the corner dot to resize."
        var filing = Card(kind: .text, x: 40, y: 220, width: 270, height: 150, color: .pink)
        filing.text = "Drag any card onto a board to file it inside.\n\nLong-press a board to select it without opening."
        var board = Card(kind: .board, x: 340, y: 220, width: 180, height: 150)
        board.boardID = ideas.id
        home.cards = [welcome, notes, filing, board]

        return Library(rootID: home.id, boards: [home.id: home, ideas.id: ideas])
    }
}

extension UIImage {
    func downscaled(maxDimension: CGFloat) -> UIImage {
        let largest = max(size.width, size.height)
        guard largest > maxDimension else { return self }
        let factor = maxDimension / largest
        let newSize = CGSize(width: size.width * factor, height: size.height * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
