# Continuous feature distance-separation certificate

FeatureSeparationCertificate proves only that one closed VF or EE pair stays at Euclidean distance strictly greater than the requested floor over the entire linear motion t∈[0,1]. It does not certify primitive nondegeneracy, body exterior, initial self-intersection freedom, sewing exclusions, source validity or permission to advance a garment.

~~~swift
var limits = FeatureSeparationCertificate.Limits()
let proof = FeatureSeparationCertificate.certify(
    kind: .vertexFace,             // or .edgeEdge
    start: fourOriginalPoints,
    end: fourOriginalPointsAtEnd,
    minimumSeparation: 0.0005,
    limits: limits,
    isCancelled: { token.cancelled })

if proof.status == .separated {
    // Distance only. Retain the original independent whole-domain proof,
    // every other feature query, global budgets and exterior/bootstrap rules.
}
~~~

The immutable public values are Sendable. The cancellation callback is synchronous, nonescaping, never retained and runs on the caller's current thread. It deliberately accepts the same ordinary closure type as the existing native/body guard; no unchecked callback box or cross-task transfer is required.

VF order is point, triangle0, triangle1, triangle2. EE order is edgeA0, edgeA1, edgeB0, edgeB1. Both endpoints contain exactly four SIMD3<Double> values. The SHA binds kind, the original floor and the exact binary64 start/end coordinates. This component never changes the source, endpoints, native minimum separation, native tolerance or native result.

## Proof

For a fixed time interval [l,r], choose any finite nonzero direction n. The numerical closest-point routine first proposes a midpoint direction, then directions from the two interval endpoints. Each proposal must independently prove the same whole interval; an endpoint proposal is not an endpoint-distance test. Their distances and feature classifications are not trusted. If all three VF face vertices are exactly unchanged from start to end, three additional axes come from the cross product of the point trajectory with each static face edge, trying both signs. Zero or nonfinite axes cannot certify anything. These axes can find a supporting plane at an interior trajectory time against a static edge; each still must prove the same whole interval. No corresponding assumption is made for moving faces.

For every A/B vertex pair, compute an outward interval enclosing

n · (a_i(t) − b_j(t))

at both interval endpoints. Each projection is linear in t. Its minimum over the whole interval therefore occurs at an endpoint. If the smallest lower bound L satisfies

L > floor × U

where U is an outward upper bound on |n| and the right product is also rounded upward, every pair projection is strictly separated. Every pair of points on the two closed convex features is a convex combination of these vertex differences. Cauchy–Schwarz then proves their Euclidean distance is strictly greater than floor for every time in the interval.

This covers face interiors, edges, endpoints and time interiors. It is not an endpoint-distance test or dense sampling. Relative vertex differences retain common-motion cancellation. The midpoint direction is rescaled by its largest absolute component; the resulting binary64 vector is simply another exact direction for the interval proof.

If all applicable fixed directions fail, a second proof uses the actual moving feature plane on the same interval. For VF let u=b−a, v=c−a, w=p−a. For EE let u=b−a, v=d−c, w=a−c. Each is linear in time. The normal n=u×v is quadratic and g=w·n is cubic. Outward binary64 interval arithmetic encloses their Bernstein controls. All four g controls must have the same strict sign. Their absolute lower bound must exceed the original floor times an outward upper bound on |n| over the entire interval. Since a face lies in its plane and two edges lie in their respective parallel planes, this proves separation of the complete closed features. It also applies at positive floors; it is not a zero-floor signed-volume exception.

With endpoint controls u0,u1,v0,v1,w0,w1 in the current local interval, the normal controls are n0=u0×v0, n1=(u0×v1+u1×v0)/2, n2=u1×v1. Projection controls are w0·n0, (2w0·n1+w1·n0)/3, (w0·n2+2w1·n1)/3, w1·n2. The factor 1/3 has its own outward enclosure. Convex-hull bounds enclose the polynomial on the entire interval. No time sample is treated as a proof of intermediate safety.

An interval unproved by the fixed and moving proofs is bisected at its exact dyadic midpoint. Only a finite partition covering all [0,1] leaves can return separated. Any contact, weak direction, arithmetic ambiguity, depth limit, node limit or cancellation remains unproved. notCertified means the proof failed, not that a collision was numerically located. Work per node is at most nine fixed direction proposals followed by one bounded polynomial proof; the original depth/node limits and physical thresholds are unchanged.

