//
//  MaskEditorTool.swift
//  image-depth-test
//

import Foundation
import CoreGraphics

enum MaskEditorTool: String, CaseIterable, Identifiable {
    case pencil
    case eraser

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .pencil:
            return "鉛筆"
        case .eraser:
            return "消しゴム"
        }
    }

    var systemImageName: String {
        switch self {
        case .pencil:
            return "pencil"
        case .eraser:
            return "eraser"
        }
    }
}

struct MaskStroke: Identifiable, Sendable {
    let id = UUID()
    let tool: MaskEditorTool
    let brushSize: Double
    var points: [CGPoint]
}
