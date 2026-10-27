`GarmentCodeJointPreconditioner` supplies a serial sparse preconditioner for `GarmentCodeJointObjective.Frame`. Its matrix uses the original physical mass, current material orientation and actual signed barycentric sewing rows. The caller continues to evaluate the declared energy, gradient and exact Hessian through the objective.

```swift
let plan = try GarmentCodeJointPreconditioner.Plan(prepared: clothPrepared)
let workspace = try plan.makeWorkspace()
let update = try workspace.update(frame: clothFrame, positions: current)
let z = try workspace.solve(rhs: residual,
                            generation: update.linear.generation).vector
```

The immutable `Plan` contains the complete lower CSC source/sewing pattern, optional four-vertex hinge pattern, mass-diagonal offsets and precomputed scatter slots. A `Workspace` belongs to one numerical worker and deliberately has no `Sendable` conformance. Each Newton update invalidates the previous numeric generation, assembles a private matrix and performs numeric refactorization with the same symbolic ordering. Cancellation and failure never publish a partial solution or substitute an earlier pose's factors.

The represented matrix has these terms:

- Physical inertia is `m_i / dt²` on each Cartesian DOF. Normalized inverse masses, mass floors and new pins are absent.
- Each triangle contributes `A0 * B_Rᵀ * C_linear * B_R`, where `R = F (FᵀF)^(-1/2)` is computed from the current deformation and held fixed during that linear solve. Original `du`, `dv`, area, shear stiffness and area stiffness are retained.
- Each active principal barrier contributes `A0 Dᵀ H_F⁺ D` in the same source9×9 pattern. Six analytic orthogonal deformation-space modes include repeated stretches, shear/rotation and both normal directions. Only this proxy clips negative density curvature; the actual barrier E/g/rawHv is unchanged. [The separate verification](PRINCIPAL-BARRIER-PRECONDITIONER.md) covers independent full eigendecomposition, stable near-repeated secants, covariance, SI, staging budgets and the real250 stiffness mismatch.
- A nonzero-target sewing row contributes `k [nnᵀ + max(0, 1-target/length)(I-nnᵀ)]` through its original signed coefficients. Only this algorithmic matrix clips negative transverse curvature. The true objective and Hessian retain that curvature.
- A zero target uses the smooth `k I` block even at exact coincidence. A nonzero target at exact coincidence is rejected without an epsilon normal.
- When the actual bending material has `kb > 0`, every original source hinge contributes the PSD Gauss–Newton block `2 * kb * sourceWeight * q qᵀ`, where `q = d(theta)/dx` is the public source-domain-checked `HingeBending.Prepared.angle` derivative. Its four vertices need the full 12×12 block (78 lower entries), including the two opposite vertices that do not share a source face. The CSC pattern and scatter include those pairs explicitly; it never substitutes a 9×9 face block or excludes a source hinge.

The source preconditioner omits body/self contact and friction stiffness; the existing contact workspace adds complete current body/self PSD blocks with an explicitly rebuilt nonlocal graph. Hinge GN omits the exact `theta * Dq` curvature; the true objective retains its complete energy/gradient/exact Hv, including possible negative bending curvature. This is an algorithmic preconditioner only.

The `kb == 0` path adds no hinge pattern/scatter and evaluates no angle derivative. For the three frozen matrices with inactive principal barriers, its CSC and Double-value bytes still match: synthetic, complete real initial state and real r16. Active barrier entries are now included separately. The fixture records the original P source hash and a baseline run performed before these changes. Changing `kb` or any barrier parameter requires a matching Plan. Nonzero bending checks every public source hinge field, counts, panel membership and material before update; `Frame.prepared.bending.angle` enforces that frame's source-domain rules. Degeneration, the principal-angle branch, invalid coefficients, cancellation and memory/nonzero/hinge/barrier limits fail atomically without old-factor reuse.

The public `angle` API currently validates the complete position array per hinge, so this implementation has an explicit O(vertexCount × hingeCount) validation cost in addition to sparse assembly. `UpdateReport.hingeGaussNewtonCount` and `hingeAssemblySeconds` expose this cost. No private angle formula was copied and no extra cache or changed H/linearization API was introduced in this update.

`NativeSparseCholesky` owns the C workspace in the existing local package. It uses public Apple Accelerate Sparse APIs available before the project's iOS 17 minimum. The bridge checks CSC ordering, finite values, dimensions, nearest rounding, budgets, generations and the actual represented-matrix residual. Numeric failure adds no jitter or compliance. SDK-reported factor storage is a minimum, not a process RSS measurement. Cancellation is checked around opaque SDK factor/solve calls; those kernels provide no mid-call cancellation callback.

The SDK declaration names for the workspace `SparseSolve` overload differ from its inline implementation. The bridge follows the actual `(factor, rhs, solution, workspace)` implementation, protected by the analytic Swift C-interop test.

Verification commands:

```sh
python3 Tests/NativePattern/run-joint-preconditioner.py
python3 Tests/NativePattern/run-native-sparse-platform.py
swift test --package-path NativeClothCollision -c release --filter NativeSparseCholeskyTests
```

The isolated App regression checks current-orientation exact Hessian agreement at isometry, rotation covariance, heterogeneous physical mass, real barycentric rows, signed curvature, coincident zero targets, invalidation/cancellation and source limits. Folded-hinge tests separately compare added P blocks to `H.hessianProduct(mode: .gaussNewtonPSD)`, prove that exact folded H is different, and verify SPD, rigid covariance, source/material rejection, the complete four-vertex graph, principal-branch failure and cancellation during the hinge stage. The actual objective energy, gradient and exact Hv stay unchanged.

The persistent `3d-joint-preconditioner` fixture binds the complete 2000-vertex / 3472-triangle / 4948-hinge / 69-row native source to the existing `3d-hinge` topology and plan. It compares every original initial matrix entry and an independent Hessian-vector oracle, checks the three `kb0` byte hashes, then tests the real r16 positive-bending GN matrix and its actual solve residual. Subtracting two large full matrices can lose bits relative to a small bending block; that real comparison reports an explicit binary64 roundoff bound, alongside the small synthetic direct-GN comparison. Test coefficients are algebraic controls and are not calibrated fabric presets or a garment pass.

The platform smoke executes real Swift→C→Accelerate calls on macOS and links the same calls for arm64 iOS 17 and x86_64 iOS 17 Simulator. Device execution and complete garment acceptance are separate validations. This helper alone changes no legacy solver route or export output.
