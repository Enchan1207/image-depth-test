//
//  DepthLayerItem.swift
//  image-depth-test
//

import AppKit
import Foundation

struct DepthLayerItem: Identifiable, Equatable {
    let id: UUID
    var name: String
    var color: NSColor

    init(id: UUID = UUID(), name: String, color: NSColor) {
        self.id = id
        self.name = name
        self.color = color
    }

    static let colorPresets: [NSColor] = [
        .systemIndigo,
        .systemTeal,
        .systemYellow,
        .systemRed,
        .systemCyan,
        .systemOrange,
        .systemPurple,
        .systemGreen,
        .systemPink,
        .systemBlue
    ]

    static let initialItems = [
        DepthLayerItem(name: "Far", color: colorPresets[0]),
        DepthLayerItem(name: "Back", color: colorPresets[1]),
        DepthLayerItem(name: "Mid", color: colorPresets[2]),
        DepthLayerItem(name: "Front", color: colorPresets[3])
    ]

    static func presetColor(at index: Int) -> NSColor {
        guard !colorPresets.isEmpty else { return .systemGray }
        return colorPresets[index % colorPresets.count]
    }
}
