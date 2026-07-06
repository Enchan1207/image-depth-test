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

    private(set) var selectedFileName: String?
    private(set) var inputImage: NSImage?
    private(set) var depthImage: NSImage?
    private(set) var isLoadingImage = false
    private(set) var isEstimatingDepth = false
    private(set) var errorMessage: String?

    var hasSelectedImage: Bool {
        inputImage != nil
    }

    init(depthEstimator: any DepthEstimating) {
        self.depthEstimator = depthEstimator
    }

    func loadImage(from url: URL?) async {
        guard let url else { return }

        selectedFileName = url.lastPathComponent
        inputImage = nil
        depthImage = nil
        errorMessage = nil
        isLoadingImage = true

        do {
            let image = try await Self.loadPlatformImage(from: url)
            inputImage = image
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

        depthImage = nil
        errorMessage = nil
        isEstimatingDepth = true

        do {
            let depthCGImage = try await depthEstimator.estimateDepth(for: cgImage)
            depthImage = NSImage(
                cgImage: depthCGImage,
                size: NSSize(width: depthCGImage.width, height: depthCGImage.height)
            )
        } catch {
            errorMessage = "深度推定に失敗しました"
        }

        isEstimatingDepth = false
    }

    func clearSelection() {
        selectedFileName = nil
        inputImage = nil
        depthImage = nil
        errorMessage = nil
        isLoadingImage = false
        isEstimatingDepth = false
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
