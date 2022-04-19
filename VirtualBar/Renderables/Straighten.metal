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


kernel void kernel_hough(
  constant HoughConfig& houghConfig [[buffer(0)]],
  texture2d<half, access::read> inputImage [[texture(0)]],
  device short* output [[buffer(1)]],
  uint2 id [[thread_position_in_grid]]
) {
  // https://docs.opencv.org/3.4/d9/db0/tutorial_hough_lines.html
  // One thread per r-theta pair
  int index = id.y * houghConfig.bufferSize.x + id.x;
  ushort2 coord = ushort2(id.x % houghConfig.imageSize.x, id.y % houghConfig.imageSize.y);
//  output[index] = inputImage.read(coord).r;
//
//  return;
  float r = id.y * houghConfig.rStep;
  float t = (id.x - houghConfig.bufferSize.x / 2) * houghConfig.thetaStep; // theta
  
  // TODO: generate equation to find min/max x such that y remains within [0, image.size.y)
  float cosT = cos(t);
  float sinT = sin(t);
  
  
  
  ushort sum = 0;
  for(int x = 0; x < houghConfig.imageSize.x; x++) {
    float y_frac = -x/tan(t) + r/sin(t);
    int y = 0;
    if (fract(y_frac) < 0.2) {
      y = int(y_frac);
    } else if (fract(y_frac) > 0.8) {
      y = int(y_frac + 1);
    } else {
      return;
    }
    
    if (y < 0 || y > houghConfig.bufferSize.y) {
      return;
    }
    
    sum += inputImage.read(ushort2(x, y)).x > 0;
  }
  output[index] = sum;
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
//  constexpr sampler s2(coord::pixel);
//  return cannyTexture.sample(textureSampler, in.texturePosition);
  ushort4 houghSample = houghTexture.sample(textureSampler, in.texturePosition);
  
//  ushort4 houghSample = houghTexture.sample(s2, float2(10, 10));
//  houghSample = houghTexture.read(ushort2(20, 10));
  return float4(float3(houghSample.x) / 30, 1);
}
