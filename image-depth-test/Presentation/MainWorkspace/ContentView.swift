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
    @State private var lastAcceptedBoundaries = [0.22, 0.48, 0.74]
    @State private var layerRenderingTask: Task<Void, Never>?
    @State private var isEditingDepthRange = false
    @State private var isRevertingDepthBoundaryChange = false
    @State private var editedMasksByLayerID: [UUID: CGImage] = [:]
    @State private var maskEditorRegistry = MaskEditorWindowRegistry()

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
            FileImportPane(
                viewModel: viewModel,
                importImageAction: presentImageImporter,
                reestimateAction: reestimateDepthForSelectedImage
            )

            HStack(alignment: .top, spacing: 14) {
                PreviewWorkspacePane(
                    layers: visiblePreviewLayers,
                    workspaceID: previewWorkspaceID,
                    placeholderSystemImage: visiblePreviewPlaceholderSystemImage,
                    placeholderMessage: visiblePreviewPlaceholderMessage,
                    isLoading: isProcessingImage,
                    selectedLayer: layerDefinitions[safe: selectedLayerIndex],
                    layerDefinitions: layerDefinitions,
                    boundaries: $boundaries,
                    selectedLayerID: $selectedLayerID,
                    rangeEditingChanged: handleDepthRangeEditingChanged
                )

                LayerControlPane(
                    layers: layerDefinitions,
                    layerCount: layerItems.count,
                    selectedLayerID: $selectedLayerID,
                    visiblePreviewTargets: $visiblePreviewTargets,
                    editedMaskLayerIDs: Set(editedMasksByLayerID.keys),
                    availableLayerIndexes: availableLayerIndexes,
                    canGenerateLayerRenderings: viewModel.canGenerateLayerRenderings,
                    isDepthMapAvailable: viewModel.depthImage != nil,
                    isOriginalAvailable: viewModel.inputImage != nil,
                    canEditMask: canEditMask(for:),
                    splitSelectedLayer: splitSelectedLayer,
                    autoSplitDepthRanges: {
                        Task {
                            await autoSplitDepthRanges()
                        }
                    },
                    resetDepthRanges: resetDepthRanges,
                    editMask: { layer in
                        Task {
                            await openMaskEditor(for: layer)
                        }
                    },
                    deleteLayer: deleteLayer(id:),
                    togglePreviewTarget: togglePreviewTarget
                )
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
            if isRevertingDepthBoundaryChange {
                isRevertingDepthBoundaryChange = false
                return
            }

            if !editedMasksByLayerID.isEmpty {
                let shouldDiscard = confirmDiscardEditedMasks(
                    messageText: "深度レンジを変更すると編集済みマスクは再構成されます。",
                    informativeText: "続行すると全レイヤの編集済みマスクを破棄します。"
                )

                guard shouldDiscard else {
                    isRevertingDepthBoundaryChange = true
                    boundaries = lastAcceptedBoundaries
                    return
                }

                discardEditedMasksAndCloseEditors()
            }

            lastAcceptedBoundaries = boundaries
            scheduleLayerRenderingUpdate(includeCutouts: !isEditingDepthRange)
        }
    }

    private var isProcessingImage: Bool {
        viewModel.isLoadingImage || viewModel.isEstimatingDepth || viewModel.isGeneratingLayerRenderings
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

    private var availableLayerIndexes: Set<Int> {
        Set(viewModel.layerCutoutImages.indices)
    }

    private var visiblePreviewLayers: [DepthPreviewCanvasLayer] {
        var layers: [DepthPreviewCanvasLayer] = []

        if visiblePreviewTargets.contains(.original), let inputImage = viewModel.inputImage {
            layers.append(DepthPreviewCanvasLayer(id: PreviewDisplayTarget.original, image: inputImage, tintColor: nil))
        }

        if visiblePreviewTargets.contains(.depthMap), let depthImage = viewModel.depthImage {
            layers.append(DepthPreviewCanvasLayer(id: PreviewDisplayTarget.depthMap, image: depthImage, tintColor: nil))
        }

        for layer in layerDefinitions {
            let target = PreviewDisplayTarget.layer(layer.id)
            guard visiblePreviewTargets.contains(target),
                  let image = viewModel.layerCutoutImages[safe: layer.index] else {
                continue
            }

            layers.append(DepthPreviewCanvasLayer(id: target, image: image, tintColor: layer.color))
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

    private func presentImageImporter() {
        if confirmDiscardEditedMasks(
            messageText: "画像を変更すると編集済みマスクは破棄されます。",
            informativeText: "続行すると開いているマスクエディタも閉じます。"
        ) {
            discardEditedMasksAndCloseEditors()
            isFileImporterPresented = true
        }
    }

    private func reestimateDepthForSelectedImage() {
        Task {
            await viewModel.estimateDepthForSelectedImage()
            discardEditedMasksAndCloseEditors()
            await generateLayerRenderings()
        }
    }

    private func autoSplitDepthRanges() async {
        guard confirmDiscardEditedMasks(
            messageText: "深度レンジの自動分割で編集済みマスクは再構成されます。",
            informativeText: "続行すると全レイヤの編集済みマスクを破棄します。"
        ) else {
            return
        }

        discardEditedMasksAndCloseEditors()

        guard let suggestedBoundaries = await viewModel.suggestDepthBoundaries(layerCount: layerItems.count) else {
            resetDepthRanges()
            return
        }

        setActiveBoundaries(suggestedBoundaries)
        await generateLayerRenderings()
    }

    private func resetDepthRanges() {
        guard confirmDiscardEditedMasks(
            messageText: "深度レンジのリセットで編集済みマスクは再構成されます。",
            informativeText: "続行すると全レイヤの編集済みマスクを破棄します。"
        ) else {
            return
        }

        discardEditedMasksAndCloseEditors()
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
            overlayOpacity: overlayOpacity,
            editedMasksByLayerID: editedMasksByLayerID,
            layerIDsByIndex: layerDefinitions.map(\.id)
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
        lastAcceptedBoundaries = boundaries
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
        editedMasksByLayerID.removeValue(forKey: removedItem.id)
        visiblePreviewTargets.remove(.layer(removedItem.id))

        if boundaries.indices.contains(index) {
            boundaries.remove(at: index)
        } else if !boundaries.isEmpty {
            boundaries.removeLast()
        }

        let nextIndex = min(index, layerItems.count - 1)
        selectedLayerID = layerItems[nextIndex].id
        lastAcceptedBoundaries = boundaries
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

    private func canEditMask(for layer: DepthLayerDefinition) -> Bool {
        viewModel.canEditLayerMasks && layer.renderSpec != nil
    }

    private func openMaskEditor(for layer: DepthLayerDefinition) async {
        guard let inputImage = viewModel.inputCGImageForEditing(),
              let renderSpec = layer.renderSpec else {
            return
        }

        let initialMask: CGImage?
        if let editedMask = editedMasksByLayerID[layer.id] {
            initialMask = editedMask
        } else {
            initialMask = await viewModel.makeInitialMask(for: renderSpec)
        }

        guard let initialMask else { return }

        maskEditorRegistry.openEditor(
            layerID: layer.id,
            layerName: layer.name,
            layerColor: layer.nsColor,
            inputImage: inputImage,
            initialMask: initialMask
        ) { mask in
            editedMasksByLayerID[layer.id] = mask
            Task {
                await generateLayerRenderings()
            }
        }
    }

    private func confirmDiscardEditedMasks(messageText: String, informativeText: String) -> Bool {
        guard !editedMasksByLayerID.isEmpty else { return true }

        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.alertStyle = .warning
        alert.addButton(withTitle: "続行")
        alert.addButton(withTitle: "キャンセル")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func discardEditedMasksAndCloseEditors() {
        editedMasksByLayerID.removeAll()
        maskEditorRegistry.closeAllDiscardingChanges()
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

private struct PreviewDepthEstimator: DepthEstimating {
    func estimateDepth(for image: CGImage) async throws -> DepthEstimationResult {
        throw PreviewDepthEstimationError()
    }
}

private struct PreviewDepthEstimationError: Error {}

#Preview {
    ContentView(depthEstimator: PreviewDepthEstimator(), layerRenderer: CPUDepthLayerRenderer())
}