The optional minimumCertifiedDistanceLowerBoundMeters describes certified leaves only. A failed motion can have a positive bound on a clear prefix and still collide later. Never use that number to authorize the full motion; only status separated indicates complete coverage.

## Domain and native integration boundary

A distance certificate is not a triangle/edge noncollapse certificate. The test with a distant point and a triangle that collapses at t=.5 intentionally obtains a distance certificate while the unchanged native kernel returns uncertainGeometry. That native domain failure remains a failure.

The component has no domain=true parameter, override flag or permitsWholeCandidate property. Its report explicitly declares requiresIndependentPrimitiveDomainCertificate. A caller integrating a fallback must keep all original domain/feature/adjacency/global-budget statistics and check every remaining feature. Certifying one witness never clears a whole body query.

In the fixed native wrapper, conservativeHit/detail.none and uncertain/detail.precisionOrBudget occur only after its original whole-domain checks. The reviewed body guard may use a successful independent proof for these exact result classes. Arbitrary uncertainGeometry, unsupported rounding, internalFailure, invalid input, cancellation or unknown domain must not be converted into safe motion. The wrapper's own raw CCD calls and original results remain unchanged.

The physical Euclidean floor remains exactly the requested value. Dividing it by √3 to counter an L∞ conservative box would miss real sub-floor distances and is forbidden. Native spatial tolerance is not reinterpreted as a temporal error.

## Bounds and arithmetic

Only nearest-rounding IEEE binary64 is supported; the existing read-only C bridge is checked before work, at each node and after the final callback. The helper never changes rounding mode.

Default limits are depth12, 8191 visited nodes, 1MiB estimated working-array capacity and no retained leaf trace. Explicit maxima are depth16 and 65535 nodes. The DFS pending stack is bounded by depth+2. Enabling leaf traces retains the old bounded fixed-leaf reserve; moving-normal traces allocate lazily with explicit capacity and payload charges before append. Constant working scratch is also charged. The estimate includes capacity headroom; it is not a process-RSS claim. Invalid inputs, exhausted node/trace memory and callback cancellation cannot return separated.

The existing LeafCertificate continues to describe only a fixed direction. MovingNormalCertificate separately records the time interval, VF/EE kind, strict projection sign, all three interval normal controls, all four interval projection controls, absolute projection lower bound, normal-norm upper bound, required floor-product upper bound and diagnostic distance lower bound. Report counters distinguish fixed and moving certified intervals and moving-proof attempts. The two arrays together form the certified time partition. Older JSON reports without these added fields still decode with empty moving traces and zero counters; an old fixed direction is never relabeled as a moving normal.

Coordinates have the same finite ±1e6m envelope as the original C primitive. The helper accepts floors 0…1m; this mathematical domain does not supersede the original native scale/option checks.

## Regressions

~~~sh
python3 NativeClothCollision/Scripts/run-feature-separation-checks.py
~~~

This standalone runner covers the earlier fixed-direction stage with primitive/body-integration Release XCTest functions and an independent Python Fraction oracle. The full current package regression, including correlated motion, uses `Scripts/run-checks.py`. It snapshots and verifies all owned and vendor bytes, exports fixed/moving/full-query traces, runs the complete Mac Release suite and independent exact Fraction audits, and compiles/links the complete Swift module and real clients for arm64 iOS17 and x86_64 iOS17 Simulator.

Controls include:

- Original Circle step247 point64 versus body face[10834,10815,10835], exact binary64 coordinates and original raw conservative hits.
- Those two whole paths certify lower bounds approximately .739720186239653mm and .512051460141026mm at the original .5mm floor, each with one node.
- A new real Circle118 VF path has an exact minimum only about 2.55pm above .5mm. The former midpoint-only helper exhausted depth12; its true minimum is at interior time t≈.658445927 against body edge BC. A static trajectory/edge axis now proves the same complete path without increasing any threshold or work cap. All reported bounds and its exact convex-QP minimum are independently recomputed as Fractions.
- A real Shirt85 EE path retains the raw native post-domain precisionOrBudget result. Its independent whole-path certificate and full-triangle body integration retain the exact .5mm floor.
- Independent exact-rational convex-QP recomputation of the fixed-triangle path minimum, including all active sets.
- Every diagnostic leaf's projection lower bound, norm/product upper bounds and complete time partition checked with exact Fractions.
- VF/EE paths whose endpoints are clear but which collide in the middle; exact-floor and under-floor rejection.
- A corner miss requiring finite subdivision, closed vertex/edge closest cases, moving faces, common translation and conservative L∞ cases.
- Domain-collapse separation that cannot replace the native domain refusal.
- Deterministic cancellation, input/count limits, depth/node/memory exhaustion, unchanged inputs, exact motion hashing and unsupported rounding.

