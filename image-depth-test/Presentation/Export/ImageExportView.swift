//
//  ImageExportView.swift
//  image-depth-test
//

import SwiftUI

struct ImageExportView: View {
    @Bindable var session: ImageExportSession

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                ExportLayerListPane(
                    layers: session.layers,
                    setLayerIncluded: session.setLayer(_:isIncluded:)
                )

                ExportPreviewCanvas(
                    layers: session.layers,
                    contentID: session.previewContentID
                )
            }

            footer
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 620)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let errorMessage = session.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }

            Button("キャンセル") {
                session.cancel()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(session.isExporting)

            Button {
                session.export()
            } label: {
                Label("エクスポート", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!session.canExport)
        }
    }
}
