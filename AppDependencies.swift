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
}

private struct UnavailableDepthEstimator: DepthEstimating {
    func estimateDepth(for image: CGImage) async throws -> CGImage {
        throw DepthEstimatorUnavailableError()
    }
}

private struct DepthEstimatorUnavailableError: Error {}
