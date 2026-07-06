//
//  ContentView.swift
//  image-depth-test
//
//  Created by enchantcode on 2026/07/04.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isFileImporterPresented = false
    @State private var selectedFileName: String?

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
                selectedFileName = urls.first?.lastPathComponent
            case .failure:
                selectedFileName = nil
            }
        }
    }

    private var fileImportPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button {
                    isFileImporterPresented = true
                } label: {
                    Label("画像を読み込む", systemImage: "photo.badge.plus")
                }
                .buttonStyle(.borderedProminent)

                if let selectedFileName {
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
                    systemImageName: "photo",
                    message: selectedFileName == nil ? "画像未選択" : "画像表示は次の段階で実装"
                )

                ImagePreviewPanel(
                    title: "深度マップ",
                    systemImageName: "square.stack.3d.down.right",
                    message: selectedFileName == nil ? "推定結果なし" : "深度推定は次の段階で実装"
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
    let systemImageName: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 12) {
                Image(systemName: systemImageName)
                    .font(.system(size: 42, weight: .regular))
                    .foregroundStyle(.secondary)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.quaternary, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

#Preview {
    ContentView()
}
