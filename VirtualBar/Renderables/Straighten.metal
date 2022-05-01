//
//  Straighten.metal
//  VirtualBar
//
//  Created by Rio Ogino on 19/04/22.
//

#include <metal_stdlib>
using namespace metal;
#import "./../Common.h"
#import "./PlonkTextureShared.metal"


kernel void straighten_mean_left_right(
  constant StraightenParams& config [[buffer(0)]],
  texture2d<half,  access::read > image [[texture(0)]],
  texture2d<float, access::write>  mean [[texture(1)]],
                                    
  ushort2 pid [[thread_position_in_grid]]
) {
  ushort y = pid.x;
  bool isLeft = pid.y == 0;
  
  ushort startX = isLeft ? config.leftX: config.rightX;
  
  float4 sum = float(0);
  for(ushort x = 0; x < config.width; x++) {
    sum += float4(image.read(ushort2(startX + x, y)));
  }
  mean.write(sum / config.width, ushort2(pid.y, pid.x));
}

kernel void straighten_left_right_delta_squared(
  constant StraightenParams& config        [[buffer(0)]],
  texture2d<float, access::write> delta    [[texture(0)]],
  texture2d<float,  access::read>  rowMean [[texture(1)]],
                                    
  ushort2 pid [[thread_position_in_grid]]
) {
  ushort yLeft = pid.x;
  short i = config.offsetYMin + short(pid.y);
  short yRight = yLeft - i;
  
  if (short(delta.get_height()) <= yLeft  ||
      short(delta.get_height()) <= yRight || yRight < 0
  ) {
    return;
  }
  
  float4 left  = rowMean.read(ushort2(0, yLeft ));
  float4 right = rowMean.read(ushort2(1, yRight));
  
  // Find difference as a *proportion* of the larger value, not absolute
  // (0.1, 0.2) is bigger error than (0.8, 0.9)
  float3 diff = left.xyz - right.xyz;
  float diffSquared = dot(diff, diff);
  
  float3 larger = length(left) > length(right) ? float3(left.xyz): float3(right.xyz);
  float denominator = dot(larger, larger);
  
  delta.write(diffSquared/denominator, pid.yx); // y is image y axis, x is i
}




fragment float4 fragment_straighten(
  const VertexOutPlonkTexture in [[stage_in]],
  constant float3x3 &transform [[buffer(0)]],
  const texture2d<float> originalTexture [[texture(0)]]
//  const texture2d<float> leftTexture [[texture(1)]],
//  const texture2d<float> rightTexture [[texture(2)]],
//  const texture2d<float> deltaAvgTexture [[texture(3)]]
) {
  constexpr sampler textureSampler(filter::linear);
  
  float2 pos = (transform * float3(in.texturePosition, 1)).xy;
//  
//  if (in.texturePosition.y < 0.5) {
//    pos.y *= 2;
//  } else {
//    pos.y = (pos.y * 2) - 1;
//  }
  float4 color = originalTexture.sample(textureSampler, pos);
  
  return color;
}
