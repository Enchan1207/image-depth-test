//
//  DepthAnythingV2DepthEstimator.swift
//  image-depth-test
//

import CoreGraphics
import CoreImage
import CoreML
import CoreVideo

final class DepthAnythingV2DepthEstimator: DepthEstimating, @unchecked Sendable {
    private let model: MLModel
    private let inputWidth: Int
    private let inputHeight: Int
    private let ciContext = CIContext()

    init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        model = try DepthAnythingV2SmallF32(configuration: configuration).model

        guard let imageConstraint = model.modelDescription.inputDescriptionsByName[FeatureName.image]?.imageConstraint else {
            throw DepthEstimationError.missingInputImageConstraint
        }

        inputWidth = imageConstraint.pixelsWide
        inputHeight = imageConstraint.pixelsHigh
    }

    func estimateDepth(for image: CGImage) async throws -> DepthEstimationResult {
        try await Task.detached(priority: .userInitiated) { [model, inputWidth, inputHeight, ciContext] in
            let inputPixelBuffer = try Self.makePixelBuffer(
                from: image,
                width: inputWidth,
                height: inputHeight
            )
            let input = try MLDictionaryFeatureProvider(dictionary: [
                FeatureName.image: MLFeatureValue(pixelBuffer: inputPixelBuffer)
            ])
            let output = try model.prediction(from: input)

            guard let depthPixelBuffer = output.featureValue(for: FeatureName.depth)?.imageBufferValue else {
                throw DepthEstimationError.missingDepthOutput
            }

            let depthImage = CIImage(cvPixelBuffer: depthPixelBuffer)
            let resizedDepthImage = depthImage.transformed(
                by: CGAffineTransform(
                    scaleX: CGFloat(image.width) / depthImage.extent.width,
                    y: CGFloat(image.height) / depthImage.extent.height
                )
            )
            let outputRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            let resizedDepthPixelBuffer = try Self.makeDepthPixelBuffer(width: image.width, height: image.height)
            ciContext.render(
                resizedDepthImage,
                to: resizedDepthPixelBuffer,
                bounds: outputRect,
                colorSpace: nil
            )

            guard let cgImage = ciContext.createCGImage(resizedDepthImage, from: outputRect) else {
                throw DepthEstimationError.depthImageConversionFailed
            }

            return DepthEstimationResult(
                depthImage: cgImage,
                depthPixelBuffer: resizedDepthPixelBuffer
            )
        }.value
    }

    nonisolated private static func makePixelBuffer(from image: CGImage, width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw DepthEstimationError.inputPixelBufferCreationFailed
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw DepthEstimationError.inputPixelBufferCreationFailed
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else {
            throw DepthEstimationError.inputPixelBufferCreationFailed
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixelBuffer
    }

    nonisolated private static func makeDepthPixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        let attributes: CFDictionary = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ] as CFDictionary

        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_OneComponent32Float,
            attributes,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw DepthEstimationError.depthPixelBufferCreationFailed
        }

        return pixelBuffer
    }
}

private enum FeatureName {
    nonisolated static let image = "image"
    nonisolated static let depth = "depth"
}

enum DepthEstimationError: Error {
    case missingInputImageConstraint
    case inputPixelBufferCreationFailed
    case depthPixelBufferCreationFailed
    case missingDepthOutput
    case depthImageConversionFailed
}
