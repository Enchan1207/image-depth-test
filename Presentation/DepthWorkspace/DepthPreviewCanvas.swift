//
//  DepthPreviewCanvas.swift
//  image-depth-test
//

import SwiftUI

struct DepthPreviewCanvas: View {
    let mode: DepthPreviewMode
    let inputImage: NSImage?
    let depthImage: NSImage?
    let isLoading: Bool
    let selectedLayer: DepthLayerDefinition?
    let overlayOpacity: Double

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)

            switch mode {
            case .original:
                imageView(inputImage, placeholderSystemImage: "photo", message: imageMessage)
            case .depth:
                imageView(depthImage, placeholderSystemImage: "square.stack.3d.down.right", message: depthMessage)
            case .layers:
                imageView(depthImage ?? inputImage, placeholderSystemImage: "square.3.layers.3d", message: depthMessage)
                    .overlay(layerTint.opacity(depthImage == nil ? 0 : 0.62))
            case .overlay:
                imageView(inputImage, placeholderSystemImage: "circle.lefthalf.filled", message: imageMessage)
                    .overlay(layerTint.opacity(depthImage == nil ? 0 : overlayOpacity))
            case .isolated:
                imageView(depthImage ?? inputImage, placeholderSystemImage: "scope", message: depthMessage)
                    .overlay(layerTint.opacity(depthImage == nil ? 0 : 0.78))
                    .mask(RoundedRectangle(cornerRadius: 8))
            }

            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let selectedLayer, mode != .original, depthImage != nil {
                Label("\(selectedLayer.name)  \(selectedLayer.rangeText)", systemImage: "slider.horizontal.below.rectangle")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private var layerTint: some View {
        LinearGradient(
            colors: DepthLayerDefinition.colors,
            startPoint: .top,
            endPoint: .bottom
        )
        .blendMode(.multiply)
    }

    private var imageMessage: String {
        isLoading ? "読み込み中" : "画像未選択"
    }

    private var depthMessage: String {
        isLoading ? "深度推定中" : "推定結果なし"
    }

    @ViewBuilder
    private func imageView(_ image: NSImage?, placeholderSystemImage: String, message: String) -> some View {
        if let image {
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .padding(14)
        } else {
            VStack(spacing: 12) {
                Image(systemName: placeholderSystemImage)
                    .font(.system(size: 44, weight: .regular))
                    .foregroundStyle(.secondary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
        }
    }
}
