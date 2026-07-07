//
//  ZoomableScrollView.swift
//  image-depth-test
//

import AppKit
import SwiftUI

struct ZoomableScrollView<Content: View>: NSViewRepresentable {
    let contentSize: CGSize
    let contentID: AnyHashable
    let minMagnification: CGFloat
    let maxMagnification: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        contentSize: CGSize,
        contentID: AnyHashable,
        minMagnification: CGFloat = 0.1,
        maxMagnification: CGFloat = 8,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.contentSize = contentSize
        self.contentID = contentID
        self.minMagnification = minMagnification
        self.maxMagnification = maxMagnification
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(contentID: contentID)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.contentView = CenteringClipView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = true
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.allowsMagnification = true
        scrollView.minMagnification = minMagnification
        scrollView.maxMagnification = maxMagnification

        let hostingView = NSHostingView(rootView: content())
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        hostingView.autoresizingMask = []
        scrollView.documentView = hostingView
        context.coordinator.hostingView = hostingView

        DispatchQueue.main.async {
            fitContent(in: scrollView, contentSize: contentSize)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.minMagnification = minMagnification
        scrollView.maxMagnification = maxMagnification
        context.coordinator.hostingView?.rootView = content()
        context.coordinator.hostingView?.frame = NSRect(origin: .zero, size: contentSize)

        guard context.coordinator.contentID != contentID else { return }
        context.coordinator.contentID = contentID

        DispatchQueue.main.async {
            fitContent(in: scrollView, contentSize: contentSize)
        }
    }

    final class Coordinator {
        var contentID: AnyHashable
        weak var hostingView: NSHostingView<Content>?

        init(contentID: AnyHashable) {
            self.contentID = contentID
        }
    }
}

private final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var constrainedBounds = super.constrainBoundsRect(proposedBounds)

        guard let documentView else {
            return constrainedBounds
        }

        let documentFrame = documentView.frame
        if documentFrame.width < constrainedBounds.width {
            constrainedBounds.origin.x = floor((documentFrame.width - constrainedBounds.width) / 2)
        }

        if documentFrame.height < constrainedBounds.height {
            constrainedBounds.origin.y = floor((documentFrame.height - constrainedBounds.height) / 2)
        }

        return constrainedBounds
    }
}

private func fitContent(in scrollView: NSScrollView, contentSize: CGSize) {
    guard contentSize.width > 0, contentSize.height > 0 else { return }

    let viewportSize = scrollView.contentView.bounds.size
    guard viewportSize.width > 0, viewportSize.height > 0 else { return }

    let fitScale = min(
        viewportSize.width / contentSize.width,
        viewportSize.height / contentSize.height
    )
    let targetScale = min(max(fitScale, scrollView.minMagnification), scrollView.maxMagnification)
    let center = NSPoint(x: contentSize.width / 2, y: contentSize.height / 2)
    scrollView.setMagnification(targetScale, centeredAt: center)
}
