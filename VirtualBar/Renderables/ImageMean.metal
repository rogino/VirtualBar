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
  const texture2d<float> originalTexture [[texture(0)]],
  const texture2d<float> squashTexture [[texture(1)]],
  const texture2d<float> sobelTexture [[texture(2)]],
  constant float &threshold [[buffer(3)]],
  constant float* activeArea [[buffer(4)]],
  constant int &numActiveAreas [[buffer(5)]]
) {
  constexpr sampler textureSampler;
  float4 original = originalTexture.sample(textureSampler, in.texturePosition);
  float4 squash = squashTexture.sample(textureSampler, float2(0, in.texturePosition[1]));
  float4 sobel = sobelTexture.sample(textureSampler, float2(0, in.texturePosition[1]));
  
               
  if (in.texturePosition[0] < 0.1) return sobel * 5;
  if (in.texturePosition[0] > 0.9) return squash;
  if (in.texturePosition[0] >= 0.1 && in.texturePosition[0] < 0.11) {
    float val = dot(sobel, sobel) - 1;
    return float4(0, val > threshold ? 1: 0, 0, 1);
  }
  
  for (int i = 0; i < numActiveAreas; i++) {
    if (activeArea[i * 2] <= in.texturePosition[1] && in.texturePosition[1] <= activeArea[i * 2 + 1]) {
      return mix(
        float4(
          1,
          saturate(2.0 * float(i) / numActiveAreas),
          saturate(-0.5 + 2.0 * (float(i) / numActiveAreas)),
          1
        ),
        original,
        mix(0.3, 0.7, i/(numActiveAreas - 1))
      );
    }
  }
  
  float4 color = original;
  return color;
}


float2 tangentialDistortion(
  float2 inCoord,
  constant float *lensIntrinsics
) {
  // https://docs.nvidia.com/vpi/algo_ldc.html
  float r = length(inCoord - float2(0.5, 0.5));
  float r2 = r * r;
  float r4 = r2 * r2;
  float r6 = r2 * r4;
  
  float k1 = lensIntrinsics[0], k2 = lensIntrinsics[1],
        k3 = lensIntrinsics[2], k4 = lensIntrinsics[3],
        k5 = lensIntrinsics[4], k6 = lensIntrinsics[5];
  
  return inCoord *
    (1 + k1*r2 + k2*r4 + k3*r6)/
    (1 + k4*r2 + k5*r4 + k6*r6);
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
