//
//  ContentView.swift
//  image-depth-test
//
//  Created by enchantcode on 2026/07/04.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel: ImageDepthViewModel
    @State private var isFileImporterPresented = false
    @State private var previewMode: DepthPreviewMode = .overlay
    @State private var layerItems: [DepthLayerItem]
    @State private var selectedLayerID: DepthLayerItem.ID
    @State private var boundaries = [0.22, 0.48, 0.74]
    @State private var overlayOpacity = 0.56
    @State private var visibleLayerIDs: Set<DepthLayerItem.ID>
    @State private var layerRenderingTask: Task<Void, Never>?

    init(depthEstimator: any DepthEstimating) {
        let initialLayerItems = DepthLayerItem.initialItems
        _viewModel = State(initialValue: ImageDepthViewModel(depthEstimator: depthEstimator))
        _layerItems = State(initialValue: initialLayerItems)
        _selectedLayerID = State(initialValue: initialLayerItems.last?.id ?? UUID())
        _visibleLayerIDs = State(initialValue: Set(initialLayerItems.map(\.id)))
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
        .onChange(of: boundaries) { _, _ in
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
                layers: layerDefinitions,
                boundaries: $boundaries,
                selectedLayerID: $selectedLayerID
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

            Button {
                splitSelectedLayer()
            } label: {
                Label("分割して追加", systemImage: "plus.rectangle.on.rectangle")
            }

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

                ForEach(layerDefinitions) { layer in
                    LayerRangeRow(
                        layer: layer,
                        isSelected: layer.id == selectedLayerID,
                        isVisible: visibleLayerIDs.contains(layer.id),
                        canDelete: layerItems.count > 2
                    ) {
                        selectedLayerID = layer.id
                    } visibilityAction: {
                        toggleLayerVisibility(layer.id)
                    } deleteAction: {
                        deleteLayer(id: layer.id)
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
        layerItems.indices.map { index in
            let item = layerItems[index]
            let lowerBound = index == 0 ? 0 : boundaries[index - 1]
            let upperBound = index == layerItems.count - 1 ? 1 : boundaries[index]

            return DepthLayerDefinition(
                id: item.id,
                index: index,
                name: item.name,
                lowerBound: lowerBound,
                upperBound: upperBound,
                nsColor: item.color
            )
        }
    }

    private var layerRenderSpecs: [DepthLayerRenderSpec] {
        layerDefinitions.compactMap(\.renderSpec)
    }

    private var selectedLayerIndex: Int {
        layerItems.firstIndex { $0.id == selectedLayerID } ?? 0
    }

    private var visibleLayerCutoutImages: [NSImage] {
        layerDefinitions.enumerated().compactMap { index, layer in
            guard visibleLayerIDs.contains(layer.id) else { return nil }
            return viewModel.layerCutoutImages[safe: index]
        }
    }

    private func autoSplitDepthRanges() async {
        guard let suggestedBoundaries = await viewModel.suggestDepthBoundaries(layerCount: layerItems.count) else {
            resetDepthRanges()
            return
        }

        setActiveBoundaries(suggestedBoundaries)
        await generateLayerRenderings()
    }

    private func resetDepthRanges() {
        boundaries = defaultBoundaries(for: layerItems.count)
        selectedLayerID = layerItems[min(layerItems.count - 1, selectedLayerIndex)].id
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
        guard specs.count == layerItems.count else { return }

        await viewModel.generateLayerRenderings(
            layers: specs,
            overlayOpacity: overlayOpacity
        )
    }

    private func splitSelectedLayer() {
        let index = selectedLayerIndex
        guard let selectedDefinition = layerDefinitions[safe: index] else { return }

        let splitBoundary = (selectedDefinition.lowerBound + selectedDefinition.upperBound) / 2
        let insertedItem = DepthLayerItem(
            name: nextLayerName(after: selectedDefinition.name),
            color: nextLayerColor(for: layerItems.count)
        )

        layerItems.insert(insertedItem, at: index + 1)
        boundaries.insert(splitBoundary, at: index)
        selectedLayerID = insertedItem.id
        visibleLayerIDs.insert(insertedItem.id)
        scheduleLayerRenderingUpdate()
    }

    private func deleteLayer(id: DepthLayerItem.ID) {
        guard layerItems.count > 2,
              let index = layerItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removedItem = layerItems.remove(at: index)
        visibleLayerIDs.remove(removedItem.id)

        if boundaries.indices.contains(index) {
            boundaries.remove(at: index)
        } else if !boundaries.isEmpty {
            boundaries.removeLast()
        }

        let nextIndex = min(index, layerItems.count - 1)
        selectedLayerID = layerItems[nextIndex].id
        syncVisibleLayers()
        scheduleLayerRenderingUpdate()
    }

    private func setActiveBoundaries(_ activeBoundaries: [Double]) {
        var nextBoundaries = boundaries
        let sanitizedBoundaries = sanitized(activeBoundaries, expectedCount: layerItems.count - 1)

        for index in sanitizedBoundaries.indices {
            if index < nextBoundaries.count {
                nextBoundaries[index] = sanitizedBoundaries[index]
            } else {
                nextBoundaries.append(sanitizedBoundaries[index])
            }
        }

        boundaries = nextBoundaries
    }

    private func ensureBoundaryStorage(for layerCount: Int) {
        while boundaries.count < max(0, layerCount - 1) {
            let fallbackValue = Double(boundaries.count + 1) / Double(layerCount)
            boundaries.append(fallbackValue)
        }
    }

    private func defaultBoundaries(for layerCount: Int) -> [Double] {
        guard layerCount > 1 else { return [] }
        return (1..<layerCount).map { Double($0) / Double(layerCount) }
    }

    private func nextLayerName(after name: String) -> String {
        let baseName = "\(name) Split"
        guard layerItems.contains(where: { $0.name == baseName }) else {
            return baseName
        }

        var suffix = 2
        while layerItems.contains(where: { $0.name == "\(baseName) \(suffix)" }) {
            suffix += 1
        }
        return "\(baseName) \(suffix)"
    }

    private func nextLayerColor(for index: Int) -> NSColor {
        DepthLayerItem.presetColor(at: index)
    }

    private func syncSelection() {
        guard !layerItems.contains(where: { $0.id == selectedLayerID }) else { return }
        selectedLayerID = layerItems.last?.id ?? selectedLayerID
    }

    private func syncVisibleLayers() {
        let activeIDs = Set(layerItems.map(\.id))
        visibleLayerIDs = visibleLayerIDs.intersection(activeIDs)

        if visibleLayerIDs.isEmpty, let selectedItem = layerItems[safe: selectedLayerIndex] {
            visibleLayerIDs.insert(selectedItem.id)
        }
    }

    private func toggleLayerVisibility(_ id: DepthLayerItem.ID) {
        if visibleLayerIDs.contains(id) {
            visibleLayerIDs.remove(id)
        } else {
            visibleLayerIDs.insert(id)
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
