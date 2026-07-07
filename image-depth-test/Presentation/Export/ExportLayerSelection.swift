//
//  ExportLayerSelection.swift
//  image-depth-test
//

import AppKit
import CoreGraphics
import Foundation
import SwiftUI

struct ExportLayerSelection: Identifiable {
    let id: UUID
    let index: Int
    let name: String
    let tintColor: Color
    let image: CGImage
    var isIncluded: Bool

    init(layer: DepthLayerDefinition, image: CGImage, isIncluded: Bool = true) {
        self.id = layer.id
        self.index = layer.index
        self.name = layer.name
        self.tintColor = layer.color
        self.image = image
        self.isIncluded = isIncluded
    }

    var exportLayer: DepthLayerExportLayer {
        DepthLayerExportLayer(id: id, index: index, name: name, image: image)
    }
}
