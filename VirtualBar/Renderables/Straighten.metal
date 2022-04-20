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


kernel void kernel_hough_clear(
  constant HoughConfig& houghConfig [[buffer(0)]],
  device short* output [[buffer(1)]],
  uint2 id [[thread_position_in_grid]]
) {
  int index = id.y * houghConfig.bufferSize.x + id.x;
  output[index] = 0;
}

kernel void kernel_hough(
  constant HoughConfig& houghConfig [[buffer(0)]],
  texture2d<half, access::read> inputImage [[texture(0)]],
  device short* output [[buffer(1)]],
  uint2 id [[thread_position_in_grid]]
) {
//  constexpr sampler imageSampler(coord::pixel);
//  ushort4 sample = inputImage.sample(imageSampler, float2(id));
//  if (id.x < houghConfig.bufferSize.x && id.y < houghConfig.bufferSize.y) {
//    output[id.y * houghConfig.bufferSize.x + id.x] = 255;
//  }
//  return;
  
  
//  for (int i = 0; i < 10000; i++) {
//    output[i] = 255;
//  }
//  return;

  half4 sample = inputImage.read(id);
  if (sample.r <= 0) return;
  // https://stackoverflow.com/questions/59442566/optimize-metal-compute-shader-for-image-histogram
  for(float t = -houghConfig.thetaRange; t < houghConfig.thetaRange + 0.01; t += houghConfig.thetaStep) {
    // https://docs.opencv.org/3.4/d9/db0/tutorial_hough_lines.html
    float r = id.x * cos(t) + id.y + sin(t);
    int r_int = clamp(int(round(r)), 0, houghConfig.bufferSize.y);
    int t_int = clamp(int(round(t)), 0, houghConfig.bufferSize.x);
    uint position = houghConfig.bufferSize.x * r_int + t_int;
//    threadgroup_barrier(
    output[position] = 10;
    
//    output[position] += 1;
//    atomic_fetch_add_explicit(&(output[position]), 1, memory_order_relaxed);
//  https://stackoverflow.com/questions/57742654/non-atomic-parallel-reduction-with-metal
  }
}


vertex VertexOutImageMean vertex_straighten(
  uint id                   [[vertex_id]]
) {
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
  const texture2d<float> originalTexture [[texture(0)]],
  const texture2d<float> cannyTexture [[texture(1)]],
  const texture2d<ushort> houghTexture [[texture(2)]]
) {
  constexpr sampler textureSampler;
  constexpr sampler s2(coord::pixel);
//  return cannyTexture.sample(textureSampler, in.texturePosition);
  
  ushort4 houghSample = houghTexture.sample(s2, in.texturePosition);
//  houghSample = houghTexture.read(ushort2(20, 10));
  return float4(float3(houghSample.x), 1);
}