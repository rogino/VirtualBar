#include <metal_stdlib>
using namespace metal;
#import "Common.h"

struct VertexInMinimalIndexed {
  float4 position [[ attribute(0) ]];
};

vertex float4 vertex_minimal_indexed(
  const VertexInMinimalIndexed vertex_in [[ stage_in ]]) {
  return vertex_in.position;
}

fragment float4 fragment_minimal_red() {
  return float4(1, 0, 0, 1);
}





struct VertexInPosColor {
  float3 position [[ attribute(0) ]];
  float4 color    [[ attribute(1) ]];
};

struct VertexOutPosColor {
  float4 position [[ position ]];
  float4 color;
};

vertex VertexOutPosColor vertex_minimal_unindexed(
  constant VertexInPosColor *vertices [[buffer(0)]],
  uint id [[vertex_id]]
) {
  return {
    .position = float4(vertices[id].position, 1),
    .color = vertices[id].color
  };
}

fragment float4 fragment_minimal_pos_color(
  const VertexOutPosColor in [[ stage_in ]]
) {
  return in.color;
};


//struct VertexOut {
//  float4 position [[position]];
//  float point_size [[point_size]];
//};
//
//vertex VertexOut vertex_main(constant float3 *vertices [[buffer(0)]],
//                             uint id [[vertex_id]])
//{
//  VertexOut vertex_out {
//    .position = float4(vertices[id], 1),
//    .point_size = 20.0
//  };
//  return vertex_out;
//}
//
//fragment float4 fragment_main(constant float4 &color [[buffer(0)]])
//{
//  return color;
//}
