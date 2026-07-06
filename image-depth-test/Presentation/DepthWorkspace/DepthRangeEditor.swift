//
//  DepthRangeEditor.swift
//  image-depth-test
//

import SwiftUI

struct DepthRangeEditor: View {
    let layerCount: Int
    @Binding var boundaries: [Double]
    @Binding var selectedLayerIndex: Int

    private let handleWidth: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Far")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Front")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            GeometryReader { proxy in
                let width = proxy.size.width

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(0..<layerCount, id: \.self) { index in
                            DepthLayerDefinition.colors[index]
                                .frame(width: segmentWidth(for: index, totalWidth: width))
                                .onTapGesture {
                                    selectedLayerIndex = index
                                }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    ForEach(0..<(layerCount - 1), id: \.self) { index in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(.white)
                            .shadow(radius: 2)
                            .frame(width: handleWidth, height: 36)
                            .overlay {
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(.black.opacity(0.25), lineWidth: 1)
                            }
                            .position(x: CGFloat(boundaries[index]) * width, y: 18)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        selectedLayerIndex = min(index + 1, layerCount - 1)
                                        updateBoundary(index, locationX: value.location.x, width: width)
                                    }
                            )
                    }
                }
            }
            .frame(height: 36)
        }
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
    }

    private func segmentWidth(for index: Int, totalWidth: CGFloat) -> CGFloat {
        let lowerBound = index == 0 ? 0 : boundaries[index - 1]
        let upperBound = index == layerCount - 1 ? 1 : boundaries[index]
        return max(0, CGFloat(upperBound - lowerBound) * totalWidth)
    }

    private func updateBoundary(_ index: Int, locationX: CGFloat, width: CGFloat) {
        guard width > 0 else { return }

        let minimumGap = 0.04
        let previousBoundary = index == 0 ? 0 : boundaries[index - 1]
        let nextBoundary = index == layerCount - 2 ? 1 : boundaries[index + 1]
        let normalizedLocation = Double(locationX / width)
        boundaries[index] = min(max(normalizedLocation, previousBoundary + minimumGap), nextBoundary - minimumGap)
    }
}
