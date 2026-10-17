#include <metal_stdlib>
using namespace metal;

struct VertexOut { float4 position [[position]]; float2 uv; };
struct Uniforms { float2 crop; uint effect; float padding; };

vertex VertexOut cameraVertex(uint id [[vertex_id]]) {
    float2 p = float2((id << 1) & 2, id & 2);
    VertexOut out;
    out.position = float4(p * 2.0 - 1.0, 0, 1);
    out.uv = float2(p.x, 1.0 - p.y);
    return out;
}

fragment float4 cameraFragment(VertexOut in [[stage_in]],
                               texture2d<float> camera [[texture(0)]],
                               constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler sampleFilter(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 portraitUV = (in.uv - 0.5) * u.crop + 0.5;
    // The rear camera delivers landscape buffers. Rotate clockwise for portrait.
    float2 sourceUV = float2(portraitUV.y, 1.0 - portraitUV.x);
    float3 color = camera.sample(sampleFilter, sourceUV).rgb;
    if (u.effect == 1) {
        color = float3(dot(color, float3(0.2126, 0.7152, 0.0722)));
    } else if (u.effect == 2) {
        color = mix(color, color * float3(1.0, 0.65, 0.35) + float3(0.10, 0.025, 0.0), 0.65);
    } else if (u.effect == 3) {
        float radius = length((in.uv - 0.5) * 2.0);
        color *= 1.0 - 0.75 * smoothstep(0.35, 1.25, radius);
    }
    return float4(clamp(color, 0.0, 1.0), 1.0);
}
