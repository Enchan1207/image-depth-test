//
//  PreviewDisplayTarget.swift
//  image-depth-test
//

import Foundation

enum PreviewDisplayTarget: Hashable {
    case original
    case depthMap
    case layer(UUID)
}
