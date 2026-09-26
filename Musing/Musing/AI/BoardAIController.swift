import SwiftUI
import UIKit

/// Where the canvas should look after an AI action.
enum AIReveal {
    case card(UUID)
    case wholeBoard
}

/// Remembers card positions from before "Organize" so it can be undone.
struct OrganizeUndo {
    let boardID: UUID
    let positions: [UUID: CGPoint]
    let createdCardIDs: [UUID]
}

/// Runs AI actions for one board: gathers the board's content, calls the backend, and turns results into cards.
@MainActor
@Observable
final class BoardAIController {
    enum Sheet: String, Identifiable {
        case setup, account
        var id: String { rawValue }
    }

    var sheet: Sheet?
    var errorMessage: String?
    var showAskPrompt = false
    var askDraft = ""
    private(set) var runningLabel: String?
    private(set) var organizeUndo: OrganizeUndo?

    @ObservationIgnored private var task: Task<Void, Never>?
    /// The action to retry once setup (consent + sign-in) finishes.
    @ObservationIgnored private var pending: (() -> Void)?

    var isRunning: Bool { runningLabel != nil }

    func perform(
        _ action: AIAction,
        cardID: UUID? = nil,
        question: String? = nil,
        boardID: UUID,
        store: BoardStore,
        account: AccountStore,
        reveal: @escaping (AIReveal) -> Void
    ) {
        guard !isRunning else { return }
        guard AIConfig.backendURL != nil else {
            errorMessage = APIError.notConfigured.localizedDescription
            return
        }
        let retry: () -> Void = { [weak self] in
            self?.perform(action, cardID: cardID, question: question, boardID: boardID,
                          store: store, account: account, reveal: reveal)
        }
        guard account.hasConsented, account.isSignedIn else {
            pending = retry
            sheet = .setup
            return
        }
        guard let board = store.board(boardID) else { return }
        let focus = cardID.flatMap { store.card($0, in: boardID) }
        let request: AIRequest
        do {
            request = try Self.makeRequest(action, board: board, focus: focus, question: question, store: store)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        organizeUndo = nil
        runningLabel = action.progressLabel
        task = Task {
            defer {
                runningLabel = nil
                task = nil
            }
            do {
                let result = try await account.run(request)
                try Task.checkCancellation()
                if let target = apply(result, for: action, focus: focus, question: question, boardID: boardID, store: store) {
                    reveal(target)
                }
            } catch is CancellationError {
            } catch let error as URLError where error.code == .cancelled {
            } catch APIError.unauthorized {
                pending = retry
                sheet = .setup
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func cancel() {
        task?.cancel()
    }

    /// Called when the setup sheet finishes (consent given and signed in).
    func setupCompleted() {
        sheet = nil
        let next = pending
        pending = nil
        next?()
    }

    func setupCancelled() {
        sheet = nil
        pending = nil
    }

    func undoOrganize(store: BoardStore) {
        guard let undo = organizeUndo else { return }
        withAnimation(.snappy) {
            for (cardID, point) in undo.positions {
                store.update(cardID, in: undo.boardID) {
                    $0.x = point.x
                    $0.y = point.y
                }
            }
            for cardID in undo.createdCardIDs {
                store.delete(cardID, in: undo.boardID)
            }
        }
        organizeUndo = nil
    }

    func dismissUndo() {
        organizeUndo = nil
    }

    // MARK: - Building requests

    enum RequestError: LocalizedError {
        case emptyBoard, missingImage, emptyNote

        var errorDescription: String? {
            switch self {
            case .emptyBoard: "Add a few cards to this board first."
            case .missingImage: "This card's image couldn't be read."
            case .emptyNote: "Write something in this note first."
            }
        }
    }

    private static let maxCards = 400
    private static let maxTextLength = 8000

    static func makeRequest(
        _ action: AIAction,
        board: Board,
        focus: Card?,
        question: String?,
        store: BoardStore
    ) throws -> AIRequest {
        let cards = board.cards.prefix(maxCards).map { card in
            var payload = AIRequest.CardPayload(id: card.id.uuidString, kind: card.kind.rawValue)
            switch card.kind {
            case .text:
                payload.text = String(card.text.prefix(maxTextLength))
            case .link:
                payload.url = card.url.map { String($0.prefix(2000)) }
                payload.linkTitle = card.linkTitle.map { String($0.prefix(500)) }
            case .board:
                payload.childTitle = card.boardID.flatMap { store.board($0)?.title }.map { String($0.prefix(200)) }
            case .ink, .image:
                break
            }
            return payload
        }
        var request = AIRequest(
            action: action,
            board: .init(title: String(board.title.prefix(200)), cards: Array(cards))
        )
        switch action {
        case .summarize, .organize:
            if cards.isEmpty { throw RequestError.emptyBoard }
        case .expand:
            guard let focus, !focus.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw RequestError.emptyNote
            }
            request.focusCardId = focus.id.uuidString
        case .handwriting, .photoNotes:
            guard let focus, let image = imagePayload(for: focus, store: store) else { throw RequestError.missingImage }
            request.focusCardId = focus.id.uuidString
            request.image = image
        case .ask:
            request.question = question.map { String($0.prefix(1000)) }
        }
        return request
    }

    /// A JPEG of an ink or photo card, sized for Claude's vision input.
    private static func imagePayload(for card: Card, store: BoardStore) -> AIRequest.ImagePayload? {
        let source: UIImage? = switch card.kind {
        case .ink: store.inkImage(for: card)?.flattened(on: .white)
        case .image: card.imageFile.flatMap { store.image(named: $0) }
        default: nil
        }
        guard let data = source?.downscaled(maxDimension: 1568).jpegData(compressionQuality: 0.8) else { return nil }
        return .init(mediaType: "image/jpeg", data: data.base64EncodedString())
    }

    // MARK: - Applying results

    private func apply(
        _ result: AIResult,
        for action: AIAction,
        focus: Card?,
        question: String?,
        boardID: UUID,
        store: BoardStore
    ) -> AIReveal? {
        guard let board = store.board(boardID) else { return nil }
        let bounds = board.cards.bounds ?? CGRect(x: 40, y: 40, width: 0, height: 0)
        let besideBoard = CGPoint(x: bounds.maxX + 60, y: bounds.minY)

        switch action {
        case .summarize:
            let text = [result.title, result.summary].compactMap { $0 }.joined(separator: "\n\n")
            return .card(addNote(text, at: besideBoard, width: 300, color: .yellow, boardID: boardID, store: store))

        case .ask:
            let text = "Q: \(question ?? "")\n\n\(result.answer ?? "")"
            return .card(addNote(text, at: besideBoard, width: 300, color: .blue, boardID: boardID, store: store))

        case .expand:
            guard let focus, let ideas = result.ideas, !ideas.isEmpty else { return nil }
            let width = 200.0
            let columns = 3
            var ids: [UUID] = []
            var rowTop = focus.y + focus.height + 40
            for row in stride(from: 0, to: ideas.count, by: columns) {
                let slice = ideas[row..<min(row + columns, ideas.count)]
                var rowHeight = 0.0
                for (column, idea) in slice.enumerated() {
                    let origin = CGPoint(x: focus.x + Double(column) * (width + 20), y: rowTop)
                    let id = addNote(idea, at: origin, width: width, color: .green, boardID: boardID, store: store)
                    rowHeight = max(rowHeight, store.card(id, in: boardID)?.height ?? 0)
                    ids.append(id)
                }
                rowTop += rowHeight + 20
            }
            return ids.first.map(AIReveal.card)

        case .handwriting:
            guard let focus, let text = result.text else { return nil }
            let origin = CGPoint(x: focus.x + focus.width + 30, y: focus.y)
            return .card(addNote(text, at: origin, width: 240, color: .paper, boardID: boardID, store: store))

        case .photoNotes:
            guard let focus, let notes = result.notes, !notes.isEmpty else { return nil }
            var top = focus.y
            var first: UUID?
            for note in notes {
                let id = addNote(note, at: CGPoint(x: focus.x + focus.width + 30, y: top), width: 220,
                                 color: .yellow, boardID: boardID, store: store)
                first = first ?? id
                top += (store.card(id, in: boardID)?.height ?? 80) + 16
            }
            return first.map(AIReveal.card)

        case .organize:
            guard let groups = result.groups, !groups.isEmpty else { return nil }
            organize(board: board, groups: groups, origin: CGPoint(x: bounds.minX, y: bounds.minY), store: store)
            return .wholeBoard
        }
    }

    /// Lays the board out as one column per group, each under a header card; ungrouped cards go last.
    private func organize(board: Board, groups: [AIResult.Group], origin: CGPoint, store: BoardStore) {
        let cardsByID = Dictionary(uniqueKeysWithValues: board.cards.map { ($0.id, $0) })
        var columns: [(title: String, cards: [Card])] = groups.map { group -> (title: String, cards: [Card]) in
            let cards = group.cardIds.compactMap { id -> Card? in
                guard let uuid = UUID(uuidString: id) else { return nil }
                return cardsByID[uuid]
            }
            return (title: group.title, cards: cards)
        }
        let grouped = Set(columns.flatMap { $0.cards.map(\.id) })
        let others = board.cards.filter { !grouped.contains($0.id) }
        if !others.isEmpty { columns.append((title: "Other", cards: others)) }

        var positions: [UUID: CGPoint] = [:]
        var created: [UUID] = []
        var x = origin.x
        withAnimation(.snappy) {
            for column in columns where !column.cards.isEmpty {
                let width = max(220, column.cards.map(\.width).max() ?? 220)
                let header = addNote(column.title, at: CGPoint(x: x, y: origin.y), width: width,
                                     color: .purple, boardID: board.id, store: store)
                created.append(header)
                var y = origin.y + (store.card(header, in: board.id)?.height ?? 60) + 20
                for card in column.cards {
                    positions[card.id] = CGPoint(x: card.x, y: card.y)
                    store.update(card.id, in: board.id) {
                        $0.x = x
                        $0.y = y
                    }
                    y += card.height + 16
                }
                x += width + 60
            }
        }
        organizeUndo = OrganizeUndo(boardID: board.id, positions: positions, createdCardIDs: created)
    }

    private func addNote(
        _ text: String,
        at origin: CGPoint,
        width: Double,
        color: CardColor,
        boardID: UUID,
        store: BoardStore
    ) -> UUID {
        let height = max(60, BoardStore.textHeight(text, width: width))
        var card = Card(kind: .text, x: origin.x, y: origin.y, width: width, height: height, color: color)
        card.text = text
        return store.add(card, to: boardID).id
    }
}

extension UIImage {
    /// Draws the image over a solid background, e.g. transparent ink onto white paper.
    func flattened(on color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(at: .zero)
        }
    }
}
