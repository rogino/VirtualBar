#include <metal_stdlib>
using namespace metal;
#import "./../Common.h"


struct VertexOutImageMean {
  float4 position [[ position ]];
  float2 texturePosition;
  
};

vertex VertexOutImageMean vertex_image_mean(
  constant float2 *vertices           [[buffer(0)]],
  constant float2 *textureCoordinates [[buffer(1)]],
            uint id                   [[vertex_id]]
) {
  return {
    .position        = float4(vertices[id], 0, 1),
    // Mirror the image
    .texturePosition = float2(1 - textureCoordinates[id].x, textureCoordinates[id].y)
  };
}

fragment float4 fragment_image_mean(
  const VertexOutImageMean in [[stage_in]],
  const texture2d<float> computedTexture [[texture(1)]],
  const texture2d<float> originalTexture [[texture(2)]],
  constant float &threshold [[buffer(3)]],
  constant float* activeArea [[buffer(4)]]
) {
  constexpr sampler textureSampler;
  float4 original = originalTexture.sample(textureSampler, in.texturePosition);
  float4 computed = computedTexture.sample(textureSampler, float2(0, in.texturePosition[1]));
  
               
  if (in.texturePosition[0] < 0.1) return computed * 5;
  
  if (activeArea[0] <= in.texturePosition[1] && in.texturePosition[1] <= activeArea[1]) {
    return mix(float4(1, 0, 0, 0), original, 0.3);
  }
  
  if (computed[0] + computed[1] + computed[2] > threshold * 3) return float4(1);
  
  float4 color = original;
  return color;
}


kernel void line_of_symmetry(
  texture2d<float> sobelTexture [[texture(0)]],
  // https://stackoverflow.com/questions/47738441/passing-textures-with-uint8-component-type-to-metal-compute-shader
  // Sobel texture is uint8_t but automatically converted to float
  device float *outputBuffer [[buffer(0)]],
  constant LineOfSymmetryArgs &args [[buffer(1)]],
  uint index [[thread_position_in_grid]]
) {
  constexpr sampler s(coord::pixel);
  float center = index;
  
  if (center < args.deadzone || sobelTexture.get_height() - center - 1 < args.deadzone) {
    outputBuffer[index] = INFINITY;
    return;
  }
  float sum = 0;
  int n = min(center, sobelTexture.get_height() - center - 1);
  for (int i = 1; i <= n; i++) {
    float3 below = sobelTexture.sample(s, float2(0, center - i)).rgb;
    float3 above = sobelTexture.sample(s, float2(0, center + i)).rgb;
    float3 delta = below - above; // Take advantage of RGB data colour differences
    // TODO get rid of division - not requied
    sum += dot(delta, delta) / 3;
  }
  outputBuffer[index] = sum / n;
}
