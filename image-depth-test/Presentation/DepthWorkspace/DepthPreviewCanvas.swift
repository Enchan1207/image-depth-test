//
//  DepthPreviewCanvas.swift
//  image-depth-test
//

import SwiftUI

struct DepthPreviewCanvas: View {
    let mode: DepthPreviewMode
    let inputImage: NSImage?
    let depthImage: NSImage?
    let layerPreviewImage: NSImage?
    let layerOverlayImage: NSImage?
    let cutoutImages: [NSImage]
    let isLoading: Bool
    let selectedLayer: DepthLayerDefinition?

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
                imageView(layerPreviewImage, placeholderSystemImage: "square.3.layers.3d", message: layerMessage)
            case .overlay:
                imageView(layerOverlayImage, placeholderSystemImage: "circle.lefthalf.filled", message: layerMessage)
            case .isolated:
                cutoutStack
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

    @ViewBuilder
    private var cutoutStack: some View {
        if cutoutImages.isEmpty {
            placeholder(systemImageName: "eye.slash", message: cutoutMessage)
        } else {
            ZStack {
                ForEach(Array(cutoutImages.enumerated()), id: \.offset) { _, image in
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(14)
                }
            }
        }
    }

    private var imageMessage: String {
        isLoading ? "読み込み中" : "画像未選択"
    }

    private var depthMessage: String {
        isLoading ? "深度推定中" : "推定結果なし"
    }

    private var layerMessage: String {
        isLoading ? "レイヤ生成中" : "レイヤ結果なし"
    }

    private var cutoutMessage: String {
        isLoading ? "切り抜き生成中" : "表示中の切り抜きレイヤなし"
    }

    @ViewBuilder
    private func imageView(_ image: NSImage?, placeholderSystemImage: String, message: String) -> some View {
        if let image {
            Image(platformImage: image)
                .resizable()
                .scaledToFit()
                .padding(14)
        } else {
            placeholder(systemImageName: placeholderSystemImage, message: message)
        }
    }

    private func placeholder(systemImageName: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: systemImageName)
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
    }
}
