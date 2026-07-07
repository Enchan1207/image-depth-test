//
//  DepthLayerRendering.swift
//  image-depth-test
//

import CoreGraphics
import CoreVideo
import Foundation

struct DepthLayerPreviewRenderingResult: Sendable {
    let layerPreview: CGImage
    let overlayPreview: CGImage
}

protocol DepthLayerRendering: Sendable {
    nonisolated func makePreviewRenderings(
        from image: CGImage,
        depthImage: CGImage,
        depthPixelBuffer: CVPixelBuffer?,
        layers: [DepthLayerRenderSpec],
        overlayOpacity: Double
    ) throws -> DepthLayerPreviewRenderingResult

    nonisolated func makeCutouts(
        from image: CGImage,
        depthImage: CGImage,
        depthPixelBuffer: CVPixelBuffer?,
        layers: [DepthLayerRenderSpec]
    ) throws -> [CGImage]
}

extension DepthLayerRendering {
    nonisolated func makeLayerRenderings(
        from image: CGImage,
        depthImage: CGImage,
        layers: [DepthLayerRenderSpec],
        overlayOpacity: Double
    ) throws -> DepthLayerRenderingResult {
        try makeLayerRenderings(
            from: image,
            depthImage: depthImage,
            depthPixelBuffer: nil,
            layers: layers,
            overlayOpacity: overlayOpacity
        )
    }

    nonisolated func makeLayerRenderings(
        from image: CGImage,
        depthImage: CGImage,
        depthPixelBuffer: CVPixelBuffer?,
        layers: [DepthLayerRenderSpec],
        overlayOpacity: Double
    ) throws -> DepthLayerRenderingResult {
        let previews = try makePreviewRenderings(
            from: image,
            depthImage: depthImage,
            depthPixelBuffer: depthPixelBuffer,
            layers: layers,
            overlayOpacity: overlayOpacity
        )
        let cutouts = try makeCutouts(
            from: image,
            depthImage: depthImage,
            depthPixelBuffer: depthPixelBuffer,
            layers: layers
        )

        return DepthLayerRenderingResult(
            layerPreview: previews.layerPreview,
            overlayPreview: previews.overlayPreview,
            cutouts: cutouts
        )
    }
}

struct CPUDepthLayerRenderer: DepthLayerRendering {
    nonisolated func makePreviewRenderings(
        from image: CGImage,
        depthImage: CGImage,
        depthPixelBuffer: CVPixelBuffer?,
        layers: [DepthLayerRenderSpec],
        overlayOpacity: Double
    ) throws -> DepthLayerPreviewRenderingResult {
        try DepthLayerMasking.makePreviewRenderings(
            from: image,
            depthImage: depthImage,
            layers: layers,
            overlayOpacity: overlayOpacity
        )
    }

    nonisolated func makeCutouts(
        from image: CGImage,
        depthImage: CGImage,
        depthPixelBuffer: CVPixelBuffer?,
        layers: [DepthLayerRenderSpec]
    ) throws -> [CGImage] {
        try DepthLayerMasking.makeCutouts(
            from: image,
            depthImage: depthImage,
            layers: layers
        )
    }
}
