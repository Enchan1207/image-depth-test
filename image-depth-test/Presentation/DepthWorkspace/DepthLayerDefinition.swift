//
//  DepthLayerDefinition.swift
//  image-depth-test
//

import AppKit
import Foundation
import SwiftUI

struct DepthLayerDefinition: Identifiable {
    let id: UUID
    let index: Int
    let name: String
    let lowerBound: Double
    let upperBound: Double
    let nsColor: NSColor

    var color: Color {
        Color(nsColor: displayColor)
    }

    var renderSpec: DepthLayerRenderSpec? {
        guard let range = try? DepthRange(lowerBound: lowerBound, upperBound: upperBound) else {
            return nil
        }

        return DepthLayerRenderSpec(
            index: index,
            range: range,
            color: renderColor
        )
    }

    var rangeText: String {
        "\(lowerBound.formatted(.number.precision(.fractionLength(2)))) - \(upperBound.formatted(.number.precision(.fractionLength(2))))"
    }

    private var displayColor: NSColor {
        nsColor.usingColorSpace(.sRGB) ?? nsColor
    }

    private var renderColor: DepthLayerRenderColor {
        let color = displayColor
        return DepthLayerRenderColor(
            red: UInt8((color.redComponent * 255).rounded()),
            green: UInt8((color.greenComponent * 255).rounded()),
            blue: UInt8((color.blueComponent * 255).rounded())
        )
    }
}
