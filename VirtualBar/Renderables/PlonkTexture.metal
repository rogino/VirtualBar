//
//  PlonkTexture.metal
//  VirtualBar
//
//  Created by Rio Ogino on 20/04/22.
//

#include <metal_stdlib>
using namespace metal;
#import "./../Common.h"
#import "./PlonkTextureShared.metal"

vertex VertexOutPlonkTexture vertex_plonk_texture(uint id [[vertex_id]]) {
  return {
    .position = float4(fullScreenVertices[id], 0, 1),
    .texturePosition = float2(
      // Mirror the image? 1 - coord[id].y
      fullScreenTextureCoordinates[id].x,
      fullScreenTextureCoordinates[id].y
    )
  };
}


fragment float4 fragment_plonk_texture(
  const VertexOutPlonkTexture in [[stage_in]],
  const texture2d<float> texture [[texture(0)]]
) {
  constexpr sampler s;
  if (is_null_texture(texture)) {
    return float4(0.4, 0.2, 0.7, 1.0);
  }
  return texture.sample(s, in.texturePosition);
}


