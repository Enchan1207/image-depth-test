//
//  ExportPreviewCanvas.swift
//  image-depth-test
//

import SwiftUI

struct ExportPreviewCanvas: View {
    private let imagePadding: CGFloat = 14

    let layers: [ExportLayerSelection]
    let contentID: AnyHashable

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(.background)

            if let imageSize {
                let contentSize = paddedSize(for: imageSize)

                ZoomableScrollView(
                    contentSize: contentSize,
                    contentID: contentID
                ) {
                    ZStack {
                        checkerboard
                            .frame(width: imageSize.width, height: imageSize.height)

                        ForEach(visibleLayers) { layer in
                            Image(nsImage: layer.previewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: imageSize.width, height: imageSize.height)
                        }
                    }
                    .padding(imagePadding)
                    .frame(width: contentSize.width, height: contentSize.height)
                }

                if visibleLayers.isEmpty {
                    placeholder
                        .allowsHitTesting(false)
                }
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var visibleLayers: [ExportLayerSelection] {
        layers
            .filter(\.isIncluded)
            .sorted { $0.index < $1.index }
    }

    private var imageSize: CGSize? {
        guard let image = layers.first?.image else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    private var checkerboard: some View {
        CheckerboardView(tileSize: 14)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.dashed")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.secondary)

            Text("出力するレイヤがありません")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func paddedSize(for imageSize: CGSize) -> CGSize {
        CGSize(
            width: imageSize.width + imagePadding * 2,
            height: imageSize.height + imagePadding * 2
        )
    }
}

private extension ExportLayerSelection {
    var previewImage: NSImage {
        NSImage(
            cgImage: image,
            size: NSSize(width: image.width, height: image.height)
        )
    }
}

private struct CheckerboardView: View {
    let tileSize: CGFloat

    var body: some View {
        Canvas { context, size in
            let columns = Int(ceil(size.width / tileSize))
            let rows = Int(ceil(size.height / tileSize))

            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let rect = CGRect(
                        x: CGFloat(column) * tileSize,
                        y: CGFloat(row) * tileSize,
                        width: tileSize,
                        height: tileSize
                    )
                    context.fill(Path(rect), with: .color(Color.secondary.opacity(0.12)))
                }
            }
        }
        .background(Color.secondary.opacity(0.05))
    }
}
