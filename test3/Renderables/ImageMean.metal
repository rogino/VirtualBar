#include <metal_stdlib>
using namespace metal;
#import "./../Common.h"

struct VertexInImageMean {
  float3 position [[ attribute(0) ]];
};

struct VertexOutImageMean {
  float4 position [[ position ]];
  float2 texturePosition;
  
};

vertex VertexOutImageMean vertex_image_mean(
  const VertexInImageMean vertex_in [[ stage_in ]]
) {
  return {
    .position = float4(vertex_in.position, 1),
    .texturePosition =  float2(
     (vertex_in.position.x + 1) / 2,
     (vertex_in.position.y + 1) / 2
    )
  };
}

fragment float4 fragment_image_mean(
  const VertexOutImageMean in [[stage_in]],
  const texture2d<float> computedTexture [[texture(1)]],
  const texture2d<float> originalTexture [[texture(2)]],
  constant float &threshold [[buffer(3)]]
) {
  constexpr sampler textureSampler;
  float4 original = originalTexture.sample(textureSampler, in.texturePosition);
  float4 computed = computedTexture.sample(textureSampler, float2(0, in.texturePosition[1]));
  if (computed[0] + computed[1] + computed[2] + computed[3] > threshold * 4) return float4(1);
  float4 color = original;
  return color;
}


