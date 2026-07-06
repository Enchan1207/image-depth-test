//
//  DepthPreviewMode.swift
//  image-depth-test
//

import Foundation

enum DepthPreviewMode: String, CaseIterable, Identifiable {
    case original
    case depth
    case layers
    case overlay
    case isolated

    var id: Self { self }

    var title: String {
        switch self {
        case .original: "Original"
        case .depth: "Depth"
        case .layers: "Layers"
        case .overlay: "Overlay"
        case .isolated: "Isolated"
        }
    }

    var systemImageName: String {
        switch self {
        case .original: "photo"
        case .depth: "square.stack.3d.down.right"
        case .layers: "square.3.layers.3d"
        case .overlay: "circle.lefthalf.filled"
        case .isolated: "scope"
        }
    }
}
