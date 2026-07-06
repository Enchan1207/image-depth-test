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
    let color: Color

    var id: Int { index }

    static let names = ["Far", "Back", "Mid", "Front"]
    static let colors: [Color] = [.indigo, .teal, .yellow, .red]

    var rangeText: String {
        "\(lowerBound.formatted(.number.precision(.fractionLength(2)))) - \(upperBound.formatted(.number.precision(.fractionLength(2))))"
    }
}