Fixtures are minimal generated numeric regression data, with raw trace SHA/provenance and exact coordinate bit patterns. No AGPL measurement source or extra runtime dependency is included. These tests establish a separation primitive, not a complete garment, physics solver or body-fitting result.

## Body-guard integration regressions

The integration tests retain each original limited/initial-hit point motion and the same static body face. Two other cloth vertices are lifted along the positive body-plane normal to form a complete, nondegenerate moving triangle. This preserves strict whole-triangle plane separation instead of substituting an isolated vertex for a body query. An independent exact Fraction calculation checks all 3×3 cloth/body vertex differences at both time endpoints; it proves the full continuous convex triangles remain above the unchanged .5mm Euclidean floor.

For each original path, the raw native VF still returns conservativeHit/detail.none. The complete body query evaluates all 15 required unique features/native queries, records its independent certificate attempt, and returns clear only after all features finish. No native status is rewritten by the primitive helper.

Additional integration controls keep a genuine middle-of-path crossing limited; keep native uncertainGeometry for a cloth face that collapses despite a valid distance-only proof; exhaust a zero and a one-node whole-query budget across multiple features; cancel after a recorded certificate attempt with completedAllFeatures=false; and reject unsupported rounding even when broadphase would produce no candidates. Original body and cloth arrays remain unchanged. These controls cover query integration and do not validate garment equilibrium, self-contact or an entire avatar.

## Correlated-motion regression evidence

The sealed `/private/tmp/TailorAssCorrelatedFSCNativeFirst` proof executed all 111 Mac tests together, including the previous 105 and six new functions. Exact Fraction audits independently recomputed 15 motions and 57 moving-normal leaves, including every Bernstein interval enclosure, strict sign, norm/product bound and full fixed/moving time partition. Crossing and tangent controls remain notCertified, with exact rational closed-feature contacts. Time/edge reversal, translation, near parallelism, positive floors and SI scale changes are covered alongside cancellation, rounding, memory/node/depth limits and old report decoding.

The original Circle failed physical step690 provided an actual EE motion for vertices [60,61,1597,1598]. Its old native result remains uncertain/precisionOrBudget, and the old fixed-direction certificate exhausted its unchanged depth limit. Exact rational arithmetic proves the actual complete motion stays separated at floor0. The new production moving proof certifies it without increasing depth, nodes or reducing any floor. The complete saved inner motion still checks 626 features; the complete saved physical outer motion now checks all 1552 features and original domain certificates, including those after the formerly blocking witness. Both return clear. These are direct replays of saved coordinates, not a new Newton solve or a completed step690, garment equilibrium or final output.

The same frozen Swift source also compiled and linked as a complete module with real Swift clients for both iOS targets, reusing the byte-identical prior C++ archives. Platform/minimum-OS and linked symbols were checked. This is a compile/link result; no device runtime result is claimed. The new helper changes no C++/vendor algorithm, mesh, material, source/rest geometry, force, Hessian or sewing mask.

## Filtered exact expansion proof

The existing fixed and outward-interval moving proofs still run first on every visited interval. Only if both fail, a third filter computes the same polynomial more accurately. This does not change any floor, spatial tolerance, feature enumeration, domain certificate, default depth12/node8191 limit or continuous trajectory.

The new actual Native111 Circle690 witness again uses EE[60,61,1597,1598], with different saved endpoints from the earlier regression. Its exact rational whole-time distance is strictly positive, but very small: the independent depth12 proof gives a lower bound of about 3.44487e−16m. The ordinary moving interval calculation cannot certify this case. The helper must neither infer collision nor grant safety from that numerical failure.

