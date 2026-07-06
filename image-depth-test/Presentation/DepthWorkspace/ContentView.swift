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
    @State private var visibleLayerIndices: Set<Int> = [0, 1, 2, 3]
    @State private var layerRenderingTask: Task<Void, Never>?

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
                    await generateLayerRenderings()
                }
            case .failure:
                viewModel.clearSelection()
            }
        }
        .onChange(of: layerCount) { _, newValue in
            selectedLayerIndex = min(selectedLayerIndex, newValue - 1)
            ensureBoundaryStorageForLayerCount(newValue)
            syncVisibleLayers(for: newValue)
            scheduleLayerRenderingUpdate()
        }
        .onChange(of: depthBoundaries) { _, _ in
            scheduleLayerRenderingUpdate()
        }
        .onChange(of: overlayOpacity) { _, _ in
            scheduleLayerRenderingUpdate()
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
                    await generateLayerRenderings()
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
                layerPreviewImage: viewModel.layerPreviewImage,
                layerOverlayImage: viewModel.layerOverlayImage,
                cutoutImages: visibleLayerCutoutImages,
                isLoading: viewModel.isLoadingImage || viewModel.isEstimatingDepth || viewModel.isGeneratingLayerRenderings,
                selectedLayer: layerDefinitions[safe: selectedLayerIndex]
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
                        Task {
                            await autoSplitDepthRanges()
                        }
                    }
                    .disabled(!viewModel.canGenerateLayerRenderings)

                    Button("Reset") {
                        resetDepthRanges()
                    }
                }

                Button {
                    Task {
                        await generateLayerRenderings()
                        previewMode = .isolated
                    }
                } label: {
                    Label("切り抜きレイヤを表示", systemImage: "scope")
                }
                .frame(maxWidth: .infinity)
                .disabled(!viewModel.canGenerateLayerRenderings || viewModel.isGeneratingLayerRenderings)

                ForEach(layerDefinitions) { layer in
                    LayerRangeRow(
                        layer: layer,
                        isSelected: layer.index == selectedLayerIndex,
                        isVisible: visibleLayerIndices.contains(layer.index)
                    ) {
                        selectedLayerIndex = layer.index
                    } visibilityAction: {
                        toggleLayerVisibility(layer.index)
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
                renderColor: DepthLayerDefinition.renderColors[index]
            )
        }
    }

    private var layerRenderSpecs: [DepthLayerRenderSpec] {
        layerDefinitions.compactMap(\.renderSpec)
    }

    private var visibleLayerCutoutImages: [NSImage] {
        viewModel.layerCutoutImages.enumerated().compactMap { index, image in
            visibleLayerIndices.contains(index) ? image : nil
        }
    }

    private func autoSplitDepthRanges() async {
        guard let suggestedBoundaries = await viewModel.suggestDepthBoundaries(layerCount: layerCount) else {
            resetDepthRanges()
            return
        }

        setActiveBoundaries(suggestedBoundaries)
        await generateLayerRenderings()
    }

    private func resetDepthRanges() {
        depthBoundaries = [0.22, 0.48, 0.74]
        selectedLayerIndex = min(3, layerCount - 1)
        scheduleLayerRenderingUpdate()
    }

    private func scheduleLayerRenderingUpdate() {
        layerRenderingTask?.cancel()
        layerRenderingTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await generateLayerRenderings()
        }
    }

    private func generateLayerRenderings() async {
        let specs = layerRenderSpecs
        guard specs.count == layerCount else { return }

        await viewModel.generateLayerRenderings(
            layers: specs,
            overlayOpacity: overlayOpacity
        )
    }

    private func setActiveBoundaries(_ activeBoundaries: [Double]) {
        var nextBoundaries = depthBoundaries
        let sanitizedBoundaries = sanitized(activeBoundaries, expectedCount: layerCount - 1)

        for index in sanitizedBoundaries.indices {
            if index < nextBoundaries.count {
                nextBoundaries[index] = sanitizedBoundaries[index]
            } else {
                nextBoundaries.append(sanitizedBoundaries[index])
            }
        }

        depthBoundaries = nextBoundaries
    }

    private func ensureBoundaryStorageForLayerCount(_ newLayerCount: Int) {
        guard newLayerCount == 4, depthBoundaries.count < 3 else { return }

        while depthBoundaries.count < 3 {
            depthBoundaries.append(0.75)
        }
    }

    private func syncVisibleLayers(for newLayerCount: Int) {
        visibleLayerIndices = visibleLayerIndices.filter { $0 < newLayerCount }

        if visibleLayerIndices.isEmpty {
            visibleLayerIndices.insert(min(selectedLayerIndex, newLayerCount - 1))
        }
    }

    private func toggleLayerVisibility(_ index: Int) {
        if visibleLayerIndices.contains(index) {
            visibleLayerIndices.remove(index)
        } else {
            visibleLayerIndices.insert(index)
        }

        previewMode = .isolated
    }

    private func sanitized(_ boundaries: [Double], expectedCount: Int) -> [Double] {
        let minimumGap = 0.04
        var sanitizedBoundaries = Array(boundaries.prefix(expectedCount)).sorted()

        while sanitizedBoundaries.count < expectedCount {
            let fallbackValue = Double(sanitizedBoundaries.count + 1) / Double(expectedCount + 1)
            sanitizedBoundaries.append(fallbackValue)
        }

        for index in sanitizedBoundaries.indices {
            let lowerLimit = index == 0 ? minimumGap : sanitizedBoundaries[index - 1] + minimumGap
            let upperLimit = 1 - minimumGap * Double(expectedCount - index)
            sanitizedBoundaries[index] = min(max(sanitizedBoundaries[index], lowerLimit), upperLimit)
        }

        return sanitizedBoundaries
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
