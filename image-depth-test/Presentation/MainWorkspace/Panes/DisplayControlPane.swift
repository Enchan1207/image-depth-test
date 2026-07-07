//
//  DisplayControlPane.swift
//  image-depth-test
//

import SwiftUI

struct DisplayControlPane: View {
    let layers: [DepthLayerDefinition]
    @Binding var visiblePreviewTargets: Set<PreviewDisplayTarget>
    let availableLayerIndexes: Set<Int>
    let isDepthMapAvailable: Bool
    let isOriginalAvailable: Bool
    let togglePreviewTarget: (PreviewDisplayTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("表示")
                .font(.subheadline.weight(.semibold))

            ForEach(layers.reversed()) { layer in
                let target = PreviewDisplayTarget.layer(layer.id)
                PreviewTargetButton(
                    title: layer.name,
                    systemImageName: "scope",
                    tint: layer.color,
                    isVisible: visiblePreviewTargets.contains(target),
                    isAvailable: availableLayerIndexes.contains(layer.index)
                ) {
                    togglePreviewTarget(target)
                }
            }

            PreviewTargetButton(
                title: "深度マップ",
                systemImageName: "square.stack.3d.down.right",
                isVisible: visiblePreviewTargets.contains(.depthMap),
                isAvailable: isDepthMapAvailable
            ) {
                togglePreviewTarget(.depthMap)
            }

            PreviewTargetButton(
                title: "元画像",
                systemImageName: "photo",
                isVisible: visiblePreviewTargets.contains(.original),
                isAvailable: isOriginalAvailable
            ) {
                togglePreviewTarget(.original)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct PreviewTargetButton: View {
    let title: String
    let systemImageName: String
    var tint: Color?
    let isVisible: Bool
    let isAvailable: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImageName)
                    .frame(width: 18)
                    .foregroundStyle(tint ?? .secondary)

                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Image(systemName: isVisible ? "eye.fill" : "eye.slash")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(isVisible ? Color.accentColor : Color.secondary.opacity(0.55))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .opacity(isAvailable ? 1 : 0.45)
            .background(isVisible ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isVisible ? Color.accentColor.opacity(0.30) : Color.secondary.opacity(0.14), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .help(isVisible ? "非表示にする" : "表示する")
    }
}
