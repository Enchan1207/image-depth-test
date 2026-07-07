//
//  LayerControlPane.swift
//  image-depth-test
//

import SwiftUI

struct LayerControlPane: View {
    let layers: [DepthLayerDefinition]
    let layerCount: Int
    @Binding var selectedLayerID: DepthLayerItem.ID
    @Binding var visiblePreviewTargets: Set<PreviewDisplayTarget>
    let editedMaskLayerIDs: Set<UUID>
    let availableLayerIndexes: Set<Int>
    let canGenerateLayerRenderings: Bool
    let isDepthMapAvailable: Bool
    let isOriginalAvailable: Bool
    let canEditMask: (DepthLayerDefinition) -> Bool
    let splitSelectedLayer: () -> Void
    let autoSplitDepthRanges: () -> Void
    let resetDepthRanges: () -> Void
    let editMask: (DepthLayerDefinition) -> Void
    let deleteLayer: (DepthLayerItem.ID) -> Void
    let togglePreviewTarget: (PreviewDisplayTarget) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("レイヤ設定")
                .font(.headline)

            Button(action: splitSelectedLayer) {
                Label("分割して追加", systemImage: "plus.rectangle.on.rectangle")
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("深度レンジ")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Auto", action: autoSplitDepthRanges)
                        .disabled(!canGenerateLayerRenderings)

                    Button("Reset", action: resetDepthRanges)
                }

                ForEach(layers) { layer in
                    LayerRangeRow(
                        layer: layer,
                        isSelected: layer.id == selectedLayerID,
                        canDelete: layerCount > 2,
                        canEditMask: canEditMask(layer),
                        isMaskEdited: editedMaskLayerIDs.contains(layer.id)
                    ) {
                        selectedLayerID = layer.id
                    } editMaskAction: {
                        editMask(layer)
                    } deleteAction: {
                        deleteLayer(layer.id)
                    }
                }
            }

            Spacer(minLength: 12)

            DisplayControlPane(
                layers: layers,
                visiblePreviewTargets: $visiblePreviewTargets,
                availableLayerIndexes: availableLayerIndexes,
                isDepthMapAvailable: isDepthMapAvailable,
                isOriginalAvailable: isOriginalAvailable,
                togglePreviewTarget: togglePreviewTarget
            )
        }
        .padding(16)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
