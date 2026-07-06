//
//  ContentView.swift
//  image-depth-test
//
//  Created by enchantcode on 2026/07/04.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var viewModel = ImageDepthViewModel()
    @State private var isFileImporterPresented = false

    var body: some View {
        VStack(spacing: 16) {
            fileImportPane
            previewPane
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 520)
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
    }

    private var fileImportPane: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("画像を読み込む", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                if viewModel.isLoadingImage {
                    ProgressView()
                        .controlSize(.small)
                    Text("読み込み中")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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

                Spacer()
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private var previewPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("プレビュー")
                .font(.headline)

            HStack(spacing: 16) {
                ImagePreviewPanel(
                    title: "入力画像",
                    image: viewModel.inputImage,
                    systemImageName: "photo",
                    message: viewModel.isLoadingImage ? "読み込み中" : "画像未選択"
                )

                ImagePreviewPanel(
                    title: "深度マップ",
                    image: viewModel.depthImage,
                    systemImageName: "square.stack.3d.down.right",
                    message: viewModel.hasSelectedImage ? "深度推定は次の段階で実装" : "推定結果なし"
                )
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ImagePreviewPanel: View {
    let title: String
    let image: NSImage?
    let systemImageName: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.background)

                if let image {
                    Image(platformImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(12)
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImageName)
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
    }
}

private extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}

#Preview {
    ContentView()
}
