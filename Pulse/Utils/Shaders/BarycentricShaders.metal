#include <metal_stdlib>
using namespace metal;

// Barycentric tri-color gradient over a fixed triangle in normalized space.
// Parameters are provided by SwiftUI Shader:
// - position: pixel position in layer space
// - bounds:   layer bounds (x, y, width, height)
// - ca, cb, cc: colors (RGBA, premultiplied not assumed)
// - pA, pB, pC: anchor positions in normalized [0,1] coordinates
// Stitchable signature for Canvas fill shader:
// position (auto), then custom params as provided in Swift.
half4 baryTriGradient(float2 position,
                      half4 ca,
                      half4 cb,
                      half4 cc,
                      float2 size,
                      float2 pA,
                      float2 pB,
                      float2 pC) [[ stitchable ]] {
    // Normalize position to [0,1] using provided size
    float2 uv = float2(position.x / max(size.x, 1.0),
                       position.y / max(size.y, 1.0));

    // Barycentric coordinates relative to triangle pA, pB, pC
    float2 v0 = pB - pA;
    float2 v1 = pC - pA;
    float2 v2 = uv - pA;
    float d00 = dot(v0, v0);
    float d01 = dot(v0, v1);
    float d11 = dot(v1, v1);
    float d20 = dot(v2, v0);
    float d21 = dot(v2, v1);
    float denom = max(d00 * d11 - d01 * d01, 1e-6);
    float v = (d11 * d20 - d01 * d21) / denom;
    float w = (d00 * d21 - d01 * d20) / denom;
    float u = 1.0 - v - w;

    // Clamp to non-negative and renormalize to avoid seams at triangle edges
    u = max(0.0, u);
    v = max(0.0, v);
    w = max(0.0, w);
    float sum = max(1e-6, (u + v + w));
    u /= sum; v /= sum; w /= sum;

    // Premultiplied blending to respect per-color alpha
    half a = u * ca.a + v * cb.a + w * cc.a;
    half3 rgbPremul = (half3(ca.rgb) * ca.a) * u + (half3(cb.rgb) * cb.a) * v + (half3(cc.rgb) * cc.a) * w;
    half3 rgb = (a > 0) ? rgbPremul / a : rgbPremul;
    return half4(rgb, a);
}
