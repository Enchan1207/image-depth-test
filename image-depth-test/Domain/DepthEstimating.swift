//
//  DepthEstimating.swift
//  image-depth-test
//

import CoreGraphics

protocol DepthEstimating: Sendable {
    func estimateDepth(for image: CGImage) async throws -> CGImage
}
