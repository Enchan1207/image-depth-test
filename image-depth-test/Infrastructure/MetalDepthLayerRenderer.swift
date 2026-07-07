//
//  MetalDepthLayerRenderer.swift
//  image-depth-test
//

import CoreGraphics
import CoreVideo
import Foundation
import Metal
import MetalKit
import simd

final class MetalDepthLayerRenderer: DepthLayerRendering, @unchecked Sendable {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    nonisolated(unsafe) private let textureCache: CVMetalTextureCache
    private let previewPipeline: MTLComputePipelineState
    private let cutoutPipeline: MTLComputePipelineState

    init(device: MTLDevice? = MTLCreateSystemDefaultDevice()) throws {
        guard let device else {
            throw MetalDepthLayerRendererError.metalDeviceUnavailable
        }
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalDepthLayerRendererError.commandQueueCreationFailed
        }
        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess,
              let textureCache else {
            throw MetalDepthLayerRendererError.textureCacheCreationFailed
        }
        guard let library = device.makeDefaultLibrary() else {
            throw MetalDepthLayerRendererError.libraryCreationFailed
        }
        guard let previewFunction = library.makeFunction(name: "makeDepthLayerPreview"),
              let cutoutFunction = library.makeFunction(name: "makeDepthLayerCutout") else {
            throw MetalDepthLayerRendererError.functionCreationFailed
        }

        self.device = device
        self.commandQueue = commandQueue
        self.textureCache = textureCache
        self.previewPipeline = try device.makeComputePipelineState(function: previewFunction)
        self.cutoutPipeline = try device.makeComputePipelineState(function: cutoutFunction)
    }

    nonisolated func makePreviewRenderings(
        from image: CGImage,
        depthImage: CGImage,
        depthPixelBuffer: CVPixelBuffer?,
        layers: [DepthLayerRenderSpec],
        overlayOpacity: Double
    ) throws -> DepthLayerPreviewRenderingResult {
        guard !layers.isEmpty else {
            throw DepthLayerMaskingError.missingLayerDefinitions
        }

        let inputTexture = try makeTexture(from: image)
        let depthTextureReference = try makeDepthTexture(
            from: depthPixelBuffer,
            fallbackImage: depthImage,
            width: image.width,
            height: image.height
        )
        let layerPreviewTexture = try makeOutputTexture(width: image.width, height: image.height)
        let overlayPreviewTexture = try makeOutputTexture(width: image.width, height: image.height)
        let layerSpecs = layers.map(MetalDepthLayerSpec.init(renderSpec:))
        var layerCount = UInt32(layerSpecs.count)
        var opacity = Float(min(max(overlayOpacity, 0), 1))

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw MetalDepthLayerRendererError.commandEncodingFailed
        }

        encoder.setComputePipelineState(previewPipeline)
        encoder.setTexture(inputTexture, index: 0)
        encoder.setTexture(depthTextureReference.texture, index: 1)
        encoder.setTexture(layerPreviewTexture, index: 2)
        encoder.setTexture(overlayPreviewTexture, index: 3)
        layerSpecs.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                encoder.setBytes(baseAddress, length: buffer.count, index: 0)
            }
        }
        encoder.setBytes(&layerCount, length: MemoryLayout<UInt32>.stride, index: 1)
        encoder.setBytes(&opacity, length: MemoryLayout<Float>.stride, index: 2)
        dispatch(encoder: encoder, pipeline: previewPipeline, width: image.width, height: image.height)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        try throwIfFailed(commandBuffer)

        return DepthLayerPreviewRenderingResult(
            layerPreview: try makeCGImage(from: layerPreviewTexture, shouldInterpolate: false),
            overlayPreview: try makeCGImage(from: overlayPreviewTexture, shouldInterpolate: true)
        )
    }

    nonisolated func makeCutouts(
        from image: CGImage,
        depthImage: CGImage,
        depthPixelBuffer: CVPixelBuffer?,
        layers: [DepthLayerRenderSpec]
    ) throws -> [CGImage] {
        guard !layers.isEmpty else {
            throw DepthLayerMaskingError.missingLayerDefinitions
        }

        let inputTexture = try makeTexture(from: image)
        let depthTextureReference = try makeDepthTexture(
            from: depthPixelBuffer,
            fallbackImage: depthImage,
            width: image.width,
            height: image.height
        )

        return try layers.map { layer in
            let outputTexture = try makeOutputTexture(width: image.width, height: image.height)
            var lowerBound = Float(layer.range.lowerBound)
            var upperBound = Float(layer.range.upperBound)

            guard let commandBuffer = commandQueue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else {
                throw MetalDepthLayerRendererError.commandEncodingFailed
            }

            encoder.setComputePipelineState(cutoutPipeline)
            encoder.setTexture(inputTexture, index: 0)
            encoder.setTexture(depthTextureReference.texture, index: 1)
            encoder.setTexture(outputTexture, index: 2)
            encoder.setBytes(&lowerBound, length: MemoryLayout<Float>.stride, index: 0)
            encoder.setBytes(&upperBound, length: MemoryLayout<Float>.stride, index: 1)
            dispatch(encoder: encoder, pipeline: cutoutPipeline, width: image.width, height: image.height)
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            try throwIfFailed(commandBuffer)
            return try makeCGImage(from: outputTexture, shouldInterpolate: true)
        }
    }

    nonisolated private func makeTexture(from image: CGImage) throws -> MTLTexture {
        try MTKTextureLoader(device: device).newTexture(
            cgImage: image,
            options: [
                MTKTextureLoader.Option.SRGB: false,
                MTKTextureLoader.Option.textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)
            ]
        )
    }

    nonisolated private func makeDepthTexture(
        from pixelBuffer: CVPixelBuffer?,
        fallbackImage image: CGImage,
        width: Int,
        height: Int
    ) throws -> MetalTextureReference {
        if let pixelBuffer,
           CVPixelBufferGetWidth(pixelBuffer) == width,
           CVPixelBufferGetHeight(pixelBuffer) == height {
            return try makeDepthTexture(from: pixelBuffer)
        }

        return MetalTextureReference(texture: try makeDepthTexture(from: image, width: width, height: height))
    }

    nonisolated private func makeDepthTexture(from pixelBuffer: CVPixelBuffer) throws -> MetalTextureReference {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let pixelFormat = try metalPixelFormat(for: CVPixelBufferGetPixelFormatType(pixelBuffer))
        var cvMetalTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            width,
            height,
            0,
            &cvMetalTexture
        )

        guard status == kCVReturnSuccess,
              let cvMetalTexture,
              let texture = CVMetalTextureGetTexture(cvMetalTexture) else {
            throw MetalDepthLayerRendererError.pixelBufferTextureCreationFailed
        }

        return MetalTextureReference(texture: texture, backingTexture: cvMetalTexture)
    }

    nonisolated private func metalPixelFormat(for pixelFormat: OSType) throws -> MTLPixelFormat {
        switch pixelFormat {
        case kCVPixelFormatType_OneComponent8:
            return .r8Unorm
        case kCVPixelFormatType_OneComponent16Half:
            return .r16Float
        case kCVPixelFormatType_OneComponent32Float:
            return .r32Float
        default:
            throw MetalDepthLayerRendererError.unsupportedDepthPixelFormat(pixelFormat)
        }
    }

    nonisolated private func makeDepthTexture(from image: CGImage, width: Int, height: Int) throws -> MTLTexture {
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

        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalDepthLayerRendererError.textureCreationFailed
        }

        texture.replace(
            region: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0,
            withBytes: pixels,
            bytesPerRow: width * Constants.rgbaBytesPerPixel
        )
        return texture
    }

    nonisolated private func makeOutputTexture(width: Int, height: Int) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw MetalDepthLayerRendererError.textureCreationFailed
        }
        return texture
    }

    nonisolated private func makeCGImage(from texture: MTLTexture, shouldInterpolate: Bool) throws -> CGImage {
        let width = texture.width
        let height = texture.height
        var pixels = [UInt8](repeating: 0, count: width * height * Constants.rgbaBytesPerPixel)
        texture.getBytes(
            &pixels,
            bytesPerRow: width * Constants.rgbaBytesPerPixel,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )

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

    nonisolated private func dispatch(encoder: MTLComputeCommandEncoder, pipeline: MTLComputePipelineState, width: Int, height: Int) {
        let threadgroupWidth = pipeline.threadExecutionWidth
        let threadgroupHeight = max(1, pipeline.maxTotalThreadsPerThreadgroup / threadgroupWidth)
        let threadsPerThreadgroup = MTLSize(width: threadgroupWidth, height: threadgroupHeight, depth: 1)
        let threadgroups = MTLSize(
            width: (width + threadgroupWidth - 1) / threadgroupWidth,
            height: (height + threadgroupHeight - 1) / threadgroupHeight,
            depth: 1
        )
        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
    }

    nonisolated private func throwIfFailed(_ commandBuffer: MTLCommandBuffer) throws {
        if let error = commandBuffer.error {
            throw MetalDepthLayerRendererError.commandBufferFailed(error)
        }
    }
}

