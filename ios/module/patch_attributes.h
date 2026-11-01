#pragma once
#include "recomp.h"
// Strong patch definitions must win over weak generated originals regardless
// of object ordering. This header is included only by the patch translation.
#if defined(__clang__)
#undef RECOMP_FUNC
#define RECOMP_FUNC __attribute__((noinline))
#endif
