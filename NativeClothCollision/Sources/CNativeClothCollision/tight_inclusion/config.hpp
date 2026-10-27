#pragma once
// Generated configuration for the pinned upstream config.hpp.in (not an algorithm modification).
#define TIGHT_INCLUSION_NAME "TightInclusion"
#define TIGHT_INCLUSION_VER "1.0.4"
#define TIGHT_INCLUSION_VER_MAJOR "1"
#define TIGHT_INCLUSION_VER_MINOR "0"
#define TIGHT_INCLUSION_VER_PATCH "4"
#define TIGHT_INCLUSION_WITH_DOUBLE_PRECISION
// Rational, timers, float conversion, and upstream's early queue-exit switch remain OFF.


// Numerical preconditions for the upstream floating-point error filters.
#if defined(__FAST_MATH__)
#error "Tight-Inclusion must not be compiled with fast-math"
#endif
#if defined(__clang__)
#pragma clang fp contract(off)
#endif
