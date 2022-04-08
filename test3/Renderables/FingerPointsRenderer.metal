#include <metal_stdlib>
using namespace metal;
#import "./../Common.h"

float3 hsv2rgb(float3 in) {
  // https://stackoverflow.com/a/6930407
  float  p, q, t, ff;
  short  i;
  float3 out;
  
  float h = in.r;
  float s = in.g;
  float v = in.b;
  if(s <= 0.0) {
    out.r = v;
    out.g = v;
    out.b = v;
    return out;
  }
  if (h >= 1.0 || h < 0.0) h = 0.0;
  h /= 60.0;
  i = (short)h;
  ff = h - i;
  p = v * (1.0 - s);
  q = v * (1.0 - (s * ff));
  t = v * (1.0 - (s * (1.0 - ff)));
  
  switch(i) {
    case 0:
      out.r = v;
      out.g = t;
      out.b = p;
      break;
    case 1:
      out.r = q;
      out.g = v;
      out.b = p;
      break;
    case 2:
      out.r = p;
      out.g = v;
      out.b = t;
      break;
      
    case 3:
      out.r = p;
      out.g = q;
      out.b = v;
      break;
    case 4:
      out.r = t;
      out.g = p;
      out.b = v;
      break;
    case 5:
    default:
      out.r = v;
      out.g = p;
      out.b = q;
      break;
  }
  return out;
}


struct VertexOutFingerPoints {
  float4 position  [[position]];
  float  pointSize [[point_size]];
  float  confidence;
};

vertex VertexOutFingerPoints vertex_finger_points(
  constant float3 *vertices [[buffer(0)]],
             uint id        [[vertex_id]]
) {
  return {
    .position   = float4(vertices[id].x, vertices[id].y, 1, 1),
    .confidence = vertices[id].y,
    .pointSize = 20
  };
}

fragment float4 fragment_finger_points(
  const VertexOutFingerPoints in    [[stage_in]],
                       float2 point [[ point_coord]]
) {
  if (distance(point, float2(0.5, 0.5)) > 0.5) {
    discard_fragment();
  }
  // confidence of 0 is red, 1 is green. Narrator: It wasn't
  return float4(hsv2rgb(float3(in.confidence * 0.9/3.6, 1, 1)), 1);
}

