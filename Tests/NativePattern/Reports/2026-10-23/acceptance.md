# Native pattern replacement acceptance — 2026-10-23

Upstream: GarmentCode `d449629979028123a5c4dc9e732a2ec19b7fce31`.
Runtime: Swift / Foundation geometry and SwiftUI, without Python, Warp or Unity.
Generator metadata: `swift-pattern-only-2`, tangent solver `native-simplex-v1`.

## Accepted numerical implementation

The user approved preserving official parameters and garment formulas while
using a stable native tangent optimizer and joint geometry/seam acceptance.
The official length, endpoint-tangent, sampled maximum-curvature and endpoint
extension objective is retained. Deterministic simplex replaces the sensitive
finite-difference L-BFGS-B path. Nonconvergence is reported as a generation error.

The native geometry gate preserves exact panel names, edge connectivity, labels,
curve types, arc flags and stitch references. Unaffected panels retain existing
numeric tolerances with a 1e-6 cm numerical floor. Fitted sleeve/cuff curves must
remain within 3 mm of their official counterpart; hood curves within 6 mm, in
both directions. The test bounds continuous distance using target interpolation
error and source derivative bounds. It rejects unresolved intervals and includes
counterexamples with displaced lines and an inflected curve with a coincident
midpoint. Paired-edge signed length differences must change by less than 0.5 mm,
preserving official ruffles rather than forcing equal raw lengths.

## Scope and evidence

| Requirement | Evidence |
| --- | --- |
| Complete pinned default body/design parameter catalog | Entire bundled dictionaries compared equal to the pinned `mean_all.yaml` and `default.yaml` |
| Body dependent formulas | Consecutive body-edit oracle snapshots and two official body-profile grids in `Smoke.swift` |
| Public garment selections | Shirt, FittedShirt; StraightWB, FittedWB; SkirtCircle, AsymmSkirtCircle, Skirt2, SkirtManyPanels, PencilSkirt, GodetSkirt, SkirtLevels |
| Component and combination semantics | 356 pinned comparisons, including both 80-selection body grids, collars, sleeves/cuffs, asymmetry, strapless, darts, skirt tiers/inserts/slits/decorative cuts and joins |
| Shape and stitch semantics | `GARMENTCODE_NATIVE_ACCEPTANCE=1 sh Tests/NativePattern/run.sh` exits 0 |
| Native objective and curve constraints | 12 fixed-input fits pass length <0.01 cm, endpoint tangent residual ≤ max(0.005, 1.05 × official), objective ≤ 100.1% of official |
| Numerical stability | Sampled one-ULP perturbations pass <0.001 cm response; known smooth/nonsmooth optimizer objectives and independent matrix/length tests pass |
| JSON compatibility and invalid-input handling | 12 import/roundtrip cases, unit normalization and oversized sampling checks pass |
| iOS build | Simulator Debug `xcodebuild` exits 0; built app installed and launched on iPhone 17 / iOS 27.0 |
| Parameter-to-preview UI | Shirt + Hood2Panels generates 6 pieces; selection shows right hood 26.13 × 48.37 cm and 4 stitch groups |
| Export/import UI loop | Skirt2 generates 2 pieces, exported through system share sheet to local Downloads, then selected through the import file picker and restored to 2-piece preview |
| Lossless file roundtrip | Generated and reimported temporary JSONs are both 28,331 bytes with SHA-256 `acd91e46c939896b06d6995346cc478ffe33ae11e6d831d758ea8bda159e8320` |
| Legacy path removed | `PatternDesignView` directly hosts `GarmentCodeNativeDesignView`; old approximate generator/private model removed |

Run the whole acceptance suite from the repository root:

```sh
sh Tests/NativePattern/run-acceptance.sh
```

## Measured differences and limits

The largest observed change in signed seam-length difference is 0.2369 mm.
The worst same-parameter sleeve-point difference is 7.6486 mm; comparing actual
geometric shape rather than parameter speed gives a sampled distance of 2.7552
mm. Shirt hood sampled shape distance is 5.7785 mm. Review images and per-panel
metrics are stored alongside this report. Those plots are discrete diagnostics;
the Swift acceptance gate separately bounds continuous distance.

The old strict numeric comparison remains available with `sh
Tests/NativePattern/run.sh` and still reports the known fitted-control
differences. It is distinct from the approved native solver acceptance route.
Representative tests cover public programs and components; they are not an
exhaustive enumeration of continuous parameter space. Software acceptance does
not certify individual physical fit. Three-dimensional simulation, printable
PDF tiling and integration with fabric layout remain outside this stage.
