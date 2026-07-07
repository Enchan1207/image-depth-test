//
//  MaskEditorWindowRegistry.swift
//  image-depth-test
//

import AppKit
import SwiftUI

@MainActor
final class MaskEditorWindowRegistry {
    private var controllersByLayerID: [UUID: MaskEditorWindowController] = [:]

    func openEditor(
        layerID: UUID,
        layerName: String,
        layerColor: NSColor,
        inputImage: CGImage,
        initialMask: CGImage,
        onSave: @escaping (CGImage) -> Void
    ) {
        if let controller = controllersByLayerID[layerID] {
            controller.show()
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let session = MaskEditorSession(
            layerID: layerID,
            layerName: layerName,
            layerColor: layerColor,
            inputImage: inputImage,
            initialMask: initialMask,
            onSave: onSave
        )
        let controller = MaskEditorWindowController(session: session) { [weak self] closedLayerID in
            self?.controllersByLayerID.removeValue(forKey: closedLayerID)
        }

        controllersByLayerID[layerID] = controller
        controller.show()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeAllDiscardingChanges() {
        let controllers = Array(controllersByLayerID.values)
        controllersByLayerID.removeAll()

        for controller in controllers {
            controller.closeDiscardingChanges()
        }
    }
}

@MainActor
private final class MaskEditorWindowController: NSObject, NSWindowDelegate {
    private let session: MaskEditorSession
    private let onClose: (UUID) -> Void
    private let window: NSWindow
    private var isClosingFromSession = false

    init(session: MaskEditorSession, onClose: @escaping (UUID) -> Void) {
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

        window.title = "マスク編集 - \(session.layerName)"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: MaskEditorView(session: session))
        window.delegate = self
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
    }

    func closeDiscardingChanges() {
        session.markChangesDiscarded()
        closeFromSession()
    }

    private func closeFromSession() {
        isClosingFromSession = true
        window.close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if isClosingFromSession {
            return true
        }

        return session.confirmClose()
    }

    func windowWillClose(_ notification: Notification) {
        session.onRequestClose = nil
        window.delegate = nil
        window.contentView = nil
        onClose(session.layerID)
    }
}