The third filter uses bounded floating-point expansions of the exact stored binary64 coordinates. TwoSum preserves sums and FMA TwoProduct preserves products. Before every nonzero product, the least set significand-bit exponents must sum to at least −1074; otherwise the product's exact low bits could underflow the binary64 lattice and the expansion is explicitly unavailable. Finite intermediates are also required. This rejects cases where a rounded FMA residual would silently cease to be an exact error term. Zero, supported subnormal products, cancellation, overflow refusal and true underflow refusal have independent Fraction controls. No new third-party source or runtime dependency is introduced.

The global cubic Bernstein projection is multiplied by three, removing its non-binary denominator. With N0=u0×v0, N2=u1×v1 and M=u0×v1+u1×v0, its exact controls are:

- G0=3w0·N0
- G1=w0·M+w1·N0
- G2=w0·N2+w1·M
- G3=3w1·N2

Exact expansion de Casteljau half-splits restrict these controls to the same dyadic interval already visited by the original DFS. The cubic representation is tried first. Its mathematical Bernstein hull can remain inconclusive even when every arithmetic operation is exact. A fixed, bounded sequence of degree elevations may then try degrees4…8 on the same interval. This changes only the polynomial's representation: the actual four points still follow precisely the original linear motion, and the determinant remains the same cubic function up to a tracked positive scale.

For current degree n−1 and controls C, the new degree-n controls are n*C0, k*C[k−1]+(n−k)*C[k] for 1≤k<n, and n*C[n−1]. These integer weights represent n times the previous polynomial. The tracked scale is therefore 3,12,60,360,2520 or20160. No nonbinary division is introduced. Only then are controls converted to outward binary64 bounds. The original outward normal controls still bound |n(t)|. All scaled projection bounds must have the same strict sign, and their absolute lower bound must exceed an outward bound for scale×floor×normalNormUpper. This applies at positive floors, with no special zero-floor authorization. Inexact/unavailable arithmetic cannot contribute a successful leaf.

The filter permits at most 64 words per expansion and 1,048,576 EFT steps over one complete primitive call. `Limits.maximumExpansionOperations` may reduce that work cap, including to zero; it cannot exceed the default maximum. Exhaustion returns a budget failure rather than silently skipping work. Each EFT step checks cancellation and nearest rounding. A lazy 128KiB conservative scratch allowance and every retained trace payload/capacity are charged against the original working-memory limit. This is an array-capacity estimate, not a process-RSS guarantee. The original two proof levels may still certify an interval independently when expansion arithmetic is unavailable; unavailable arithmetic itself never grants separation.

`ExpansionCertificate` is a third, separate trace type. It records projectionDegree3…8, the tracked projectionScale, degree+1 scaled Bernstein interval bounds, the original three normal interval controls, strict sign/lower bound, normal upper bound, scaled required product and a diagnostic distance lower bound. Historical cubic traces without a degree field decode as degree3 from their four controls. Old fixed and ordinary moving traces retain their meanings. All three leaf arrays jointly partition [0,1]; old JSON without expansion fields decodes with zero/empty defaults. Report counters expose attempts, certified intervals, EFT steps, peak word count and unavailable arithmetic reason. At most nine control bounds and their capacity/payload are charged against the unchanged trace-memory limit.

The first six expansion-specific tests passed in `/private/tmp/TailorAssFSCExpansionPackageFirst`. An independent exact-binary Fraction audit checks 199 sum/product operand pairs, and a separate polynomial oracle checks every exported scaled control and full mixed partition. Controls cover the actual narrow EE miss, a strictly positive required floor, an excessive floor that remains unproved, true VF/EE contacts, time/edge reversal, power-of-two SI scaling, old report decoding, cancellation during EFT, unsupported rounding, operation and memory limits. Full saved inner and physical-outer Self queries must complete all original features and domain certificates after the formerly blocking witness; this is still a saved-path replay, not a new Newton solve or final garment acceptance. The complete package/SDK pass status belongs to its sealed run summary, not to a sum of earlier filtered test counts.

