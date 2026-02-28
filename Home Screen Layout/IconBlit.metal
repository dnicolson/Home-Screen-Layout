#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut fullscreenVertex(uint vertexId [[vertex_id]]) {
    float2 positions[3] = {
        float2(-1.0, -1.0),
        float2( 3.0, -1.0),
        float2(-1.0,  3.0)
    };

    float2 pos = positions[vertexId];

    VertexOut out;
    out.position = float4(pos, 0.0, 1.0);
    out.uv = float2((pos.x + 1.0) * 0.5, (1.0 - pos.y) * 0.5);
    return out;
}

fragment half4 textureBlitFragment(VertexOut in [[stage_in]], texture2d<half, access::sample> sourceTexture [[texture(0)]]) {
    constexpr sampler textureSampler(address::clamp_to_edge, filter::linear);
    return sourceTexture.sample(textureSampler, in.uv);
}
