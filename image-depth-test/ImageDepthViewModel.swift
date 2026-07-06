//
//  ImageDepthViewModel.swift
//  image-depth-test
//

import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class ImageDepthViewModel {
    @ObservationIgnored private let depthEstimator: any DepthEstimating
    @ObservationIgnored private var inputCGImage: CGImage?
    @ObservationIgnored private var depthCGImage: CGImage?

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

    init(depthEstimator: any DepthEstimating) {
        self.depthEstimator = depthEstimator
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
            let depthCGImage = try await depthEstimator.estimateDepth(for: cgImage)
            self.depthCGImage = depthCGImage
            depthImage = Self.makePlatformImage(from: depthCGImage)
        } catch {
            errorMessage = "深度推定に失敗しました"
        }

        isEstimatingDepth = false
    }

    func generateLayerRenderings(layers: [DepthLayerRenderSpec], overlayOpacity: Double) async {
        guard let inputCGImage, let depthCGImage else {
            clearLayerRenderings()
            return
        }

        isGeneratingLayerRenderings = true

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try DepthLayerMasking.makeLayerRenderings(
                    from: inputCGImage,
                    depthImage: depthCGImage,
                    layers: layers,
                    overlayOpacity: overlayOpacity
                )
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