private struct MetalTextureReference: @unchecked Sendable {
    nonisolated(unsafe) let texture: MTLTexture
    nonisolated(unsafe) let backingTexture: CVMetalTexture?

    nonisolated init(texture: MTLTexture, backingTexture: CVMetalTexture? = nil) {
        self.texture = texture
        self.backingTexture = backingTexture
    }
}

private struct MetalDepthLayerSpec {
    let color: SIMD4<Float>
    let range: SIMD2<Float>

    nonisolated init(renderSpec: DepthLayerRenderSpec) {
        color = SIMD4<Float>(
            Float(renderSpec.color.red) / 255,
            Float(renderSpec.color.green) / 255,
            Float(renderSpec.color.blue) / 255,
            1
        )
        range = SIMD2<Float>(Float(renderSpec.range.lowerBound), Float(renderSpec.range.upperBound))
    }
}

private enum Constants {
    nonisolated static let rgbaBytesPerPixel = 4
}

enum MetalDepthLayerRendererError: Error {
    case metalDeviceUnavailable
    case commandQueueCreationFailed
    case textureCacheCreationFailed
    case libraryCreationFailed
    case functionCreationFailed
    case textureCreationFailed
    case pixelBufferTextureCreationFailed
    case unsupportedDepthPixelFormat(OSType)
    case commandEncodingFailed
    case commandBufferFailed(Error)
}
