#pragma once
#include <optix.h>
#include <optix_world.h>
#include "shared.cuh"

#ifdef __CUDACC__
#include <optix_cuda.h>
#include "math.cuh"
#endif

#ifdef __CUDACC__
rtDeclareVariable(rtObject, sceneRoot, , );

__device__ void evalWorld(
  const NormalRayData& data,
  const optix::float3& isectNormalObj,
  const optix::float3& incomingWorld,
  const optix::float3& outgoingWorld,
  optix::float3* bsdfOut,
  float* bsdfPdfOut
) {}

__device__ void sampleWorld(
  const NormalRayData& data,
  const optix::float3& isectNormalObj,
  const optix::float3& incomingWorld,
  const optix::float3* outgoingWorld,
  optix::float3* bsdfOut,
  float* bsdfPdfOut
) {}
#endif

struct Light {
  optix::float3 boundsOrigin;
  float boundsRadius;
  optix::float3 color;
  int id;

  __host__ static Light* make(optix::float3 c) {
    Light* l = new Light();
    l->color = c;
    l->id = -1;
    l->boundsOrigin = optix::make_float3(0);
    l->boundsRadius = 0.0f;
    return l;
  }

  __host__ static Light* make() {
    Light* l = new Light();
    l->color = optix::make_float3(0);
    l->id = -1;
    l->boundsOrigin = optix::make_float3(0);
    l->boundsRadius = 0.0f;
    return l;
  }
  
#ifdef __CUDACC__
  __device__ optix::float3 emit(const optix::float3& dir, const optix::float3& n) const {
    // Only emit on the normal-facing side of objects, e.g. on the outside of a
    // sphere or on the normal side of a disc.
    if (dot(dir, n) > XRAY_EXTREMELY_SMALL) {
      return optix::make_float3(0);
    }

    return color;
  }

  __device__ optix::float3 directIlluminateByLightPDF(
    const NormalRayData& data,
    const optix::float3& isectNormalObj,
    const optix::float3& isectPos
  ) const {
    // Sample random from light PDF.
    optix::float3 outgoingWorld;
    optix::float3 lightColor;
    float lightPdf;
    sampleLight(
      data.rng,
      isectPos,
      &outgoingWorld,
      &lightColor,
      &lightPdf
    );

    if (lightPdf > 0.0f && !math::isVectorExactlyZero(lightColor)) {
      // Evaluate material BSDF and PDF as well.
      optix::float3 bsdf;
      float bsdfPdf;
      evalWorld(
        data,
        isectNormalObj,
        -data.direction,
        outgoingWorld,
        &bsdf,
        &bsdfPdf
      );

      if (bsdfPdf > 0.0f && !math::isVectorExactlyZero(bsdf)) {
        float lightWeight = math::powerHeuristic(1, lightPdf, 1, bsdfPdf);
        return (bsdf * lightColor)
          * fabsf(dot(isectNormalObj, outgoingWorld))
          * lightWeight / lightPdf;
      }
    }

    return optix::make_float3(0);
  }

  __device__ optix::float3 directIlluminateByMatPDF(
    const NormalRayData& data,
    const optix::float3& isectNormalObj,
    const optix::float3& isectPos
  ) const {
    // Sample random from BSDF PDF.
    optix::float3 outgoingWorld;
    optix::float3 bsdf;
    float bsdfPdf;
    sampleWorld(
      data,
      isectNormalObj,
      -data.direction,
      &outgoingWorld,
      &bsdf,
      &bsdfPdf
    );

    if (bsdfPdf > 0.0f && !math::isVectorExactlyZero(bsdf)) {
      // Evaluate light PDF as well.
      optix::float3 lightColor;
      float lightPdf;
      evalLight(
        isectPos,
        outgoingWorld,
        &lightColor,
        &lightPdf
      );

      if (lightPdf > 0.0f && !math::isVectorExactlyZero(lightColor)) {
        float bsdfWeight = math::powerHeuristic(1, bsdfPdf, 1, lightPdf);
        return bsdf * lightColor
          * fabsf(dot(isectNormalObj, outgoingWorld))
          * bsdfWeight / bsdfPdf;
      }
    }

    return optix::make_float3(0);
  }

