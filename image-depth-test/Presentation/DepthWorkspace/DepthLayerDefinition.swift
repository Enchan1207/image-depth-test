//
//  DepthLayerDefinition.swift
//  image-depth-test
//

import SwiftUI

struct DepthLayerDefinition: Identifiable {
    let index: Int
    let name: String
    let lowerBound: Double
    let upperBound: Double
    let renderColor: DepthLayerRenderColor

    var id: Int { index }

    var color: Color {
        Color(
            red: Double(renderColor.red) / 255,
            green: Double(renderColor.green) / 255,
            blue: Double(renderColor.blue) / 255
        )
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

    static let names = ["Far", "Back", "Mid", "Front"]
    static let renderColors = [
        DepthLayerRenderColor(red: 76, green: 88, blue: 216),
        DepthLayerRenderColor(red: 0, green: 147, blue: 155),
        DepthLayerRenderColor(red: 236, green: 188, blue: 54),
        DepthLayerRenderColor(red: 225, green: 72, blue: 82)
    ]

    static var colors: [Color] {
        renderColors.map { renderColor in
            Color(
                red: Double(renderColor.red) / 255,
                green: Double(renderColor.green) / 255,
                blue: Double(renderColor.blue) / 255
            )
        }
    }

    var rangeText: String {
        "\(lowerBound.formatted(.number.precision(.fractionLength(2)))) - \(upperBound.formatted(.number.precision(.fractionLength(2))))"
    }
}
