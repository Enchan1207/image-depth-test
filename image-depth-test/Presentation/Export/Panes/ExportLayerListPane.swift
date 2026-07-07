//
//  ExportLayerListPane.swift
//  image-depth-test
//

import SwiftUI

struct ExportLayerListPane: View {
    let layers: [ExportLayerSelection]
    let setLayerIncluded: (UUID, Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("出力レイヤ")
                .font(.headline)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(layers.reversed()) { layer in
                        ExportLayerToggleRow(layer: layer) { isIncluded in
                            setLayerIncluded(layer.id, isIncluded)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(16)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ExportLayerToggleRow: View {
    let layer: ExportLayerSelection
    let setIncluded: (Bool) -> Void

    var body: some View {
        Toggle(isOn: binding) {
            HStack(spacing: 10) {
                Image(systemName: "scope")
                    .frame(width: 18)
                    .foregroundStyle(layer.tintColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.name)
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text("Layer \(layer.index + 1)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(layer.isIncluded ? Color.accentColor.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(layer.isIncluded ? Color.accentColor.opacity(0.28) : Color.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { layer.isIncluded },
            set: setIncluded
        )
    }
}
