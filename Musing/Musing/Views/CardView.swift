import SwiftUI

extension CardColor {
    var fill: Color {
        switch self {
        case .paper: Color(red: 1.00, green: 1.00, blue: 0.99)
        case .yellow: Color(red: 1.00, green: 0.95, blue: 0.69)
        case .pink: Color(red: 1.00, green: 0.85, blue: 0.88)
        case .blue: Color(red: 0.85, green: 0.92, blue: 1.00)
        case .green: Color(red: 0.86, green: 0.96, blue: 0.83)
        case .purple: Color(red: 0.91, green: 0.87, blue: 1.00)
        }
    }
}

/// A card placed on the canvas: renders its content and handles tap, long-press, drag and resize.
struct CardView: View {
    let card: Card
    let boardID: UUID
    let scale: CGFloat
    let isSelected: Bool
    let isEditing: Bool
    let isDropTarget: Bool
    let zoomNamespace: Namespace.ID
    let coordinateSpace: String

    var onTap: () -> Void
    var onLongPress: () -> Void
    var onDragChanged: (CGPoint) -> Void
    var onDragEnded: () -> Void
    var onResize: (CGSize) -> Void
    var onResizeEnded: () -> Void

    @State private var dragStart: CGPoint? = nil
    @State private var resizeStart: CGSize? = nil

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }
    /// While editing text, let the text view get touches instead of our gestures.
    private var gestureMask: GestureMask { isEditing ? .subviews : .all }

    var body: some View {
        content
            .frame(width: card.width, height: card.height)
            .background(card.kind == .image ? Color.black : card.color.fill)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(
                    isSelected || isDropTarget ? Color.accentColor : Color.black.opacity(0.08),
                    lineWidth: (isSelected || isDropTarget ? 2.5 : 1) / scale
                )
            }
            .shadow(color: .black.opacity(isSelected ? 0.22 : 0.10), radius: isSelected ? 12 : 4, y: isSelected ? 6 : 2)
            .overlay(alignment: .bottomTrailing) {
                if isSelected && !isEditing { resizeHandle }
            }
            .environment(\.colorScheme, .light)
            .scaleEffect(isDropTarget ? 1.06 : 1)
            .animation(.snappy(duration: 0.2), value: isDropTarget)
            .matchedTransitionSource(id: card.boardID ?? card.id, in: zoomNamespace)
            .offset(x: card.x, y: card.y)
            .gesture(TapGesture().onEnded { onTap() }, including: gestureMask)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in onLongPress() },
                including: gestureMask
            )
            .gesture(dragGesture, including: gestureMask)
    }

    @ViewBuilder
    private var content: some View {
        switch card.kind {
        case .text:
            TextCardContent(card: card, boardID: boardID, isEditing: isEditing)
        case .ink:
            InkCardContent(card: card)
        case .image:
            ImageCardContent(card: card)
        case .link:
            LinkCardContent(card: card)
        case .board:
            BoardCardContent(card: card)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                let start = dragStart ?? CGPoint(x: card.x, y: card.y)
                dragStart = start
                onDragChanged(CGPoint(
                    x: start.x + value.translation.width / scale,
                    y: start.y + value.translation.height / scale
                ))
            }
            .onEnded { _ in
                dragStart = nil
                onDragEnded()
            }
    }

    private var resizeHandle: some View {
        Circle()
            .fill(Color.accentColor)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .frame(width: 18, height: 18)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .scaleEffect(1 / scale)
            .offset(x: 22, y: 22)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named(coordinateSpace))
                    .onChanged { value in
                        let start = resizeStart ?? CGSize(width: card.width, height: card.height)
                        resizeStart = start
                        onResize(CGSize(
                            width: start.width + value.translation.width / scale,
                            height: start.height + value.translation.height / scale
                        ))
                    }
                    .onEnded { _ in
                        resizeStart = nil
                        onResizeEnded()
                    }
            )
    }
}

// MARK: - Card contents

private struct TextCardContent: View {
    @Environment(BoardStore.self) private var store
    let card: Card
    let boardID: UUID
    let isEditing: Bool
    @FocusState private var focused: Bool

    var body: some View {
        if isEditing {
            TextEditor(text: Binding(
                get: { store.card(card.id, in: boardID)?.text ?? "" },
                set: { newText in store.update(card.id, in: boardID) { $0.text = newText } }
            ))
            .font(.system(size: 16))
            .foregroundStyle(.black)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .focused($focused)
            .onAppear { focused = true }
        } else {
            Text(card.text.isEmpty ? "Empty note" : card.text)
                .font(.system(size: 16))
                .foregroundStyle(card.text.isEmpty ? Color.gray : Color.black)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(12)
        }
    }
}

private struct InkCardContent: View {
    @Environment(BoardStore.self) private var store
    let card: Card

    var body: some View {
        if let image = store.inkImage(for: card) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            placeholder(systemImage: "scribble.variable", text: "Tap again to draw")
        }
    }
}

private struct ImageCardContent: View {
    @Environment(BoardStore.self) private var store
    let card: Card

    var body: some View {
        if let name = card.imageFile, let image = store.image(named: name) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: card.width, height: card.height)
                .clipped()
        } else {
            placeholder(systemImage: "photo", text: "Missing image")
        }
    }
}

private struct LinkCardContent: View {
    let card: Card

    private var host: String {
        card.url.flatMap { URL(string: $0)?.host() } ?? "Link"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(host, systemImage: "link")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
                .lineLimit(1)
            Text(card.linkTitle ?? card.url ?? "")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.black)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct BoardCardContent: View {
    @Environment(BoardStore.self) private var store
    let card: Card

    var body: some View {
        let child = card.boardID.flatMap { store.board($0) }
        VStack(spacing: 0) {
            BoardThumbnail(cards: child?.cards ?? [])
                .background(Color.black.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .padding(6)
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up.fill")
                    .foregroundStyle(Color.accentColor)
                Text(child?.title ?? "Board")
                    .fontWeight(.semibold)
                    .foregroundStyle(.black)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(child?.cards.count ?? 0)")
                    .foregroundStyle(.gray)
            }
            .font(.system(size: 14))
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
        }
    }
}

/// A miniature map of a board's cards.
struct BoardThumbnail: View {
    let cards: [Card]

    var body: some View {
        Canvas { context, size in
            guard let bounds = cards.bounds, bounds.width > 0, bounds.height > 0 else { return }
            let padding: CGFloat = 8
            let scale = min(
                (size.width - padding * 2) / bounds.width,
                (size.height - padding * 2) / bounds.height,
                0.5
            )
            let originX = (size.width - bounds.width * scale) / 2 - bounds.minX * scale
            let originY = (size.height - bounds.height * scale) / 2 - bounds.minY * scale
            for card in cards {
                let rect = CGRect(
                    x: card.x * scale + originX,
                    y: card.y * scale + originY,
                    width: max(card.width * scale, 2),
                    height: max(card.height * scale, 2)
                )
                let path = Path(roundedRect: rect, cornerRadius: 2)
                let fill: Color = switch card.kind {
                case .image: Color(white: 0.55)
                case .board: Color(white: 0.8)
                default: card.color.fill
                }
                context.fill(path, with: .color(fill))
                context.stroke(path, with: .color(.black.opacity(0.15)), lineWidth: 0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func placeholder(systemImage: String, text: String) -> some View {
    VStack(spacing: 6) {
        Image(systemName: systemImage).font(.title2)
        Text(text).font(.caption)
    }
    .foregroundStyle(.gray)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
}
