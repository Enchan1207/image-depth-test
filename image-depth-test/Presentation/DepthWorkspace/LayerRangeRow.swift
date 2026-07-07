//
//  LayerRangeRow.swift
//  image-depth-test
//

import SwiftUI

struct LayerRangeRow: View {
    let layer: DepthLayerDefinition
    let isSelected: Bool
    let isVisible: Bool
    let canDelete: Bool
    let action: () -> Void
    let visibilityAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(layer.color)
                    .frame(width: 18, height: 18)
                    .opacity(isVisible ? 1 : 0.35)

                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.name)
                        .font(.subheadline.weight(.semibold))
                    Text(layer.rangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .opacity(isVisible ? 1 : 0.48)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }

                Button(action: visibilityAction) {
                    Image(systemName: isVisible ? "eye" : "eye.slash")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(isVisible ? .secondary : .tertiary)
                .help(isVisible ? "切り抜きレイヤを非表示" : "切り抜きレイヤを表示")

                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(canDelete ? .secondary : .tertiary)
                .disabled(!canDelete)
                .help(canDelete ? "レイヤを削除" : "レイヤは2つ以上必要です")
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.16), lineWidth: 1)
        }
    }
}
