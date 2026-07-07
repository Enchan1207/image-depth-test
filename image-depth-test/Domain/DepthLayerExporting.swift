//
//  DepthLayerExporting.swift
//  image-depth-test
//

import CoreGraphics
import Foundation

struct DepthLayerExportLayer: Identifiable {
    let id: UUID
    let index: Int
    let name: String
    let image: CGImage
}

enum DepthLayerExporting {
    nonisolated static func makeCompositeImage(from layers: [DepthLayerExportLayer]) throws -> CGImage {
        guard let firstImage = layers.first?.image else {
            throw DepthLayerExportingError.noSelectedLayers
        }

        let width = firstImage.width
        let height = firstImage.height
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw DepthLayerExportingError.cannotCreateContext
        }

        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        for layer in layers.sorted(by: { $0.index < $1.index }) {
            guard layer.image.width == width, layer.image.height == height else {
                throw DepthLayerExportingError.inconsistentImageSize
            }

            context.draw(layer.image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        guard let image = context.makeImage() else {
            throw DepthLayerExportingError.cannotCreateImage
        }

        return image
    }
}

enum DepthLayerExportingError: Error {
    case noSelectedLayers
    case inconsistentImageSize
    case cannotCreateContext
    case cannotCreateImage
}
