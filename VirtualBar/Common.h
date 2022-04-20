
#ifndef Common_h
#define Common_h

#import <simd/simd.h>

//typedef struct {
//  matrix_float4x4 modelMatrix;
//  matrix_float4x4 viewMatrix;
//  matrix_float4x4 projectionMatrix;
//  matrix_float3x3 normalMatrix;
//} Uniforms;

typedef enum {
  VertexBufferIndexExample = 10
} VertexBufferIndexes;

//typedef struct {
//  vector_float3 position;
//  vector_float3 color;
//  vector_float3 specularColor;
//  float intensity;
//  vector_float3 attenuation;
//  LightType type;
//  float coneAngle;
//  vector_float3 coneDirection;
//  float coneAttenuation;
//} Light;
//
//typedef struct {
//  uint lightCount;
//  vector_float3 cameraPosition;
//} FragmentUniforms;
//


typedef struct {
  float deadzone;
} LineOfSymmetryArgs;


typedef struct {
  float k1;
  float k2;
  float k3;
  float k4;
  float k5;
  float k6;

  float p1;
  float p2;
  
  simd_float3x2 intrinsicK;
} LensIntrinsics;


typedef struct {
  float thetaRange;
  float thetaStep;
  float rStep;
  vector_int2 imageSize;
  vector_int2 bufferSize;
} HoughConfig;

typedef struct {
  ushort leftX;
  ushort rightX;
  ushort width;
  short offsetMin;
  short offsetMax;
} StraightenParams;
#endif /* Common_h */
