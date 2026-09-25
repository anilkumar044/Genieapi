import SwiftUI
import PencilKit

/// Full-screen PencilKit sketchpad used to create and edit ink cards.
struct InkEditor: View {
    let initialDrawing: PKDrawing
    let onDone: (PKDrawing) -> Void
    let onCancel: () -> Void

    @State private var controller = InkController()

    var body: some View {
        NavigationStack {
            InkCanvas(initialDrawing: initialDrawing, controller: controller)
                .background(CardColor.paper.fill)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Ink")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel", action: onCancel)
                    }
                    ToolbarItem(placement: .principal) {
                        HStack(spacing: 20) {
                            Button { controller.undo() } label: { Image(systemName: "arrow.uturn.backward") }
                                .accessibilityLabel("Undo")
                            Button { controller.redo() } label: { Image(systemName: "arrow.uturn.forward") }
                                .accessibilityLabel("Redo")
                            Button(role: .destructive) { controller.clear() } label: { Image(systemName: "trash") }
                                .accessibilityLabel("Clear")
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { onDone(controller.drawing ?? initialDrawing) }
                            .fontWeight(.semibold)
                    }
                }
        }
        .environment(\.colorScheme, .light)
    }
}

/// Lets SwiftUI buttons drive the underlying PKCanvasView.
@MainActor
final class InkController {
    weak var canvas: PKCanvasView?

    var drawing: PKDrawing? { canvas?.drawing }

    func undo() { canvas?.undoManager?.undo() }
    func redo() { canvas?.undoManager?.redo() }
    func clear() { canvas?.drawing = PKDrawing() }
}

private struct InkCanvas: UIViewRepresentable {
    let initialDrawing: PKDrawing
    let controller: InkController

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = initialDrawing
        canvas.drawingPolicy = .anyInput // draw with a finger on iPhone, or Apple Pencil on iPad
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.overrideUserInterfaceStyle = .light
        canvas.tool = PKInkingTool(.pen, color: .black, width: 4)
        controller.canvas = canvas

        let toolPicker = context.coordinator.toolPicker
        toolPicker.overrideUserInterfaceStyle = .light
        toolPicker.addObserver(canvas)
        toolPicker.setVisible(true, forFirstResponder: canvas)
        DispatchQueue.main.async { canvas.becomeFirstResponder() }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {}

    final class Coordinator {
        let toolPicker = PKToolPicker()
    }
}
