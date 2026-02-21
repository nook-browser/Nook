#include <metal_stdlib>
using namespace metal;

static float hash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float noise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(hash(i + float2(0,0)), hash(i + float2(1,0)), u.x),
        mix(hash(i + float2(0,1)), hash(i + float2(1,1)), u.x),
        u.y
    );
}

[[stitchable]] half4 transitionReveal(
    float2 position,
    half4 color,
    float progress,
    float2 size
) {
    float2 uv = position / size;
    float aspect = size.x / size.y;
    float dist = length((uv - 0.5) * float2(aspect, 1.0));
    float maxDist = length(float2(0.5 * aspect, 0.5));
    float n = noise(uv * 6.0 + progress * 2.0);
    float distorted = (dist / maxDist) + (n - 0.5) * 0.12;
    float mask = smoothstep(progress - 0.12, progress + 0.12, distorted);
    return color * half(mask);
}
