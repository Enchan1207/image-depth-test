//
//  PencilMaskCanvas.swift
//  image-depth-test
//

import AppKit
import SwiftUI

struct PencilMaskCanvas: NSViewRepresentable {
    @Binding var strokes: [MaskStroke]

    let tool: MaskEditorTool
    let brushSize: Double
    let onDrawingChanged: ([MaskStroke]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> MaskDrawingNSView {
        let drawingView = MaskDrawingNSView()
        drawingView.strokes = strokes
        drawingView.tool = tool
        drawingView.brushSize = brushSize
        drawingView.onDrawingChanged = { nextStrokes in
            strokes = nextStrokes
            onDrawingChanged(nextStrokes)
        }
        return drawingView
    }

    func updateNSView(_ drawingView: MaskDrawingNSView, context: Context) {
        drawingView.strokes = strokes
        drawingView.tool = tool
        drawingView.brushSize = brushSize
        drawingView.onDrawingChanged = { nextStrokes in
            strokes = nextStrokes
            onDrawingChanged(nextStrokes)
        }
        drawingView.needsDisplay = true
    }

    final class Coordinator {
        var parent: PencilMaskCanvas

        init(parent: PencilMaskCanvas) {
            self.parent = parent
        }
    }
}

final class MaskDrawingNSView: NSView {
    var strokes: [MaskStroke] = []
    var tool: MaskEditorTool = .pencil
    var brushSize: Double = 28
    var onDrawingChanged: (([MaskStroke]) -> Void)?

    private var activeStroke: MaskStroke?

    override var isFlipped: Bool {
        true
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func mouseDown(with event: NSEvent) {
        let point = clampedPoint(for: event)
        activeStroke = MaskStroke(tool: tool, brushSize: brushSize, points: [point])
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard activeStroke != nil else { return }

        let point = clampedPoint(for: event)
        activeStroke?.points.append(point)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var stroke = activeStroke else { return }

        let point = clampedPoint(for: event)
        stroke.points.append(point)
        strokes.append(stroke)
        activeStroke = nil
        onDrawingChanged?(strokes)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        NSColor.clear.setFill()
        dirtyRect.fill()

        for stroke in strokes {
            draw(stroke)
        }

        if let activeStroke {
            draw(activeStroke)
        }
    }

    private func draw(_ stroke: MaskStroke) {
        guard let firstPoint = stroke.points.first else { return }

        let path = NSBezierPath()
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.lineWidth = stroke.brushSize

        if stroke.points.count < 2 || stroke.points.allSatisfy({ distance(from: firstPoint, to: $0) < 0.5 }) {
            let radius = stroke.brushSize / 2
            path.appendOval(in: NSRect(
                x: firstPoint.x - radius,
                y: firstPoint.y - radius,
                width: stroke.brushSize,
                height: stroke.brushSize
            ))
            (stroke.tool == .pencil ? NSColor.white : NSColor.black).setFill()
            path.fill()
            return
        }

        path.move(to: firstPoint)
        for point in stroke.points.dropFirst() {
            path.line(to: point)
        }
        (stroke.tool == .pencil ? NSColor.white : NSColor.black).setStroke()
        path.stroke()
    }

    private func clampedPoint(for event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(
            x: min(max(point.x, 0), bounds.width),
            y: min(max(point.y, 0), bounds.height)
        )
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
