//
//  AppDependencies.swift
//  image-depth-test
//

import CoreGraphics

/// Builds concrete app dependencies at the application boundary.
enum AppDependencies {
    static func makeDepthEstimator() -> any DepthEstimating {
        do {
            return try DepthAnythingV2DepthEstimator()
        } catch {
            return UnavailableDepthEstimator()
        }
    }

    static func makeDepthLayerRenderer() -> any DepthLayerRendering {
        do {
            return try MetalDepthLayerRenderer()
        } catch {
            return CPUDepthLayerRenderer()
        }
    }
}

private struct UnavailableDepthEstimator: DepthEstimating {
    func estimateDepth(for image: CGImage) async throws -> DepthEstimationResult {
        throw DepthEstimatorUnavailableError()
    }
}

private struct DepthEstimatorUnavailableError: Error {}
