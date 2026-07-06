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

enum DepthLayerMasking {
    nonisolated static func makeMask(from depthImage: CGImage, range: DepthRange) throws -> CGImage {
        let width = depthImage.width
        let height = depthImage.height
        let pixelCount = width * height
        let rgbaBytesPerPixel = 4
        let rgbaBytesPerRow = width * rgbaBytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var depthPixels = [UInt8](repeating: 0, count: pixelCount * rgbaBytesPerPixel)

        guard let context = CGContext(
            data: &depthPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: rgbaBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DepthLayerMaskingError.bitmapContextCreationFailed
        }

        context.draw(depthImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var maskPixels = [UInt8](repeating: 0, count: pixelCount)
        for pixelIndex in 0..<pixelCount {
            let rgbaIndex = pixelIndex * rgbaBytesPerPixel
            let red = Double(depthPixels[rgbaIndex])
            let green = Double(depthPixels[rgbaIndex + 1])
            let blue = Double(depthPixels[rgbaIndex + 2])
            let normalizedDepth = ((red + green + blue) / 3) / 255
            maskPixels[pixelIndex] = range.contains(normalizedDepth, includesUpperBound: true) ? 255 : 0
        }

        guard let provider = CGDataProvider(data: Data(maskPixels) as CFData),
              let mask = CGImage(
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

        return mask
    }

    nonisolated static func apply(mask: CGImage, to image: CGImage) throws -> CGImage {
        let width = image.width
        let height = image.height
        let resizedMask = try makeResizedMaskIfNeeded(mask, width: width, height: height)
        let pixelCount = width * height
        let rgbaBytesPerPixel = 4
        let rgbaBytesPerRow = width * rgbaBytesPerPixel
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var imagePixels = [UInt8](repeating: 0, count: pixelCount * rgbaBytesPerPixel)
        var maskPixels = [UInt8](repeating: 0, count: pixelCount)

        guard let imageContext = CGContext(
            data: &imagePixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: rgbaBytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DepthLayerMaskingError.bitmapContextCreationFailed
        }

        guard let maskContext = CGContext(
            data: &maskPixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            throw DepthLayerMaskingError.bitmapContextCreationFailed
        }

        imageContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        maskContext.interpolationQuality = .none
        maskContext.draw(resizedMask, in: CGRect(x: 0, y: 0, width: width, height: height))

        for pixelIndex in 0..<pixelCount {
            let rgbaIndex = pixelIndex * rgbaBytesPerPixel
            imagePixels[rgbaIndex + 3] = maskPixels[pixelIndex]
        }

        guard let provider = CGDataProvider(data: Data(imagePixels) as CFData),
              let cutout = CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: rgbaBytesPerRow,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
              ) else {
            throw DepthLayerMaskingError.cutoutImageCreationFailed
        }

        return cutout
    }

    nonisolated static func makeCutout(from image: CGImage, depthImage: CGImage, range: DepthRange) throws -> CGImage {
        let mask = try makeMask(from: depthImage, range: range)
        return try apply(mask: mask, to: image)
    }

    nonisolated private static func makeResizedMaskIfNeeded(_ mask: CGImage, width: Int, height: Int) throws -> CGImage {
        guard mask.width != width || mask.height != height else { return mask }

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
        context.draw(mask, in: CGRect(x: 0, y: 0, width: width, height: height))

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let resizedMask = CGImage(
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

        return resizedMask
    }
}

enum DepthLayerMaskingError: Error {
    case invalidDepthRange
    case bitmapContextCreationFailed
    case maskImageCreationFailed
    case cutoutImageCreationFailed
}
