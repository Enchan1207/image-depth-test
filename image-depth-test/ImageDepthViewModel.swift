//
//  ImageDepthViewModel.swift
//  image-depth-test
//

import AppKit
import CoreVideo
import Foundation
import Observation

@MainActor
@Observable
final class ImageDepthViewModel {
    @ObservationIgnored private let depthEstimator: any DepthEstimating
    @ObservationIgnored private let layerRenderer: any DepthLayerRendering
    @ObservationIgnored private var inputCGImage: CGImage?
    @ObservationIgnored private var depthCGImage: CGImage?
    @ObservationIgnored private var depthPixelBuffer: CVPixelBuffer?

    private(set) var selectedFileName: String?
    private(set) var inputImage: NSImage?
    private(set) var depthImage: NSImage?
    private(set) var layerPreviewImage: NSImage?
    private(set) var layerOverlayImage: NSImage?
    private(set) var layerCutoutImages: [NSImage] = []
    private(set) var isLoadingImage = false
    private(set) var isEstimatingDepth = false
    private(set) var isGeneratingLayerRenderings = false
    private(set) var errorMessage: String?

    var hasSelectedImage: Bool {
        inputImage != nil
    }

    var canGenerateLayerRenderings: Bool {
        inputCGImage != nil && depthCGImage != nil
    }

    var canEditLayerMasks: Bool {
        inputCGImage != nil && depthCGImage != nil && !layerCutoutImages.isEmpty
    }

    init(depthEstimator: any DepthEstimating, layerRenderer: any DepthLayerRendering) {
        self.depthEstimator = depthEstimator
        self.layerRenderer = layerRenderer
    }

    func loadImage(from url: URL?) async {
        guard let url else { return }

        selectedFileName = url.lastPathComponent
        clearImages()
        errorMessage = nil
        isLoadingImage = true

        do {
            let image = try await Self.loadPlatformImage(from: url)
            inputImage = image
            inputCGImage = image.cgImageForInference()
        } catch {
            selectedFileName = nil
            errorMessage = "画像を読み込めませんでした"
        }

        isLoadingImage = false

        if inputImage != nil {
            await estimateDepthForSelectedImage()
        }
    }

    func estimateDepthForSelectedImage() async {
        guard let inputImage else { return }

        guard let cgImage = inputImage.cgImageForInference() else {
            errorMessage = "画像を推論用に変換できませんでした"
            return
        }

        inputCGImage = cgImage
        clearDepthOutputs()
        errorMessage = nil
        isEstimatingDepth = true

        do {
            let result = try await depthEstimator.estimateDepth(for: cgImage)
            self.depthCGImage = result.depthImage
            self.depthPixelBuffer = result.depthPixelBuffer
            depthImage = Self.makePlatformImage(from: result.depthImage)
        } catch {
            errorMessage = "深度推定に失敗しました"
        }

        isEstimatingDepth = false
    }

    func makeInitialMask(for layer: DepthLayerRenderSpec) async -> CGImage? {
        guard let depthCGImage else { return nil }

        do {
            return try await Task.detached(priority: .userInitiated) {
                try DepthLayerMasking.makeMask(from: depthCGImage, range: layer.range)
            }.value
        } catch {
            errorMessage = "マスク画像の生成に失敗しました"
            return nil
        }
    }

    func inputCGImageForEditing() -> CGImage? {
        inputCGImage
    }

