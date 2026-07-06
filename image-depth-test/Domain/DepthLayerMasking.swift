//
//  DepthLayerMasking.swift
//  image-depth-test
//

import CoreGraphics
import Foundation

struct DepthRange: Equatable, Sendable {
    let lowerBound: Double
    let upperBound: Double

    init(lowerBound: Double, upperBound: Double) throws {
        guard lowerBound >= 0, upperBound <= 1, lowerBound < upperBound else {
            throw DepthLayerMaskingError.invalidDepthRange
        }

        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    nonisolated func contains(_ value: Double, includesUpperBound: Bool) -> Bool {
        if includesUpperBound {
            return value >= lowerBound && value <= upperBound
        }

        return value >= lowerBound && value < upperBound
    }
}

struct DepthLayerRenderColor: Equatable, Sendable {
    let red: UInt8
    let green: UInt8
    let blue: UInt8

    init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }
}

struct DepthLayerRenderSpec: Equatable, Sendable {
    let index: Int
    let range: DepthRange
    let color: DepthLayerRenderColor
}

struct DepthLayerRenderingResult: Sendable {
    let layerPreview: CGImage
    let overlayPreview: CGImage
    let cutouts: [CGImage]
}

enum DepthLayerMasking {
    nonisolated static func makeMask(from depthImage: CGImage, range: DepthRange) throws -> CGImage {
        let depthSamples = try makeDepthSamples(from: depthImage)
        var maskPixels = [UInt8](repeating: 0, count: depthSamples.pixelCount)

        for pixelIndex in 0..<depthSamples.pixelCount {
            let includesUpperBound = range.upperBound == 1
            maskPixels[pixelIndex] = range.contains(depthSamples.values[pixelIndex], includesUpperBound: includesUpperBound) ? 255 : 0
        }

        return try makeGrayImage(
            pixels: maskPixels,
            width: depthSamples.width,
            height: depthSamples.height
        )
    }

    nonisolated static func apply(mask: CGImage, to image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let resizedMask = try makeResizedMaskIfNeeded(mask, width: width, height: height)
        var imagePixels = try makeRGBAPixels(from: image, width: width, height: height)
        let maskPixels = try makeGrayPixels(from: resizedMask, width: width, height: height)
        let pixelCount = width * height

        for pixelIndex in 0..<pixelCount {
            let rgbaIndex = pixelIndex * Constants.rgbaBytesPerPixel
            let alpha = maskPixels[pixelIndex]
            imagePixels[rgbaIndex + 3] = alpha

            if alpha == 0 {
                imagePixels[rgbaIndex] = 0
                imagePixels[rgbaIndex + 1] = 0
                imagePixels[rgbaIndex + 2] = 0
            }
        }

        return try makeRGBAImage(pixels: imagePixels, width: width, height: height, shouldInterpolate: true)
    }

    nonisolated static func makeCutout(from image: CGImage, depthImage: CGImage, range: DepthRange) throws -> CGImage {
        let mask = try makeMask(from: depthImage, range: range)
        return try apply(mask: mask, to: image)
    }

    nonisolated static func makeLayerRenderings(
        from image: CGImage,
        depthImage: CGImage,
        layers: [DepthLayerRenderSpec],
        overlayOpacity: Double
    ) throws -> DepthLayerRenderingResult {
        guard !layers.isEmpty else {
            throw DepthLayerMaskingError.missingLayerDefinitions
        }

        let width = image.width
        let height = image.height
        let depthSamples = try makeDepthSamples(from: depthImage, width: width, height: height)
        let basePixels = try makeRGBAPixels(from: image, width: width, height: height)
        let clampedOpacity = min(max(overlayOpacity, 0), 1)
        let pixelCount = width * height
        var layerPreviewPixels = [UInt8](repeating: 0, count: pixelCount * Constants.rgbaBytesPerPixel)
        var overlayPreviewPixels = basePixels
        var cutoutPixelsByLayer = layers.map { _ in basePixels }

        for pixelIndex in 0..<pixelCount {
            let depthValue = depthSamples.values[pixelIndex]
            let selectedLayerIndex = layerIndex(for: depthValue, in: layers)
            let rgbaIndex = pixelIndex * Constants.rgbaBytesPerPixel

            if let selectedLayerIndex {
                let color = layers[selectedLayerIndex].color
                layerPreviewPixels[rgbaIndex] = color.red
                layerPreviewPixels[rgbaIndex + 1] = color.green
                layerPreviewPixels[rgbaIndex + 2] = color.blue
                layerPreviewPixels[rgbaIndex + 3] = 255

                overlayPreviewPixels[rgbaIndex] = blend(base: basePixels[rgbaIndex], overlay: color.red, opacity: clampedOpacity)
                overlayPreviewPixels[rgbaIndex + 1] = blend(base: basePixels[rgbaIndex + 1], overlay: color.green, opacity: clampedOpacity)
                overlayPreviewPixels[rgbaIndex + 2] = blend(base: basePixels[rgbaIndex + 2], overlay: color.blue, opacity: clampedOpacity)
                overlayPreviewPixels[rgbaIndex + 3] = basePixels[rgbaIndex + 3]
            }

            for layerPosition in layers.indices where layerPosition != selectedLayerIndex {
                cutoutPixelsByLayer[layerPosition][rgbaIndex] = 0
                cutoutPixelsByLayer[layerPosition][rgbaIndex + 1] = 0
                cutoutPixelsByLayer[layerPosition][rgbaIndex + 2] = 0
                cutoutPixelsByLayer[layerPosition][rgbaIndex + 3] = 0
            }
        }

        let layerPreview = try makeRGBAImage(
            pixels: layerPreviewPixels,
            width: width,
            height: height,
            shouldInterpolate: false
        )
        let overlayPreview = try makeRGBAImage(
            pixels: overlayPreviewPixels,
            width: width,
            height: height,
            shouldInterpolate: true
        )
        let cutouts = try cutoutPixelsByLayer.map { pixels in
            try makeRGBAImage(pixels: pixels, width: width, height: height, shouldInterpolate: true)
        }

        return DepthLayerRenderingResult(
            layerPreview: layerPreview,
            overlayPreview: overlayPreview,
            cutouts: cutouts
        )
    }

