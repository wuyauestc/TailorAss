# Moving cloth self-contact path guard

`NativeClothCollision.SelfContactGuard` checks a linear motion of the complete
triangle surface. Both sides of every vertex/face and edge/edge query move.
It supplies a conservative time bound; it supplies no cloth force and does not
establish drape convergence.

## Required initial-state proof

`Report.requiresIntersectionFreeInitialState` is always `true`. The caller must
first establish that the complete initial surface has no proper or coplanar
intersections, then preserve the last state accepted by every required guard.
The positive-clearance native initializer provides that bootstrap for its
successfully prepared complete source. Event CCD alone is insufficient: a static
edge can already pierce a face interior while every vertex/face and edge/edge
distance is positive. The test suite retains this counterexample.

The independent vertex IDs remain unchanged. VF excludes only a vertex that is
one of the face's three IDs. EE excludes only two edges sharing an endpoint ID.
A shared vertex does not remove a whole triangle pair. Different IDs on a
planned seam receive no contact exemption.

## Complete and atomic result

The prepared topology contains every source face and unique indexed edge. Each
query first certifies all their geometry domains for the entire requested
interval, including isolated faces with no broadphase candidates. A swept face
BVH then constructs and deduplicates the complete supported VF/EE candidates.
The existing Tight-Inclusion primitive performs the two-sided moving query.

Before a primitive enters the canonical query set, its own swept bounds are
tested: point against face for VF, two swept edges for EE. Each bound contains
every endpoint over the entire interval and therefore contains every convex
point of that primitive. One side is expanded by an upward-rounded `dmin+tol`,
with outward-rounded bound coordinates. Disjoint expanded boxes prove separation
and require no native CCD query. This does not bypass any face/edge domain
certificate. The statistics count pruned primitive **visits before deduplication**.

The default minimum separation is zero, distance tolerance is `1e-8 m`, and the
safety factor is `0.9`. A limited result is returned only after all candidates
finish. Invalid input, possible initial contact, uncertain geometry, cancellation
or any exhausted budget returns zero safe time. A hit found before a later
failure cannot authorize a partial result. Input positions are never changed.

The limits cap source vertices at 20,000, faces at 40,000, BVH nodes at 80,000,
build work at 10 million, BVH visits at 20 million, triangle pairs at 500,000,
unique primitive queries at 1 million, certificate nodes at 10 million, and
estimated working memory at 256 MiB. Callers may reduce these limits, not expand
them. A conservative edge-domain certificate can refuse large regular rotations;
an uncertain result requires a smaller independently checked candidate.

## Frozen validation

The implementation adds only `SelfContactGuard.swift`,
`SelfMotionCertificates.cpp`, and `CSelfMotionCertificates.h`. Existing body CCD,
the old primitive wrapper, and vendor sources are unchanged.

- Sixteen standalone analytic/refusal controls passed, including shared-one-ID
  VF, shared-edge opposite VF, EE-only crossing, both-side motion, mid-interval
  collapse, initial independent contact, budgets, and late cancellation.
- All 211 complete positive-clearance source initializations passed static
  self-path queries, bound to their exact source/geometry/topology and independent
  bootstrap proofs. This is an initialization check, not cloth simulation.
- Exact accepted state 236 to the body-blocked state-237 trial passed the complete
  self path query: 3,472 triangle and 5,468 edge certificates, 31,054 VF and 46,296
  EE queries before the primitive-bounds optimization. The optimized complete
  query needs 22 VF and 168 EE native calls with the same domain certificates and
  20,040 face pairs. The trial remains **unaccepted overall** because its body
  condition is separate. Independent initial/final scans found zero proper and
  positive-area coplanar pairs for these exact fixtures.
- The new nine XCTest methods passed in an independent Release package snapshot
  with warnings as errors (45 tests: the previous 36 plus these nine). The
  metadata owner runs the combined package and both iOS final-link checks after
  adding the new header to its explicit module map.

The complete development evidence is frozen under
`/private/tmp/TailorAssSelfCCDPrototype` and the optimized control under
`/private/tmp/TailorAssSelfCCDAABBPrune`; the long-term package fixtures preserve
the exact real poses and their bootstrap/source hashes. The optimized Mac
measurement was about 12 ms for that real path and 3.05 seconds for all 211
static controls; these timings do not predict iPhone performance.
