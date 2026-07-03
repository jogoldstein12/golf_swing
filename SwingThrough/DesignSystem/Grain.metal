// Warm film grain to defeat flat digital sterility — extremely subtle (~2.5%).
// Static hash on position so it doesn't shimmer frame to frame.
#include <metal_stdlib>
using namespace metal;

[[ stitchable ]] half4 grain(float2 position, half4 color, float intensity) {
    float n = fract(sin(dot(floor(position), float2(12.9898, 78.233))) * 43758.5453);
    half g = half(n - 0.5) * half(intensity);
    return half4(color.rgb + g, color.a);
}
