//
//  ImageExportSession.swift
//  image-depth-test
//

import AppKit
import Foundation
import Observation
import UniformTypeIdentifiers

@MainActor
@Observable
final class ImageExportSession {
    @ObservationIgnored var onRequestClose: (() -> Void)?

    let suggestedFileName: String
    let previewContentID: AnyHashable
    private(set) var layers: [ExportLayerSelection]
    private(set) var isExporting = false
    private(set) var errorMessage: String?

    var canExport: Bool {
        layers.contains(where: \.isIncluded) && !isExporting
    }

    init(layers: [ExportLayerSelection], suggestedFileName: String) {
        self.layers = layers
        self.suggestedFileName = suggestedFileName
        self.previewContentID = Self.makePreviewContentID(from: layers)
    }

    func setLayer(_ layerID: UUID, isIncluded: Bool) {
        guard let index = layers.firstIndex(where: { $0.id == layerID }) else { return }
        layers[index].isIncluded = isIncluded
    }

    func cancel() {
        onRequestClose?()
    }

    func export() {
        guard let outputURL = chooseOutputURL() else { return }
        let selectedLayers = includedExportLayers
        guard !selectedLayers.isEmpty else { return }

        isExporting = true
        errorMessage = nil

        do {
            let image = try DepthLayerExporting.makeCompositeImage(from: selectedLayers)
            try PNGImageWriter.write(image, to: outputURL)
            isExporting = false
            onRequestClose?()
        } catch {
            isExporting = false
            errorMessage = "画像のエクスポートに失敗しました"
        }
    }

    private var includedExportLayers: [DepthLayerExportLayer] {
        layers
            .filter(\.isIncluded)
            .map(\.exportLayer)
    }

    private static func makePreviewContentID(from layers: [ExportLayerSelection]) -> AnyHashable {
        guard let firstLayer = layers.first else {
            return "empty-export-preview"
        }

        return "export-preview-\(firstLayer.image.width)x\(firstLayer.image.height)"
    }

    private func chooseOutputURL() -> URL? {
        let panel = NSSavePanel()
        panel.title = "画像を書き出す"
        panel.allowedContentTypes = [.png]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName

        return panel.runModal() == .OK ? panel.url : nil
    }
}
