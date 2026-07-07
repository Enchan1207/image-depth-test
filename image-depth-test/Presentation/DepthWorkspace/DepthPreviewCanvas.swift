//
//  DepthPreviewCanvas.swift
//  image-depth-test
//

import SwiftUI

struct DepthPreviewCanvasLayer: Identifiable {
    let id: AnyHashable
    let image: NSImage
}

struct DepthPreviewCanvas: View {
    private let imagePadding: CGFloat = 14

    let layers: [DepthPreviewCanvasLayer]
    let workspaceID: AnyHashable
    let placeholderSystemImage: String
    let placeholderMessage: String
    let isLoading: Bool
    let selectedLayer: DepthLayerDefinition?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)

            previewContent

            if isLoading {
                ProgressView()
                    .controlSize(.large)
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let selectedLayer {
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var previewContent: some View {
        if layers.isEmpty {
            placeholder(systemImageName: placeholderSystemImage, message: placeholderMessage)
        } else {
            let imageSize = maximumImageSize(in: layers.map(\.image))
            let contentSize = paddedSize(for: imageSize)

            ZoomableScrollView(
                contentSize: contentSize,
                contentID: workspaceID
            ) {
                ZStack {
                    ForEach(layers) { layer in
                        Image(platformImage: layer.image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: imageSize.width, height: imageSize.height)
                    }
                }
                .padding(imagePadding)
                .frame(width: contentSize.width, height: contentSize.height)
            }
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

    private func paddedSize(for imageSize: CGSize) -> CGSize {
        CGSize(
            width: imageSize.width + imagePadding * 2,
            height: imageSize.height + imagePadding * 2
        )
    }

    private func maximumImageSize(in images: [NSImage]) -> CGSize {
        images.reduce(.zero) { result, image in
            CGSize(
                width: max(result.width, image.size.width),
                height: max(result.height, image.size.height)
            )
        }
    }
}
