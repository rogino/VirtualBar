//
//  PlonkTextureShared.metal
//  VirtualBar
//
//  Created by Rio Ogino on 20/04/22.
//

#include <metal_stdlib>
using namespace metal;

#ifndef PlonkTexture_metal
#define PlonkTexture_metal


struct VertexOutPlonkTexture {
  float4 position [[ position ]];
  float2 texturePosition;
};
  
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

#endif
