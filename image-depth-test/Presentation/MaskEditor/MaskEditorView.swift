//
//  MaskEditorView.swift
//  image-depth-test
//

import SwiftUI

struct MaskEditorView: View {
    @Bindable var session: MaskEditorSession
    @State private var synchronizedViewport = ZoomableScrollViewViewport()

    private let imagePadding: CGFloat = 14

    var body: some View {
        VStack(spacing: 12) {
            toolbar

            HStack(spacing: 14) {
                editorPane
                previewPane
            }

            if let errorMessage = session.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 620)
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Text(session.layerName)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            Picker("ツール", selection: $session.tool) {
                ForEach(MaskEditorTool.allCases) { tool in
                    Label(tool.title, systemImage: tool.systemImageName)
                        .tag(tool)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)

            Slider(value: $session.brushSize, in: 2...96) {
                Text("太さ")
            }
            .frame(width: 180)

            Text("\(Int(session.brushSize.rounded())) px")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)

            Button {
                session.discardAndClose()
            } label: {
                Label("破棄", systemImage: "xmark")
            }

            Button {
                session.saveAndClose()
            } label: {
                Label("保存", systemImage: "checkmark")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("マスク")
                .font(.subheadline.weight(.semibold))

            ZoomableScrollView(
                contentSize: contentSize,
                contentID: "\(session.layerID)-editor",
                synchronizedViewport: $synchronizedViewport
            ) {
                ZStack {
                    Image(nsImage: session.baseMaskImage)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: session.imageSize.width, height: session.imageSize.height)

                    PencilMaskCanvas(
                        strokes: $session.strokes,
                        tool: session.tool,
                        brushSize: session.brushSize
                    ) { strokes in
                        session.updateStrokes(strokes)
                    }
                    .frame(width: session.imageSize.width, height: session.imageSize.height)
                }
                .padding(imagePadding)
                .frame(width: contentSize.width, height: contentSize.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("プレビュー")
                .font(.subheadline.weight(.semibold))

            ZoomableScrollView(
                contentSize: contentSize,
                contentID: "\(session.layerID)-preview",
                synchronizedViewport: $synchronizedViewport
            ) {
                ZStack {
                    Image(nsImage: session.originalImage)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.34)
                        .frame(width: session.imageSize.width, height: session.imageSize.height)

                    Image(nsImage: session.maskedPreviewImage)
                        .resizable()
                        .scaledToFit()
                        .opacity(0.88)
                        .frame(width: session.imageSize.width, height: session.imageSize.height)

                    session.layerTintColor
                        .opacity(0.18)
                        .mask {
                            Image(nsImage: session.maskedPreviewImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: session.imageSize.width, height: session.imageSize.height)
                        }
                }
                .padding(imagePadding)
                .frame(width: contentSize.width, height: contentSize.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var contentSize: CGSize {
        CGSize(
            width: session.imageSize.width + imagePadding * 2,
            height: session.imageSize.height + imagePadding * 2
        )
    }
}
