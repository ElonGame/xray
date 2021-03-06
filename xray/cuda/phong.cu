/**
 * This is a Phong (simulated glossy reflection) material. It is wrapped by the
 * Phong class.
 */

#include <optix.h>
#include <optix_cuda.h>
#include <optix_world.h>
#include "core.cuh"
#include "math.cuh"

/** Cached scaling term in the Phong BSDF. */
rtDeclareVariable(float3, scaleBRDF, , );
/** Cached scaling term in the Phong PDF. */
rtDeclareVariable(float, scaleProb, , );
/** The Phong exponent of the material. */
rtDeclareVariable(float, exponent, , );
/** 1.0/exponent. */
rtDeclareVariable(float, invExponent, , );
/** The color reflected by the Phong material; similar to Lambert albedo. */
rtDeclareVariable(float3, color, , );

RT_CALLABLE_PROGRAM __inline__ float3 evalBSDFInternal(
  const float3& perfectReflect,
  const float3& outgoing
) {
  float cosAlpha = max(0.0f, dot(outgoing, perfectReflect));
  float cosAlphaPow = std::pow(cosAlpha, exponent);

  return scaleBRDF * cosAlphaPow;
}

RT_CALLABLE_PROGRAM __inline__ float evalPDFInternal(
  const float3& perfectReflect,
  const float3& outgoing
) {
  float cosAlpha = max(0.0f, dot(outgoing, perfectReflect));
  float cosAlphaPow = std::pow(cosAlpha, exponent);

  return scaleProb * cosAlphaPow;
}

RT_CALLABLE_PROGRAM float3 evalBSDFLocal(const float3& incoming, const float3& outgoing) {
   // See Lafortune & Willems <http://www.graphics.cornell.edu/~eric/Phong.html>.
  int sameHemis = math::localSameHemisphere(incoming, outgoing);
  float3 perfectReflect = make_float3(-incoming.x, -incoming.y, incoming.z);
  return sameHemis * evalBSDFInternal(perfectReflect, outgoing);
}

__device__ float evalPDFLocal(const float3& incoming, const float3& outgoing) {
  int sameHemis = math::localSameHemisphere(incoming, outgoing);
  float3 perfectReflect = make_float3(-incoming.x, -incoming.y, incoming.z);
  return sameHemis * evalPDFInternal(perfectReflect, outgoing);
}

__device__ void sampleLocal(
  curandState* rng,
  const float3& incoming,
  float3* outgoingOut,
  float3* bsdfOut,
  float* pdfOut
) {
  // See Lafortune & Willems <http://www.graphics.cornell.edu/~eric/Phong.html>
  // for a derivation of the sampling procedure and PDF.
  float3 perfectReflect = make_float3(-incoming.x, -incoming.y, incoming.z);
  float3 reflectTangent;
  float3 reflectBinormal;

  shared::coordSystem(perfectReflect, &reflectTangent, &reflectBinormal);

  /* The below procedure should produce unit vectors.
   *
   * Verify using this Mathematica code:
   * @code
   * R[a_] := (invExponent = 1/(20+1);
   *   cosTheta = RandomReal[{0, 1}]^invExponent;
   *   sinTheta = Sqrt[1 - cosTheta*cosTheta];
   *   phi = 2*Pi*RandomReal[{0, 1}];
   *   {Cos[phi]*sinTheta, cosTheta, Sin[phi]*sinTheta})
   *
   * LenR[a_] := Norm[R[a]]
   * 
   * ListPointPlot3D[Map[R, Range[1000]], BoxRatios -> Automatic]
   *
   * LenR /@ Range[1000]
   *
   * @endcode
   */
  float cosTheta = std::pow(math::nextFloat(rng, 0.0f, 1.0f), invExponent);
  float sinTheta = sqrtf(1.0f - cosTheta * cosTheta);
  float phi = XRAY_TWO_PI * math::nextFloat(rng, 0.0f, 1.0f);
  float3 local = make_float3(cosf(phi) * sinTheta, sinf(phi) * sinTheta, cosTheta);

  // Here, "local" being the space of the perfect reflection vector and
  // "world" being the space of the normal.
  *outgoingOut = math::localToWorld(
    local,
    reflectTangent,
    reflectBinormal,
    perfectReflect
  );
  *bsdfOut = evalBSDFInternal(perfectReflect, *outgoingOut);
  *pdfOut = evalPDFInternal(perfectReflect, *outgoingOut);
}