    func generateLayerRenderings(
        layers: [DepthLayerRenderSpec],
        overlayOpacity: Double,
        editedMasksByLayerID: [UUID: CGImage] = [:],
        layerIDsByIndex: [UUID] = []
    ) async {
        guard let inputCGImage, let depthCGImage else {
            clearLayerRenderings()
            return
        }

        isGeneratingLayerRenderings = true

        do {
            let renderer = layerRenderer
            let depthPixelBuffer = depthPixelBuffer
            let result = try await Task.detached(priority: .userInitiated) {
                var result = try renderer.makeLayerRenderings(
                    from: inputCGImage,
                    depthImage: depthCGImage,
                    depthPixelBuffer: depthPixelBuffer,
                    layers: layers,
                    overlayOpacity: overlayOpacity
                )

                if !editedMasksByLayerID.isEmpty {
                    var cutouts = result.cutouts
                    for layer in layers where layerIDsByIndex.indices.contains(layer.index) {
                        let layerID = layerIDsByIndex[layer.index]
                        guard let mask = editedMasksByLayerID[layerID],
                              cutouts.indices.contains(layer.index) else {
                            continue
                        }

                        cutouts[layer.index] = try DepthLayerMasking.apply(mask: mask, to: inputCGImage)
                    }

                    result = DepthLayerRenderingResult(
                        layerPreview: result.layerPreview,
                        overlayPreview: result.overlayPreview,
                        cutouts: cutouts
                    )
                }

                return result
            }.value

            layerPreviewImage = Self.makePlatformImage(from: result.layerPreview)
            layerOverlayImage = Self.makePlatformImage(from: result.overlayPreview)
            layerCutoutImages = result.cutouts.map(Self.makePlatformImage)
            errorMessage = nil
        } catch {
            clearLayerRenderings()
            errorMessage = "レイヤ画像の生成に失敗しました"
        }

        isGeneratingLayerRenderings = false
    }

    func generateLayerPreviews(layers: [DepthLayerRenderSpec], overlayOpacity: Double) async {
        guard let inputCGImage, let depthCGImage else {
            clearLayerRenderings()
            return
        }

        isGeneratingLayerRenderings = true

        do {
            let renderer = layerRenderer
            let depthPixelBuffer = depthPixelBuffer
            let result = try await Task.detached(priority: .userInitiated) {
                try renderer.makePreviewRenderings(
                    from: inputCGImage,
                    depthImage: depthCGImage,
                    depthPixelBuffer: depthPixelBuffer,
                    layers: layers,
                    overlayOpacity: overlayOpacity
                )
            }.value

            layerPreviewImage = Self.makePlatformImage(from: result.layerPreview)
            layerOverlayImage = Self.makePlatformImage(from: result.overlayPreview)
            errorMessage = nil
        } catch {
            layerPreviewImage = nil
            layerOverlayImage = nil
            errorMessage = "レイヤプレビューの生成に失敗しました"
        }

        isGeneratingLayerRenderings = false
    }

    func suggestDepthBoundaries(layerCount: Int) async -> [Double]? {
        guard let depthCGImage else { return nil }

        do {
            return try await Task.detached(priority: .userInitiated) {
                try DepthLayerMasking.suggestBoundaries(
                    from: depthCGImage,
                    layerCount: layerCount
                )
            }.value
        } catch {
            errorMessage = "深度レンジの自動分割に失敗しました"
            return nil
        }
    }

    func clearSelection() {
        selectedFileName = nil
        clearImages()
        errorMessage = nil
        isLoadingImage = false
        isEstimatingDepth = false
        isGeneratingLayerRenderings = false
    }

    private func clearImages() {
        inputImage = nil
        inputCGImage = nil
        clearDepthOutputs()
    }

    private func clearDepthOutputs() {
        depthImage = nil
        depthCGImage = nil
        depthPixelBuffer = nil
        clearLayerRenderings()
    }

    private func clearLayerRenderings() {
        layerPreviewImage = nil
        layerOverlayImage = nil
        layerCutoutImages = []
    }

    private static func loadPlatformImage(from url: URL) async throws -> NSImage {
        try await Task.detached(priority: .userInitiated) {
            let canAccessResource = url.startAccessingSecurityScopedResource()
            defer {
                if canAccessResource {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let data = try Data(contentsOf: url)
            guard let image = NSImage(data: data) else {
                throw ImageLoadError.unsupportedImageData
            }

            return image
        }.value
    }

    private static func makePlatformImage(from cgImage: CGImage) -> NSImage {
        NSImage(
            cgImage: cgImage,
            size: NSSize(width: cgImage.width, height: cgImage.height)
        )
    }
}

private enum ImageLoadError: Error {
    case unsupportedImageData
}

private extension NSImage {
    func cgImageForInference() -> CGImage? {
        var proposedRect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &proposedRect, context: nil, hints: nil)
    }
}
