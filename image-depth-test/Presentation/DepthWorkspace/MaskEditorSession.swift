//
//  MaskEditorSession.swift
//  image-depth-test
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class MaskEditorSession {
    @ObservationIgnored private let inputImage: CGImage
    @ObservationIgnored private let baseMask: CGImage
    @ObservationIgnored private let onSave: (CGImage) -> Void
    @ObservationIgnored var onRequestClose: (() -> Void)?

    let layerID: UUID
    let layerName: String
    let imageSize: CGSize
    let baseMaskImage: NSImage
    let originalImage: NSImage

    var strokes: [MaskStroke] = []
    var tool: MaskEditorTool = .pencil
    var brushSize: Double = 28
    private(set) var currentMask: CGImage
    private(set) var currentMaskImage: NSImage
    private(set) var maskedPreviewImage: NSImage
    private(set) var hasUnsavedChanges = false
    private(set) var errorMessage: String?

    init(
        layerID: UUID,
        layerName: String,
        inputImage: CGImage,
        initialMask: CGImage,
        onSave: @escaping (CGImage) -> Void
    ) {
        self.layerID = layerID
        self.layerName = layerName
        self.inputImage = inputImage
        self.baseMask = initialMask
        self.onSave = onSave
        self.imageSize = CGSize(width: inputImage.width, height: inputImage.height)
        self.baseMaskImage = Self.makePlatformImage(from: initialMask)
        self.originalImage = Self.makePlatformImage(from: inputImage)
        self.currentMask = initialMask
        self.currentMaskImage = Self.makePlatformImage(from: initialMask)

        if let preview = try? DepthLayerMasking.apply(mask: initialMask, to: inputImage) {
            self.maskedPreviewImage = Self.makePlatformImage(from: preview)
        } else {
            self.maskedPreviewImage = Self.makePlatformImage(from: inputImage)
        }
    }

    func updateStrokes(_ strokes: [MaskStroke]) {
        self.strokes = strokes
        hasUnsavedChanges = true
        rebuildMask()
    }

    func save() {
        onSave(currentMask)
        hasUnsavedChanges = false
    }

    func saveAndClose() {
        save()
        onRequestClose?()
    }

    func discardAndClose() {
        markChangesDiscarded()
        onRequestClose?()
    }

    func markChangesDiscarded() {
        hasUnsavedChanges = false
    }

    func confirmClose() -> Bool {
        guard hasUnsavedChanges else { return true }

        let alert = NSAlert()
        alert.messageText = "マスク編集を保存しますか？"
        alert.informativeText = "\(layerName) の未保存の編集があります。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "破棄")
        alert.addButton(withTitle: "キャンセル")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            save()
            return true
        case .alertSecondButtonReturn:
            hasUnsavedChanges = false
            return true
        default:
            return false
        }
    }

    private func rebuildMask() {
        do {
            let mask = try MaskDrawingRasterizer.makeEditedMask(
                baseMask: baseMask,
                strokes: strokes,
                size: imageSize
            )
            let preview = try DepthLayerMasking.apply(mask: mask, to: inputImage)
            currentMask = mask
            currentMaskImage = Self.makePlatformImage(from: mask)
            maskedPreviewImage = Self.makePlatformImage(from: preview)
            errorMessage = nil
        } catch {
            errorMessage = "マスクの更新に失敗しました"
        }
    }

    private static func makePlatformImage(from cgImage: CGImage) -> NSImage {
        NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}
