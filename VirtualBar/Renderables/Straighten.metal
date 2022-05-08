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
  texture2d<float, access::read > image [[texture(0)]],
  texture2d<float, access::write>  mean [[texture(1)]],
                                    
  ushort2 pid [[thread_position_in_grid]]
) {
  ushort startX = pid.x == 0 ? config.leftX: config.rightX;
  
  float sum = 0;
  for(ushort x = 0; x < config.width; x++) {
    float3 sample = image.read(ushort2(startX + x, pid.y)).rgb;
    sum += length(sample);
  }
  sum /= config.width;
  mean.write(sum, pid);
}

float sobel(ushort x, ushort y, texture2d<float, access::read> tex) {
  if (y == 0) return 0;
  if (y + 1 == tex.get_height()) return 0;
  return tex.read(ushort2(x, y - 1)).r - tex.read(ushort2(x, y + 1)).r;
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
  
//  float  left = abs(sobel(0, yLeft, rowMean));
//  float right = abs(sobel(1, yRight, rowMean));
  float left  = rowMean.read(ushort2(0, yLeft )).r;
  float right = rowMean.read(ushort2(1, yRight)).r;
  
  // Find difference as a *proportion* of the larger value, not absolute
  // (0.1, 0.2) is bigger error than (0.8, 0.9)
  float diff = left - right;
  float numerator = diff * diff;
  
  float larger = left > right ? left: right;
  float denominator = larger * larger;
  
  delta.write(numerator/denominator, pid.yx); // y is image y axis, x is i
}

float2 distortion_correction(
  float2 coord,
  float aspectRatio,
  float lambda
) {
  // https://ieeexplore.ieee.org/abstract/document/6419070
  // d = distorted, u = corrected
  float2 xy_d = coord;
  xy_d.x *= aspectRatio;
  
  float2 xy_c = float2(0.5, 0.5);
  xy_c.x *= aspectRatio;
  
  float2 centered = xy_d - xy_c;
  
//  float r_d = length(centered);
//  float r_u = r_d/(1 + lambda * r_d * r_d);
//
//  float beta = (1 - sqrt(1 - 4 * lambda * r_u * r_u))/(2 * lambda * r_u * r_u);
//  float2 xy_d = beta *  centered + xy_c;
  
//  float2 xy_u = centered/(1 + lambda * r_d * r_d) + xy_c;
  
  // Only equation that really matters, it seems
  float2 xy_u = centered/(1 + lambda * dot(centered, centered)) + xy_c;
  
  xy_u.x /= aspectRatio;
  
  return xy_u;
}



fragment float4 fragment_straighten(
  const VertexOutPlonkTexture in [[stage_in]],
  constant StraightenFragmentParams &params [[buffer(0)]],
  const texture2d<float> originalTexture [[texture(0)]]
//  const texture2d<float> leftTexture [[texture(1)]],
//  const texture2d<float> rightTexture [[texture(2)]],
//  const texture2d<float> deltaAvgTexture [[texture(3)]]
) {
  constexpr sampler textureSampler(filter::linear);
  
  float2 pos = (params.straightenTransform * float3(in.texturePosition, 1)).xy;
  
  if (params.radialDistortionLambda != 0) {
    pos = distortion_correction(pos, params.aspectRatio, params.radialDistortionLambda);
  }
//
//  if (in.texturePosition.y < 0.5) {
//    pos.y *= 2;
//  } else {
//    pos.y = (pos.y * 2) - 1;
//  }
  float4 color = originalTexture.sample(textureSampler, pos);
  
  return color;
}

