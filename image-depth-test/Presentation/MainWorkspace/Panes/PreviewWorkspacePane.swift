//
//  PreviewWorkspacePane.swift
//  image-depth-test
//

import SwiftUI

struct PreviewWorkspacePane: View {
    let layers: [DepthPreviewCanvasLayer]
    let workspaceID: AnyHashable
    let placeholderSystemImage: String
    let placeholderMessage: String
    let isLoading: Bool
    let selectedLayer: DepthLayerDefinition?
    let layerDefinitions: [DepthLayerDefinition]
    @Binding var boundaries: [Double]
    @Binding var selectedLayerID: DepthLayerItem.ID
    let rangeEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("プレビュー")
                .font(.headline)

            DepthPreviewCanvas(
                layers: layers,
                workspaceID: workspaceID,
                placeholderSystemImage: placeholderSystemImage,
                placeholderMessage: placeholderMessage,
                isLoading: isLoading,
                selectedLayer: selectedLayer
            )

            DepthRangeEditor(
                layers: layerDefinitions,
                boundaries: $boundaries,
                selectedLayerID: $selectedLayerID,
                onEditingChanged: rangeEditingChanged
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
