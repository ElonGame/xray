#include "xray.h"

Xray::Xray() {
  _ctx = optix::Context::create();
  _ctx->setRayTypeCount(2);
  _ctx->setEntryPointCount(1);
}

Xray::~Xray() {}

optix::Context Xray::getContext() const {
  return _ctx;
}