The subsequent Native117 initial-state run produced different saved Circle690 endpoints. Their exact degree3 hull at depth12 has one negative control (about −1.21e−21), although the determinant itself stays positive. This is a representation bound, not an EFT arithmetic or work-budget error. Independent Fraction degree elevation proves that actual witness with23 time nodes, depth11 and one degree7 leaf; the original default depth12/node8191 limits suffice. This new regression is kept separate from the earlier Native111 motion. Tests independently verify weighted-control equalities and the complete power-polynomial identity Pnew=n*Pold, all reported interval controls and common-scale thresholds, true crossings/tangencies, old cubic JSON, and the complete saved local/physical Self queries. A new fresh garment solve and its final KKT/quiet/body checks remain separate work; a successful witness or saved path does not accept outer690.



### Bounded zero-shell critical-value filter

After the existing fixed plane, moving-normal interval and exact cubic degree-3…8 Bernstein filters fail, **only `minimumSeparation == 0`** may try the same restricted cubic's critical-value lemma. The polynomial is `projectionSign * 2^e * 3g(t) = at³+bt²+ct+d`; signed endpoints must both be strictly positive. Positive binary scaling is exact; underflow, overflow, 64-word expansion capacity and the existing 1,048,576 EFT-operation limit fail closed. Time depth 12, nodes 8191 and the original 128 KiB lazy scratch/1 MiB working limit remain unchanged. This additional filter does not certify primitive nondegeneracy, body exterior, adjacency, or unvisited features.

For nonzero `a`, define `D=b²−3ac`, `H=2b³−9abc+27a²d`, and `Disc=18abcd−4b³d+b²c²−4ac³−27a²d²`. If `D<=0`, endpoint positivity suffices by monotonicity. If `D>0`, the sufficient exact signs are `H>0` and `Disc<0`. Their identity `H²−4D³ = −27a² Disc` proves the unique local minimum positive, independently of approximate root location. Its value is `−Disc/(H+2D sqrt(D))`; the implementation uses the **upper bound of negative Disc**, a denominator rounded upward and division rounded downward. For `a==0`, concave/linear cases use the endpoints; a convex quadratic additionally needs `4bd−c²>0`, with downward lower bound `(4bd−c²)/(4b)`. Conditions are sufficient rather than complete; unresolved cases remain rejected. The positive lower bound is intersected with both endpoint lower bounds and divided by `2^e * 3 * normalUpper`, rounded downward. A nonrepresentable positive distance is not certified.

`CriticalCertificate` is a separate trace: it records the proof kind, power coefficients, normalized endpoints, D/H/Disc or quadratic numerator bounds, binary exponent, original quadratic-normal bounds and strict positive distance bound. Its Bernstein coefficients may straddle zero; it is never reported as an all-positive Bernstein trace. Optional report fields decode as zero/empty for historical reports. Existing earlier fixed/moving successful branches are unchanged; a new critical proof may end an older exact/elevated test trajectory sooner, so current tests accept the explicitly recorded proof type while still independently testing all degree-elevation identities. SDK elevation clients use a positive shell to keep that older path exercised.

The new fixture captures the **fresh Native123 S690 replay** terminal candidate, not the earlier Full117 saved690 endpoints. Focused tests re-evaluate both inner and physical-outer complete Self queries, and independent Fraction reconstruction checks every critical coefficient, exact sign identity, lower bound and full time partition. This is a continuous-distance proof only, not a successful Newton step or validated garment.


### Common amplitude fallback for arbitrary affine normals

The original separately normalized closest-vector proposal remains first. If its
complete quadratic projection proof fails, a second proposal divides both raw
endpoint vectors by one common maximum component. This retains their relative
amplitude; closest-point arithmetic still grants no separation permission.
Both proposals pass through the same exact stored-binary vertex-pair projection,
strict floor and conservative norm proof. `affineNormalAttempts` counts actual
proposals (up to two per reached interval); certified intervals are counted once.
All EFT operations share the existing work counter and64-word capacity. The
original depth12,8191-node,1MiB working estimate and1,048,576 EFT operation caps
remain unchanged. Sequential proof temporaries use the already reserved128KiB
exact scratch; no second live trace or extra time interval is introduced.

The additional source-bound fixture is the saved new `e642` Circle1131
attempt13 motion. Its isolated replay remains a rejected macro step. A safe
saved last-trial path and a successful feature proof do not promote a Session,
certify preceding rejected trials, or establish a final garment.
