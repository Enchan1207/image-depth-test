//
//  FileImportPane.swift
//  image-depth-test
//

import SwiftUI

struct FileImportPane: View {
    let viewModel: ImageDepthViewModel
    let importImageAction: () -> Void
    let reestimateAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: importImageAction) {
                Label("画像を読み込む", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)

            statusView

            Spacer()

            Button(action: reestimateAction) {
                Label("再推定", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!viewModel.hasSelectedImage || viewModel.isEstimatingDepth || viewModel.isLoadingImage)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var statusView: some View {
        if viewModel.isLoadingImage || viewModel.isEstimatingDepth || viewModel.isGeneratingLayerRenderings {
            ProgressView()
                .controlSize(.small)
            Text(statusText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if let errorMessage = viewModel.errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.red)
        } else if let selectedFileName = viewModel.selectedFileName {
            Text(selectedFileName)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("深度推定する画像を選択してください")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusText: String {
        if viewModel.isLoadingImage { return "読み込み中" }
        if viewModel.isEstimatingDepth { return "深度推定中" }
        if viewModel.isGeneratingLayerRenderings { return "レイヤ生成中" }
        return "処理中"
    }
}
