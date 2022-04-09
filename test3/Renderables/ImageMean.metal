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
