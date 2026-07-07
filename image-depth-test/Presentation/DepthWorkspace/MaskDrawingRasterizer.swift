//
//  MaskDrawingRasterizer.swift
//  image-depth-test
//

import AppKit
import CoreGraphics

enum MaskDrawingRasterizer {
    static func makeEditedMask(baseMask: CGImage, strokes: [MaskStroke], size: CGSize) throws -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        var maskPixels = try makeGrayPixels(from: baseMask, width: width, height: height)
        guard let context = CGContext(
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

        let imageRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.clip(to: imageRect)
        context.setBlendMode(.copy)
        context.setShouldAntialias(false)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        for stroke in strokes {
            draw(stroke, in: context)
        }

        return try makeGrayImage(pixels: maskPixels, width: width, height: height)
    }

    private static func makeGrayPixels(from image: CGImage, width: Int, height: Int) throws -> [UInt8] {
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

    private static func makeGrayImage(pixels: [UInt8], width: Int, height: Int) throws -> CGImage {
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

    private static func draw(_ stroke: MaskStroke, in context: CGContext) {
        guard let firstPoint = stroke.points.first else { return }

        let color = stroke.tool == .pencil
            ? CGColor(gray: 1, alpha: 1)
            : CGColor(gray: 0, alpha: 1)
        context.setStrokeColor(color)
        context.setFillColor(color)
        context.setLineWidth(stroke.brushSize)

        if stroke.points.count < 2 || stroke.points.allSatisfy({ distance(from: firstPoint, to: $0) < 0.5 }) {
            let radius = stroke.brushSize / 2
            context.fillEllipse(in: CGRect(
                x: firstPoint.x - radius,
                y: firstPoint.y - radius,
                width: stroke.brushSize,
                height: stroke.brushSize
            ))
            return
        }

        context.beginPath()
        context.move(to: firstPoint)
        for point in stroke.points.dropFirst() {
            context.addLine(to: point)
        }
        context.strokePath()
    }

    private static func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        hypot(lhs.x - rhs.x, lhs.y - rhs.y)
    }
}
