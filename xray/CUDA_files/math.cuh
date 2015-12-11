#pragma once
#define _USE_MATH_DEFINES
#include <optix.h>
#include <limits>
#include <cmath>

/** A very small nonzero value. */
#define XRAY_VERY_SMALL 0.0001f
#define XRAY_PI_4 0.7853981633974483

namespace math {
  using namespace optix;

  __host__ __device__ __inline__ bool isPositive(float x) {
    return x > std::numeric_limits<float>::epsilon();
  }

  __host__ __device__ __inline__ float3 at(const optix::Ray& r, float t) {
    return r.origin + t * r.direction;
  }

  /**
   * Generates an orthonormal coordinate basis. The first vector must be given,
   * and the other two orthogonal vectors will be generated from it.
   * Taken from page 63 of Pharr & Humphreys' Physically-Based Rendering.
   *
   * @param v1 [in]  the first unit (normalized) vector of the basis
   * @param v2 [out] the second unit vector, generated from the first
   * @param v3 [out] the third unit vector, generated from the first
   */
  __host__ __device__ __inline__
  void coordSystem(const float3& v1, float3* v2, float3* v3) {
    if (fabsf(v1.x) > fabsf(v1.y)) {
      float invLen = 1.0f / sqrtf(v1.x * v1.x + v1.z * v1.z);
      *v2 = make_float3(-v1.z * invLen, 0.0f, v1.x * invLen);
    } else {
      float invLen = 1.0f / sqrtf(v1.y * v1.y + v1.z * v1.z);
      *v2 = make_float3(0.0f, v1.z * invLen, -v1.y * invLen);
    }
    *v3 = cross(v1, *v2);
  }

  __host__ __device__ __inline__ float3 pointXform(float3 v, Matrix4x4 xform) {
    float4 world = xform * make_float4(v.x, v.y, v.z, 1);
    return make_float3(world.x / world.w, world.y / world.w, world.z / world.w);
  }

  __host__ __device__ __inline__ float3 vectorXform(float3 v, Matrix4x4 xform) {
    float4 world = xform * make_float4(v.x, v.y, v.z, 0);
    return make_float3(world.x, world.y, world.z);
  }

  __host__ __device__ __inline__ float saturate(float x) {
#ifdef __CUDACC__
    return __saturatef(x);
#else 
    return x < 0 ? 0 : (x > 1 ? 1 : x);
#endif
  }

  __host__ __device__ __inline__ optix::uchar4 colorToBgra(const optix::float3& c) {
    return optix::make_uchar4(
      static_cast<unsigned char>(saturate(c.z) * 255.99f), /* B */
      static_cast<unsigned char>(saturate(c.y) * 255.99f), /* G */
      static_cast<unsigned char>(saturate(c.x) * 255.99f), /* R */
      255u /* A */
    );                                                 
  }

  __host__ __device__ __inline__ optix::Matrix4x4 rotationThenTranslation(float angle, optix::float3 axis, optix::float3 offset) {
    return optix::Matrix4x4::translate(offset) * optix::Matrix4x4::rotate(angle, axis);
  }

}