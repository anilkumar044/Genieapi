import Foundation
import CoreGraphics

/// The kinds of things you can place on a board.
enum CardKind: String, Codable {
    case text, ink, image, link, board
}

/// Paper colors a card can be tinted with.
enum CardColor: String, Codable, CaseIterable, Identifiable {
    case paper, yellow, pink, blue, green, purple

    var id: String { rawValue }
    var name: String { rawValue.capitalized }
}

/// A single item on a board. Its frame is stored in board ("canvas") coordinates.
struct Card: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: CardKind
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    var color: CardColor = .paper

    /// Text cards.
    var text = ""
    /// Ink cards: `PKDrawing.dataRepresentation()`.
    var drawing: Data?
    /// Image cards: file name inside the app's Images folder.
    var imageFile: String?
    /// Link cards.
    var url: String?
    var linkTitle: String?
    /// Board cards: the nested board this card opens.
    var boardID: UUID?

    var frame: CGRect {
        get { CGRect(x: x, y: y, width: width, height: height) }
        set {
            x = newValue.origin.x
            y = newValue.origin.y
            width = newValue.width
            height = newValue.height
        }
    }

    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }
}

/// Where the camera is looking on a board: screen = offset + canvas * scale.
struct Viewport: Codable, Equatable {
    var offset: CGSize = .zero
    var scale: CGFloat = 1

    static let minScale: CGFloat = 0.1
    static let maxScale: CGFloat = 6

    func toCanvas(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - offset.width) / scale, y: (point.y - offset.height) / scale)
    }

    func toScreen(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.width, y: point.y * scale + offset.height)
    }
}

/// An infinite canvas holding cards. Boards nest inside each other via board cards.
struct Board: Identifiable, Codable {
    var id = UUID()
    var title: String
    var parentID: UUID?
    var cards: [Card] = []
    var viewport: Viewport?
}

/// Everything the app persists.
struct Library: Codable {
    var rootID: UUID
    var boards: [UUID: Board]
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension CGSize {
    static func + (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }

    static func - (lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width - rhs.width, height: lhs.height - rhs.height)
    }
}

extension Array where Element == Card {
    /// Smallest rectangle containing every card, or nil when empty.
    var bounds: CGRect? {
        guard let first else { return nil }
        return dropFirst().reduce(first.frame) { $0.union($1.frame) }
    }
}