  __device__ void evalLight(
    const optix::float3& point,
    const optix::float3& dirToLight,
    optix::float3* colorOut,
    float* pdfOut
  ) const {
    float pdf;
    optix::float3 emittedColor;

    if (math::sphereContains(boundsOrigin, boundsRadius, point)) {
      // We're inside the bounding sphere, so sample sphere uniformly.
      pdf = math::uniformSampleSpherePDF();
    } else {
      // We're outside the bounding sphere, so sample by solid angle.
      optix::float3 dirToLightOrigin = boundsOrigin - point;
      float theta = asinf(boundsRadius / length(dirToLightOrigin));

      optix::float3 normal = normalize(dirToLightOrigin);
      optix::float3 tangent;
      optix::float3 binormal;
      shared::coordSystem(normal, &tangent, &binormal);

      optix::float3 dirToLightLocal =
        math::worldToLocal(dirToLight, tangent, binormal, normal);
      pdf = math::uniformSampleConePDF(theta, dirToLightLocal);
    }

    optix::Ray pointToLight = optix::make_Ray(point + dirToLight * XRAY_VERY_SMALL, dirToLight, RAY_TYPE_NORMAL, XRAY_VERY_SMALL, RT_DEFAULT_MAX);
    NormalRayData checkData = NormalRayData::make(point, dirToLight, nullptr); // nullptr OK because no material evaluation.
    checkData.flags |= RAY_SKIP_MATERIAL_COMPUTATION;
    rtTrace(sceneRoot, pointToLight, checkData);
    if (checkData.lastHitId != id) {
      // No emission if the ray doesn't hit the light or is occluded
      // (e.g. sampling doesn't exactly correspond with light).
      emittedColor = optix::make_float3(0);
    } else {
      // Emits color if the ray does hit the light.
      emittedColor = emit(dirToLight, checkData.hitNormal);
    }

    *colorOut = emittedColor;
    *pdfOut = pdf;
  }

  __device__ void sampleLight(
    curandState* rng,
    const optix::float3& point,
    optix::float3* dirToLightOut,
    optix::float3* colorOut,
    float* pdfOut
  ) const {
    optix::float3 dirToLight;
    float pdf;
    optix::float3 emittedColor;

     if (math::sphereContains(boundsOrigin, boundsRadius, point)) {
      // We're inside the bounding sphere, so sample sphere uniformly.
      dirToLight = math::uniformSampleSphere(rng);
      pdf = math::uniformSampleSpherePDF();
    } else {
      // We're outside the bounding sphere, so sample by solid angle.
      optix::float3 dirToLightOrigin = boundsOrigin - point;
      float theta = asinf(boundsRadius / length(dirToLightOrigin));

      optix::float3 normal = normalize(dirToLightOrigin);
      optix::float3 tangent;
      optix::float3 binormal;
      shared::coordSystem(normal, &tangent, &binormal);

      dirToLight = math::localToWorld(
        math::uniformSampleCone(rng, theta),
        tangent,
        binormal,
        normal
      );
      pdf = math::uniformSampleConePDF(theta);
    }
     
    optix::Ray pointToLight = optix::make_Ray(point + dirToLight * XRAY_VERY_SMALL, dirToLight, RAY_TYPE_NORMAL, XRAY_VERY_SMALL, RT_DEFAULT_MAX);
    NormalRayData checkData = NormalRayData::make(point, dirToLight, nullptr);
    checkData.flags |= RAY_SKIP_MATERIAL_COMPUTATION;
    rtTrace(sceneRoot, pointToLight, checkData);
    if (checkData.lastHitId != id) {
      // No emission if the ray doesn't hit the light or is occluded
      // (e.g. sampling doesn't exactly correspond with light).
      emittedColor = optix::make_float3(0);
    } else {
      // Emits color if the ray does hit the light.
      emittedColor = emit(dirToLight, checkData.hitNormal);
    }

    *dirToLightOut = dirToLight;
    *colorOut = emittedColor;
    *pdfOut = pdf;
  }

  __device__ optix::float3 directIlluminate(
    const NormalRayData& data,
    const optix::float3& isectNormalObj,
    const optix::float3& isectPos
  ) const {
    optix::float3 Ld = optix::make_float3(0);

    Ld +=
      directIlluminateByLightPDF(data, isectNormalObj, isectPos);
    Ld +=
      directIlluminateByMatPDF(data, isectNormalObj, isectPos);

    return Ld;
  }
#endif
};
