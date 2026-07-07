//
//  DepthEstimating.swift
//  image-depth-test
//

import CoreGraphics
import CoreVideo

protocol DepthEstimating: Sendable {
    func estimateDepth(for image: CGImage) async throws -> DepthEstimationResult
}

struct DepthEstimationResult: @unchecked Sendable {
    let depthImage: CGImage
    let depthPixelBuffer: CVPixelBuffer?
}
