//
//  ZoomableScrollView.swift
//  image-depth-test
//

import AppKit
import SwiftUI

struct ZoomableScrollViewViewport: Equatable {
    var contentOffset: CGPoint = .zero
    var magnification: CGFloat = 0
}

struct ZoomableScrollView<Content: View>: NSViewRepresentable {
    let contentSize: CGSize
    let contentID: AnyHashable
    let minMagnification: CGFloat
    let maxMagnification: CGFloat
    let synchronizedViewport: Binding<ZoomableScrollViewViewport>?
    @ViewBuilder let content: () -> Content

    init(
        contentSize: CGSize,
        contentID: AnyHashable,
        minMagnification: CGFloat = 0.1,
        maxMagnification: CGFloat = 8,
        synchronizedViewport: Binding<ZoomableScrollViewViewport>? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.contentSize = contentSize
        self.contentID = contentID
        self.minMagnification = minMagnification
        self.maxMagnification = maxMagnification
        self.synchronizedViewport = synchronizedViewport
        self.content = content
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(contentID: contentID, synchronizedViewport: synchronizedViewport)
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
        context.coordinator.installObservers(for: scrollView)

        DispatchQueue.main.async {
            fitContent(in: scrollView, contentSize: contentSize)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        scrollView.minMagnification = minMagnification
        scrollView.maxMagnification = maxMagnification
        context.coordinator.synchronizedViewport = synchronizedViewport
        context.coordinator.hostingView?.rootView = content()
        context.coordinator.hostingView?.frame = NSRect(origin: .zero, size: contentSize)
        context.coordinator.applySynchronizedViewportIfNeeded(to: scrollView, contentSize: contentSize)

        guard context.coordinator.contentID != contentID else { return }
        context.coordinator.contentID = contentID

        DispatchQueue.main.async {
            fitContent(in: scrollView, contentSize: contentSize)
        }
    }

    final class Coordinator {
        var contentID: AnyHashable
        var synchronizedViewport: Binding<ZoomableScrollViewViewport>?
        weak var hostingView: NSHostingView<Content>?
        private var boundsObserver: NSObjectProtocol?
        private var isApplyingSynchronizedViewport = false

        init(contentID: AnyHashable, synchronizedViewport: Binding<ZoomableScrollViewViewport>?) {
            self.contentID = contentID
            self.synchronizedViewport = synchronizedViewport
        }

        deinit {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
        }

        func installObservers(for scrollView: NSScrollView) {
            scrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: scrollView.contentView,
                queue: .main
            ) { [weak self, weak scrollView] _ in
                guard let self, let scrollView else { return }
                self.publishViewport(from: scrollView)
            }
        }

        func applySynchronizedViewportIfNeeded(to scrollView: NSScrollView, contentSize: CGSize) {
            guard let viewport = synchronizedViewport?.wrappedValue,
                  viewport.magnification > 0,
                  !isApplyingSynchronizedViewport else {
                return
            }

            let currentViewport = ZoomableScrollViewViewport(
                contentOffset: scrollView.contentView.bounds.origin,
                magnification: scrollView.magnification
            )
            guard !currentViewport.isNearlyEqual(to: viewport) else { return }

            isApplyingSynchronizedViewport = true
            let magnification = min(max(viewport.magnification, scrollView.minMagnification), scrollView.maxMagnification)
            if abs(scrollView.magnification - magnification) > 0.0001 {
                scrollView.magnification = magnification
            }

            let constrainedOffset = constrained(
                viewport.contentOffset,
                for: scrollView,
                contentSize: contentSize
            )
            scrollView.contentView.scroll(to: constrainedOffset)
            scrollView.reflectScrolledClipView(scrollView.contentView)
            isApplyingSynchronizedViewport = false
        }

        private func publishViewport(from scrollView: NSScrollView) {
            guard let synchronizedViewport,
                  !isApplyingSynchronizedViewport else {
                return
            }

            let viewport = ZoomableScrollViewViewport(
                contentOffset: scrollView.contentView.bounds.origin,
                magnification: scrollView.magnification
            )
            guard !synchronizedViewport.wrappedValue.isNearlyEqual(to: viewport) else { return }
            synchronizedViewport.wrappedValue = viewport
        }

        private func constrained(_ offset: CGPoint, for scrollView: NSScrollView, contentSize: CGSize) -> CGPoint {
            let visibleSize = scrollView.contentView.bounds.size
            return CGPoint(
                x: min(max(offset.x, 0), max(0, contentSize.width - visibleSize.width)),
                y: min(max(offset.y, 0), max(0, contentSize.height - visibleSize.height))
            )
        }
    }
}

private extension ZoomableScrollViewViewport {
    func isNearlyEqual(to other: ZoomableScrollViewViewport) -> Bool {
        abs(contentOffset.x - other.contentOffset.x) < 0.5
            && abs(contentOffset.y - other.contentOffset.y) < 0.5
            && abs(magnification - other.magnification) < 0.0001
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
