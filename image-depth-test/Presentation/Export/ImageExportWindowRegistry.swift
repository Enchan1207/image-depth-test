//
//  ImageExportWindowRegistry.swift
//  image-depth-test
//

import AppKit
import SwiftUI

@MainActor
final class ImageExportWindowRegistry {
    private var controller: ImageExportWindowController?

    func openExportWindow(layers: [ExportLayerSelection], suggestedFileName: String) {
        if let controller {
            controller.show()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let session = ImageExportSession(layers: layers, suggestedFileName: suggestedFileName)
        let controller = ImageExportWindowController(session: session) { [weak self] in
            self?.controller = nil
        }
        self.controller = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class ImageExportWindowController: NSObject, NSWindowDelegate {
    private let session: ImageExportSession
    private let onClose: () -> Void
    private let window: NSWindow
    private var isClosingFromSession = false

    init(session: ImageExportSession, onClose: @escaping () -> Void) {
        self.session = session
        self.onClose = onClose
        self.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1120, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()

        session.onRequestClose = { [weak self] in
            self?.closeFromSession()
        }

        window.title = "画像エクスポート"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ImageExportView(session: session))
        window.delegate = self
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    private func closeFromSession() {
        isClosingFromSession = true
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        !isClosingFromSession || !session.isExporting
    }

    func windowWillClose(_ notification: Notification) {
        session.onRequestClose = nil
        window.delegate = nil
        window.contentView = nil
        onClose()
    }
}
