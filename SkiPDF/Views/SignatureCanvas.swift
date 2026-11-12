import SwiftUI
import PencilKit

/// A drawing surface for signatures (finger or Apple Pencil).
struct SignatureCanvas: UIViewRepresentable {
    final class Model {
        fileprivate weak var view: PKCanvasView?

        func clear() { view?.drawing = PKDrawing() }

        /// The signature cropped to its ink, on a transparent background.
        func image() -> UIImage? {
            guard let d = view?.drawing, !d.strokes.isEmpty else { return nil }
            let r = d.bounds.insetBy(dx: -8, dy: -8)
            // Render in light mode so dark ink stays dark.
            var out: UIImage?
            UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
                out = d.image(from: r, scale: 3)
            }
            return out
        }
    }

    let model: Model
    var color: UIColor

    func makeUIView(context: Context) -> PKCanvasView {
        let v = PKCanvasView()
        v.drawingPolicy = .anyInput
        v.backgroundColor = .clear
        v.isOpaque = false
        v.overrideUserInterfaceStyle = .light
        v.tool = PKInkingTool(.pen, color: color, width: 4)
        model.view = v
        return v
    }

    func updateUIView(_ v: PKCanvasView, context: Context) {
        v.tool = PKInkingTool(.pen, color: color, width: 4)
    }
}
