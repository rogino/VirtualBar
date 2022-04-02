#include <metal_stdlib>
using namespace metal;
#import "./../Common.h"

struct VertexInTriangle {
  float3 position [[ attribute(0) ]];
  float4 color    [[ attribute(1) ]];
};

struct VertexOutTriangle {
  float4 position [[ position ]];
  float4 color;
};

vertex VertexOutTriangle vertex_triangle(
  constant VertexInTriangle *vertices [[buffer(0)]],
  constant simd_float4x4 &transform [[buffer(1)]],
  uint id [[vertex_id]]
) {
  float4 position = float4(vertices[id].position, 1);
  return {
    .position = transform * position,
    .color = vertices[id].color
  };
}

fragment float4 fragment_triangle(
  const VertexOutTriangle in [[ stage_in ]]
) {
  return in.color;
};



