//
//  PaintEditor.swift
//  HyperPad
//

import PencilKit
import SwiftUI

/// Full-screen paint mode for the current card: a PencilKit canvas at the
/// card's logical size with the system tool picker. Strokes live in
/// logical card coordinates, so the drawing scales with the card.
struct PaintEditor: View {
    let cardSize: CardSize
    let initialDrawing: PKDrawing
    var onDone: (PKDrawing) -> Void

    @State private var drawing: PKDrawing
    @Environment(\.dismiss) private var dismiss

    init(cardSize: CardSize, initialDrawing: PKDrawing, onDone: @escaping (PKDrawing) -> Void) {
        self.cardSize = cardSize
        self.initialDrawing = initialDrawing
        self.onDone = onDone
        _drawing = State(initialValue: initialDrawing)
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let scale = min(proxy.size.width / cardSize.width, proxy.size.height / cardSize.height)
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(.systemBackground))
                        .shadow(radius: 8)
                    PaintCanvas(drawing: $drawing)
                }
                .frame(width: cardSize.width, height: cardSize.height)
                .scaleEffect(scale)
                .frame(width: cardSize.width * scale, height: cardSize.height * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding()
            .background(Color(.secondarySystemBackground))
            .navigationTitle("Paint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear", systemImage: "trash") {
                        drawing = PKDrawing()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(drawing)
                        dismiss()
                    }
                }
            }
        }
    }
}

/// PKCanvasView wrapper: transparent, accepts finger and Pencil, shows
/// the system tool picker while first responder.
private struct PaintCanvas: UIViewRepresentable {
    @Binding var drawing: PKDrawing

    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.drawing = drawing
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        canvas.drawingPolicy = .anyInput
        canvas.delegate = context.coordinator
        let picker = context.coordinator.toolPicker
        picker.setVisible(true, forFirstResponder: canvas)
        picker.addObserver(canvas)
        Task { @MainActor in
            canvas.becomeFirstResponder()
        }
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        if canvas.drawing != drawing {
            canvas.drawing = drawing
        }
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let toolPicker = PKToolPicker()
        private let drawing: Binding<PKDrawing>

        init(drawing: Binding<PKDrawing>) {
            self.drawing = drawing
        }

        nonisolated func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            MainActor.assumeIsolated {
                drawing.wrappedValue = canvasView.drawing
            }
        }
    }
}
