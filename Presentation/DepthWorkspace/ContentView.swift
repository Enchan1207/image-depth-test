//
//  ContentView.swift
//  image-depth-test
//
//  Created by enchantcode on 2026/07/04.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel: ImageDepthViewModel
    @State private var isFileImporterPresented = false
    @State private var previewMode: DepthPreviewMode = .overlay
    @State private var layerCount = 4
    @State private var selectedLayerIndex = 3
    @State private var depthBoundaries = [0.22, 0.48, 0.74]
    @State private var overlayOpacity = 0.56

    init(depthEstimator: any DepthEstimating) {
        _viewModel = State(initialValue: ImageDepthViewModel(depthEstimator: depthEstimator))
    }

    var body: some View {
        VStack(spacing: 14) {
            fileImportPane

            HStack(alignment: .top, spacing: 14) {
                previewWorkspace
                layerControlPane
            }
        }
        .padding(20)
        .frame(minWidth: 960, minHeight: 640)
        .fileImporter(
            isPresented: $isFileImporterPresented,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                Task {
                    await viewModel.loadImage(from: urls.first)
                }
            case .failure:
                viewModel.clearSelection()
            }
        }
        .onChange(of: layerCount) { _, newValue in
            selectedLayerIndex = min(selectedLayerIndex, newValue - 1)
        }
    }

    private var fileImportPane: some View {
        HStack(spacing: 12) {
            Button {
                isFileImporterPresented = true
            } label: {
                Label("画像を読み込む", systemImage: "photo.badge.plus")
            }
            .buttonStyle(.borderedProminent)

            statusView

            Spacer()

            Button {
                Task {
                    await viewModel.estimateDepthForSelectedImage()
                }
            } label: {
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
        if viewModel.isLoadingImage || viewModel.isEstimatingDepth {
            ProgressView()
                .controlSize(.small)
            Text(viewModel.isLoadingImage ? "読み込み中" : "深度推定中")
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

    private var previewWorkspace: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("プレビュー")
                    .font(.headline)

                Picker("表示", selection: $previewMode) {
                    ForEach(DepthPreviewMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.systemImageName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 520)

                Spacer()
            }

            DepthPreviewCanvas(
                mode: previewMode,
                inputImage: viewModel.inputImage,
                depthImage: viewModel.depthImage,
                isLoading: viewModel.isLoadingImage || viewModel.isEstimatingDepth,
                selectedLayer: layerDefinitions[safe: selectedLayerIndex],
                overlayOpacity: overlayOpacity
            )

            DepthRangeEditor(
                layerCount: layerCount,
                boundaries: $depthBoundaries,
                selectedLayerIndex: $selectedLayerIndex
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var layerControlPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("レイヤ設定")
                .font(.headline)

            Picker("分割数", selection: $layerCount) {
                Text("3 Layers").tag(3)
                Text("4 Layers").tag(4)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 8) {
                Text("オーバーレイ")
                    .font(.subheadline.weight(.semibold))
                HStack {
                    Image(systemName: "circle.lefthalf.filled")
                    Slider(value: $overlayOpacity, in: 0.2...0.85)
                    Text(overlayOpacity, format: .percent.precision(.fractionLength(0)))
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
                .foregroundStyle(.secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("深度レンジ")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Auto") {
                        autoSplitDepthRanges()
                    }
                    Button("Reset") {
                        resetDepthRanges()
                    }
                }

                ForEach(layerDefinitions) { layer in
                    LayerRangeRow(
                        layer: layer,
                        isSelected: layer.index == selectedLayerIndex
                    ) {
                        selectedLayerIndex = layer.index
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var layerDefinitions: [DepthLayerDefinition] {
        (0..<layerCount).map { index in
            let lowerBound = index == 0 ? 0 : depthBoundaries[index - 1]
            let upperBound = index == layerCount - 1 ? 1 : depthBoundaries[index]

            return DepthLayerDefinition(
                index: index,
                name: DepthLayerDefinition.names[index],
                lowerBound: lowerBound,
                upperBound: upperBound,
                color: DepthLayerDefinition.colors[index]
            )
        }
    }

    private func autoSplitDepthRanges() {
        if layerCount == 3 {
            depthBoundaries = [0.33, 0.66, 0.74]
        } else {
            depthBoundaries = [0.25, 0.50, 0.75]
        }
    }

    private func resetDepthRanges() {
        depthBoundaries = [0.22, 0.48, 0.74]
        selectedLayerIndex = min(3, layerCount - 1)
    }
}

private struct PreviewDepthEstimator: DepthEstimating {
    func estimateDepth(for image: CGImage) async throws -> CGImage {
        throw PreviewDepthEstimationError()
    }
}

private struct PreviewDepthEstimationError: Error {}

#Preview {
    ContentView(depthEstimator: PreviewDepthEstimator())
}