    nonisolated static func suggestBoundaries(from depthImage: CGImage, layerCount: Int) throws -> [Double] {
        guard layerCount >= 2 else {
            throw DepthLayerMaskingError.invalidLayerCount
        }

        let samples = try makeDepthSamples(from: depthImage).values.sorted()
        guard !samples.isEmpty else { return [] }

        return (1..<layerCount).map { boundaryIndex in
            let target = Double(boundaryIndex) / Double(layerCount)
            let sampleIndex = min(samples.count - 1, max(0, Int((Double(samples.count - 1) * target).rounded())))
            return samples[sampleIndex]
        }
    }

    nonisolated private static func layerIndex(for depthValue: Double, in layers: [DepthLayerRenderSpec]) -> Int? {
        for index in layers.indices {
            let includesUpperBound = index == layers.indices.last || layers[index].range.upperBound == 1
            if layers[index].range.contains(depthValue, includesUpperBound: includesUpperBound) {
                return index
            }
        }

        return nil
    }

    nonisolated private static func makeDepthSamples(from depthImage: CGImage) throws -> DepthSamples {
        try makeDepthSamples(from: depthImage, width: depthImage.width, height: depthImage.height)
    }

    nonisolated private static func makeDepthSamples(from depthImage: CGImage, width: Int, height: Int) throws -> DepthSamples {
        let depthPixels = try makeRGBAPixels(from: depthImage, width: width, height: height)
        let pixelCount = width * height
        var values = [Double](repeating: 0, count: pixelCount)

        for pixelIndex in 0..<pixelCount {
            let rgbaIndex = pixelIndex * Constants.rgbaBytesPerPixel
            let red = Double(depthPixels[rgbaIndex])
            let green = Double(depthPixels[rgbaIndex + 1])
            let blue = Double(depthPixels[rgbaIndex + 2])
            values[pixelIndex] = ((red + green + blue) / 3) / 255
        }

        return DepthSamples(width: width, height: height, values: values)
    }

    nonisolated private static func makeRGBAPixels(from image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height * Constants.rgbaBytesPerPixel)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * Constants.rgbaBytesPerPixel,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DepthLayerMaskingError.bitmapContextCreationFailed
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    nonisolated private static func makeGrayPixels(from image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw DepthLayerMaskingError.bitmapContextCreationFailed
        }

        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    nonisolated private static func makeRGBAImage(pixels: [UInt8], width: Int, height: Int, shouldInterpolate: Bool) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * Constants.rgbaBytesPerPixel,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: shouldInterpolate,
                intent: .defaultIntent
              ) else {
            throw DepthLayerMaskingError.imageCreationFailed
        }

        return image
    }

    nonisolated private static func makeGrayImage(pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
              ) else {
            throw DepthLayerMaskingError.maskImageCreationFailed
        }

        return image
    }

    nonisolated private static func makeResizedMaskIfNeeded(_ mask: CGImage, width: Int, height: Int) throws -> CGImage {
        guard mask.width != width || mask.height != height else { return mask }

        let pixels = try makeGrayPixels(from: mask, width: width, height: height)
        return try makeGrayImage(pixels: pixels, width: width, height: height)
    }

    nonisolated private static func blend(base: UInt8, overlay: UInt8, opacity: Double) -> UInt8 {
        UInt8((Double(base) * (1 - opacity) + Double(overlay) * opacity).rounded())
    }
}

private enum Constants {
    nonisolated static let rgbaBytesPerPixel = 4
}

private struct DepthSamples {
    let width: Int
    let height: Int
    let values: [Double]

    nonisolated var pixelCount: Int {
        width * height
    }
}

enum DepthLayerMaskingError: Error {
    case invalidDepthRange
    case invalidLayerCount
    case missingLayerDefinitions
    case bitmapContextCreationFailed
    case maskImageCreationFailed
    case imageCreationFailed
    case cutoutImageCreationFailed
}
