//
//  ImageDepthViewModel.swift
//  image-depth-test
//

import Foundation
import Observation
import SwiftUI

import AppKit

@MainActor
@Observable
final class ImageDepthViewModel {
    private(set) var selectedFileName: String?
    private(set) var inputImage: NSImage?
    private(set) var depthImage: NSImage?
    private(set) var isLoadingImage = false
    private(set) var errorMessage: String?

    var hasSelectedImage: Bool {
        inputImage != nil
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
    }

    func clearSelection() {
        selectedFileName = nil
        inputImage = nil
        depthImage = nil
        errorMessage = nil
        isLoadingImage = false
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
