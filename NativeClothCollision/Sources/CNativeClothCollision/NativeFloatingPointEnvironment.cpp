#include "NativeFloatingPointEnvironment.h"
#include <cfenv>

extern "C" int ncc_floating_point_rounding_is_nearest(void)
{
    return std::fegetround() == FE_TONEAREST ? 1 : 0;
}
