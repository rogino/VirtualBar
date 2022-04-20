//
//  Straighten.metal
//  VirtualBar
//
//  Created by Rio Ogino on 19/04/22.
//

#include <metal_stdlib>
using namespace metal;
#import "./../Common.h"


  
constant float2 fullScreenVertices[6] = {
  float2(-1.0,  1.0),
  float2( 1.0, -1.0),
  float2(-1.0, -1.0),

  float2(-1.0,  1.0),
  float2( 1.0,  1.0),
  float2( 1.0, -1.0)
};

constant float2 fullScreenTextureCoordinates[6] = {
  float2(0.0, 0.0),
  float2(1.0, 1.0),
  float2(0.0, 1.0),

  float2(0.0, 0.0),
  float2(1.0, 0.0),
  float2(1.0, 1.0)
};

struct VertexOutImageMean {
  float4 position [[ position ]];
  float2 texturePosition;
};


kernel void copy_left_right_samples(
  constant StraightenParams& config [[buffer(0)]],
  texture2d<half, access::read>  image [[texture(0)]],
  texture2d<half, access::write> left  [[texture(1)]],
  texture2d<half, access::write> right [[texture(2)]],
                                    
  ushort2 pid [[thread_position_in_grid]]
) {
  ushort y = pid.x;
  bool isLeft = pid.y == 0;
  
  texture2d<half, access::write> output = isLeft ? left: right;
  for(ushort x = 0; x < config.width; x++) {
    output.write(
      image.read(ushort2(
        (isLeft ? config.leftX: config.rightX) + x,
        y
      )),
      ushort2(x, y)
    );
  }
}

kernel void straighten_left_right_delta_squared(
  constant StraightenParams& config     [[buffer(0)]],
  texture2d<float, access::write> delta    [[texture(0)]],
  texture2d<half,  access::read>  leftAvg  [[texture(1)]],
  texture2d<half,  access::read>  rightAvg [[texture(2)]],
                                    
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
  
  half4 left  =  leftAvg.read(ushort2(0, yLeft ));
  half4 right = rightAvg.read(ushort2(0, yRight));
  float4 diff = float4(left - right);
  diff.w = 0;
  float deltaSqured = dot(diff, diff) / 3; // 3 components so divide by 3 to cap to 1
  
  delta.write(deltaSqured, pid.yx); // y is image y axis, x is i
}


vertex VertexOutImageMean vertex_straighten(uint id [[vertex_id]]) {
  return {
    .position = float4(fullScreenVertices[id], 0, 1),
    // Mirror the image
    .texturePosition = float2(
      1 - fullScreenTextureCoordinates[id].x,
      fullScreenTextureCoordinates[id].y
    )
  };
}

fragment float4 fragment_straighten(
  const VertexOutImageMean in [[stage_in]],
  constant float3x3 &transform [[buffer(0)]],
  const texture2d<float> originalTexture [[texture(0)]],
  const texture2d<float> leftTexture [[texture(1)]],
  const texture2d<float> rightTexture [[texture(2)]],
  const texture2d<float> deltaAvgTexture [[texture(3)]]
) {
  constexpr sampler textureSampler;
  
  float2 pos = in.texturePosition;
  if (pos.y < 0.5) {
    pos = (transform * float3(in.texturePosition, 1)).xy;
    pos.y *= 2;
  } else {
    pos.y = (pos.y * 2) - 1;
  }
  float4 color = originalTexture.sample(textureSampler, pos);
  
  return color;
}
