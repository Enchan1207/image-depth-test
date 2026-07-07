//
//  DepthLayerShaders.metal
//  image-depth-test
//

#include <metal_stdlib>
using namespace metal;

struct DepthLayerSpec {
    float4 color;
    float2 range;
};

static bool containsDepth(float depth, float2 range, bool isLastLayer) {
    if (isLastLayer || range.y >= 1.0) {
        return depth >= range.x && depth <= range.y;
    }

    return depth >= range.x && depth < range.y;
}

kernel void makeDepthLayerCutout(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::write> outputTexture [[texture(2)]],
    constant float& lower [[buffer(0)]],
    constant float& upper [[buffer(1)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= outputTexture.get_width() || gid.y >= outputTexture.get_height()) {
        return;
    }

    const float depth = depthTexture.read(gid).r;
    const bool isInLayer = upper >= 1.0 ? (depth >= lower && depth <= upper) : (depth >= lower && depth < upper);

    if (isInLayer) {
        outputTexture.write(inputTexture.read(gid), gid);
    } else {
        outputTexture.write(float4(0.0), gid);
    }
}

kernel void makeDepthLayerPreview(
    texture2d<float, access::read> inputTexture [[texture(0)]],
    texture2d<float, access::read> depthTexture [[texture(1)]],
    texture2d<float, access::write> layerPreviewTexture [[texture(2)]],
    texture2d<float, access::write> overlayPreviewTexture [[texture(3)]],
    constant DepthLayerSpec* layers [[buffer(0)]],
    constant uint& layerCount [[buffer(1)]],
    constant float& overlayOpacity [[buffer(2)]],
    uint2 gid [[thread_position_in_grid]]
) {
    if (gid.x >= layerPreviewTexture.get_width() || gid.y >= layerPreviewTexture.get_height()) {
        return;
    }

    const float4 inputColor = inputTexture.read(gid);
    const float depth = depthTexture.read(gid).r;
    bool hasLayer = false;
    float4 layerColor = float4(0.0);

    for (uint index = 0; index < layerCount; ++index) {
        if (containsDepth(depth, layers[index].range, index == layerCount - 1)) {
            hasLayer = true;
            layerColor = layers[index].color;
            break;
        }
    }

    if (hasLayer) {
        layerPreviewTexture.write(layerColor, gid);
        overlayPreviewTexture.write(mix(inputColor, float4(layerColor.rgb, inputColor.a), overlayOpacity), gid);
    } else {
        layerPreviewTexture.write(float4(0.0), gid);
        overlayPreviewTexture.write(inputColor, gid);
    }
}
