#pragma once

#include <utility>

namespace ipc_serial {

// A fixed-distance EE leaf is directional even though the two-edge key is
// unordered. Canonicalize the stored leaf and its key together. In particular,
// EA_EB0 is the same physical function as EA0_EB after exchanging the edges.
// The upstream leaf implementations and their distance enum stay unchanged.
inline void canonicalize_edge_pair(int& edge_a, int& edge_b, int& distance_type)
{
    if (edge_a <= edge_b) {
        return;
    }
    std::swap(edge_a, edge_b);
    switch (distance_type) {
    case 1: distance_type = 2; break;
    case 2: distance_type = 1; break;
    case 4: distance_type = 6; break;
    case 5: distance_type = 7; break;
    case 6: distance_type = 4; break;
    case 7: distance_type = 5; break;
    default: break; // 00, 11, interior/interior, AUTO and unspecified are symmetric.
    }
}

} // namespace ipc_serial
