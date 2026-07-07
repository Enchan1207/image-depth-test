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
    @State private var layerItems: [DepthLayerItem]
    @State private var selectedLayerID: DepthLayerItem.ID
    @State private var visiblePreviewTargets: Set<PreviewDisplayTarget>
    @State private var boundaries = [0.22, 0.48, 0.74]
    @State private var layerRenderingTask: Task<Void, Never>?
    @State private var isEditingDepthRange = false

    private let overlayOpacity = 0.56

    init(depthEstimator: any DepthEstimating, layerRenderer: any DepthLayerRendering) {
        let initialLayerItems = DepthLayerItem.initialItems
        _viewModel = State(initialValue: ImageDepthViewModel(depthEstimator: depthEstimator, layerRenderer: layerRenderer))
        let initialSelectedLayerID = initialLayerItems.last?.id ?? UUID()
        _layerItems = State(initialValue: initialLayerItems)
        _selectedLayerID = State(initialValue: initialSelectedLayerID)
        _visiblePreviewTargets = State(initialValue: Set([.original] + initialLayerItems.map { .layer($0.id) }))
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
            scheduleLayerRenderingUpdate(includeCutouts: !isEditingDepthRange)
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
            Text("プレビュー")
                .font(.headline)

            DepthPreviewCanvas(
                layers: visiblePreviewLayers,
                workspaceID: previewWorkspaceID,
                placeholderSystemImage: visiblePreviewPlaceholderSystemImage,
                placeholderMessage: visiblePreviewPlaceholderMessage,
                isLoading: viewModel.isLoadingImage || viewModel.isEstimatingDepth || viewModel.isGeneratingLayerRenderings,
                selectedLayer: layerDefinitions[safe: selectedLayerIndex]
            )

            DepthRangeEditor(
                layers: layerDefinitions,
                boundaries: $boundaries,
                selectedLayerID: $selectedLayerID
            ) { isEditing in
                handleDepthRangeEditingChanged(isEditing)
            }
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
                        canDelete: layerItems.count > 2
                    ) {
                        selectedLayerID = layer.id
                    } deleteAction: {
                        deleteLayer(id: layer.id)
                    }
                }
            }

            Spacer(minLength: 12)

            displayControlPane
        }
        .padding(16)
        .frame(width: 300)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var displayControlPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("表示")
                .font(.subheadline.weight(.semibold))

            ForEach(layerDefinitions.reversed()) { layer in
                let target = PreviewDisplayTarget.layer(layer.id)
                previewTargetButton(
                    title: layer.name,
                    systemImageName: "scope",
                    tint: layer.color,
                    isVisible: visiblePreviewTargets.contains(target),
                    isAvailable: viewModel.layerCutoutImages.indices.contains(layer.index)
                ) {
                    togglePreviewTarget(target)
                }
            }

            previewTargetButton(
                title: "深度マップ",
                systemImageName: "square.stack.3d.down.right",
                isVisible: visiblePreviewTargets.contains(.depthMap),
                isAvailable: viewModel.depthImage != nil
            ) {
                togglePreviewTarget(.depthMap)
            }

            previewTargetButton(
                title: "元画像",
                systemImageName: "photo",
                isVisible: visiblePreviewTargets.contains(.original),
                isAvailable: viewModel.inputImage != nil
            ) {
                togglePreviewTarget(.original)
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func previewTargetButton(
        title: String,
        systemImageName: String,
        tint: Color? = nil,
        isVisible: Bool,
        isAvailable: Bool,
        action: @escaping () -> Void
    ) -> some View {
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

                if isVisible {
                    Image(systemName: "eye.fill")
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.tint)
                } else {
                    Image(systemName: "eye.slash")
                        .frame(width: 22, height: 22)
                        .foregroundStyle(.tertiary)
                }
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

    private var visiblePreviewLayers: [DepthPreviewCanvasLayer] {
        var layers: [DepthPreviewCanvasLayer] = []

        if visiblePreviewTargets.contains(.original), let inputImage = viewModel.inputImage {
            layers.append(DepthPreviewCanvasLayer(id: PreviewDisplayTarget.original, image: inputImage))
        }

        if visiblePreviewTargets.contains(.depthMap), let depthImage = viewModel.depthImage {
            layers.append(DepthPreviewCanvasLayer(id: PreviewDisplayTarget.depthMap, image: depthImage))
        }

        for layer in layerDefinitions {
            let target = PreviewDisplayTarget.layer(layer.id)
            guard visiblePreviewTargets.contains(target),
                  let image = viewModel.layerCutoutImages[safe: layer.index] else {
                continue
            }

            layers.append(DepthPreviewCanvasLayer(id: target, image: image))
        }

        return layers
    }

    private var visiblePreviewPlaceholderSystemImage: String {
        if visiblePreviewTargets.isEmpty { return "eye.slash" }
        if visiblePreviewTargets.contains(.depthMap) { return "square.stack.3d.down.right" }
        if visiblePreviewTargets.contains(.original) { return "photo" }
        return "scope"
    }

    private var visiblePreviewPlaceholderMessage: String {
        if viewModel.isLoadingImage { return "読み込み中" }
        if viewModel.isEstimatingDepth { return "深度推定中" }
        if viewModel.isGeneratingLayerRenderings { return "レイヤ生成中" }
        if visiblePreviewTargets.isEmpty { return "表示中の項目なし" }
        if viewModel.inputImage == nil { return "画像未選択" }
        return "表示できる画像がありません"
    }

    private var previewWorkspaceID: AnyHashable {
        if let inputImage = viewModel.inputImage {
            return ObjectIdentifier(inputImage)
        }

        return "empty-preview-workspace"
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
        scheduleLayerRenderingUpdate(includeCutouts: true)
    }

    private func scheduleLayerRenderingUpdate(includeCutouts: Bool) {
        layerRenderingTask?.cancel()
        layerRenderingTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            if includeCutouts {
                await generateLayerRenderings()
            } else {
                await generateLayerPreviews()
            }
        }
    }

    private func handleDepthRangeEditingChanged(_ isEditing: Bool) {
        isEditingDepthRange = isEditing
        if !isEditing {
            scheduleLayerRenderingUpdate(includeCutouts: true)
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

    private func generateLayerPreviews() async {
        let specs = layerRenderSpecs
        guard specs.count == layerItems.count else { return }

        await viewModel.generateLayerPreviews(
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
        visiblePreviewTargets.insert(.layer(insertedItem.id))
        scheduleLayerRenderingUpdate(includeCutouts: true)
    }

    private func deleteLayer(id: DepthLayerItem.ID) {
        guard layerItems.count > 2,
              let index = layerItems.firstIndex(where: { $0.id == id }) else {
            return
        }

        let removedItem = layerItems.remove(at: index)
        visiblePreviewTargets.remove(.layer(removedItem.id))

        if boundaries.indices.contains(index) {
            boundaries.remove(at: index)
        } else if !boundaries.isEmpty {
            boundaries.removeLast()
        }

        let nextIndex = min(index, layerItems.count - 1)
        selectedLayerID = layerItems[nextIndex].id
        scheduleLayerRenderingUpdate(includeCutouts: true)
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

    private func togglePreviewTarget(_ target: PreviewDisplayTarget) {
        if visiblePreviewTargets.contains(target) {
            visiblePreviewTargets.remove(target)
        } else {
            visiblePreviewTargets.insert(target)
        }
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

private enum PreviewDisplayTarget: Hashable {
    case original
    case depthMap
    case layer(UUID)
}

private struct PreviewDepthEstimator: DepthEstimating {
    func estimateDepth(for image: CGImage) async throws -> DepthEstimationResult {
        throw PreviewDepthEstimationError()
    }
}

private struct PreviewDepthEstimationError: Error {}

#Preview {
    ContentView(depthEstimator: PreviewDepthEstimator(), layerRenderer: CPUDepthLayerRenderer())
}
