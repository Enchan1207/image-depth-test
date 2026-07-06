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
    private(set) var selectedLayerCutoutImage: NSImage?
    private(set) var isLoadingImage = false
    private(set) var isEstimatingDepth = false
    private(set) var isGeneratingLayerCutout = false
    private(set) var errorMessage: String?

    var hasSelectedImage: Bool {
        inputImage != nil
    }

    var canGenerateLayerCutout: Bool {
        inputCGImage != nil && depthCGImage != nil
    }

    init(depthEstimator: any DepthEstimating) {
        self.depthEstimator = depthEstimator
    }

    func loadImage(from url: URL?) async {
        guard let url else { return }

        selectedFileName = url.lastPathComponent
        inputImage = nil
        inputCGImage = nil
        depthImage = nil
        depthCGImage = nil
        selectedLayerCutoutImage = nil
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
        depthImage = nil
        depthCGImage = nil
        selectedLayerCutoutImage = nil
        errorMessage = nil
        isEstimatingDepth = true

        do {
            let depthCGImage = try await depthEstimator.estimateDepth(for: cgImage)
            self.depthCGImage = depthCGImage
            depthImage = NSImage(
                cgImage: depthCGImage,
                size: NSSize(width: depthCGImage.width, height: depthCGImage.height)
            )
        } catch {
            errorMessage = "深度推定に失敗しました"
        }

        isEstimatingDepth = false
    }

    func generateLayerCutout(for range: DepthRange) async {
        guard let inputCGImage, let depthCGImage else {
            selectedLayerCutoutImage = nil
            return
        }

        isGeneratingLayerCutout = true

        do {
            let cutoutCGImage = try await Task.detached(priority: .userInitiated) {
                try DepthLayerMasking.makeCutout(
                    from: inputCGImage,
                    depthImage: depthCGImage,
                    range: range
                )
            }.value

            selectedLayerCutoutImage = NSImage(
                cgImage: cutoutCGImage,
                size: NSSize(width: cutoutCGImage.width, height: cutoutCGImage.height)
            )
        } catch {
            selectedLayerCutoutImage = nil
            errorMessage = "レイヤ切り抜きに失敗しました"
        }

        isGeneratingLayerCutout = false
    }

    func clearSelection() {
        selectedFileName = nil
        inputImage = nil
        inputCGImage = nil
        depthImage = nil
        depthCGImage = nil
        selectedLayerCutoutImage = nil
        errorMessage = nil
        isLoadingImage = false
        isEstimatingDepth = false
        isGeneratingLayerCutout = false
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
