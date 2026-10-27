# GarmentCode native pattern acceptance

## Asymmetric tier interfaces

```sh
python3 Tests/NativePattern/run-levels-hem.py
```

24 independent pinned upstream cases cover four bases, two bodies and 2/3/5 asymmetric tiers. Full panels, seam references, metadata and geometry are checked; the legacy observer records actual mismatches without weakening corrected acceptance. This is a pure 2D regression, not garment physics. See [LEVELS-HEM.md](LEVELS-HEM.md) for the 618-input delta and the separate six successful/two budget-rejected fresh preparations.

## Visible-body surface contact (current mode)

```sh
sh Tests/NativePattern/run-full-body-coverage.sh
sh Tests/NativePattern/run-body-surface-contact.sh
GARMENTCODE_BODY_SURFACE_OUTPUT_DIR=/private/tmp/TailorAssBodySurface sh Tests/NativePattern/run-cloth-body-surface.sh
python3 Tests/NativePattern/render-body-surface-report.py --input-dir /private/tmp/TailorAssBodySurfaceFinal --output-dir Tests/NativePattern/Reports/2026-10-25-body-surface
```

The App enables `useBodySurfaceCollision` for the standard mannequin. Default
kernel settings keep it off so the old controlled circle/Skirt2 snapshots remain
reproducible. This mode adds a closed-body BVH, component winding validation,
actual cloth/body triangle-crossing inspection and local barycentric contact.
The old Skirt2 default had 130 proper body/cloth intersections despite only
0.200 mm SDF vertex penetration; all 130 are detected by an independent oracle.
Whole-face projection onto an infinite body tangent plane was rejected because
it destroyed source metrics. The contact instead acts at the clipped crossing,
with finite-facet vertex and edge handling and bounded weighted corrections.

Numerical targets are **0.5 mm exact-mesh contact**, **2.5 mm SDF vertex
projection** and **5 mm fixed waist-support clearance**. These are not measured
fabric thicknesses or certified minimum distances. Proper crossing classification
uses a 1e-7 m numerical tolerance, not a statement of physical body accuracy.
The offset circle support is reparameterized by its own arc length; Skirt2 keeps
each original gathered waist chord through a continuous indexed support curve.
Only actual triangle edges carry the source metric in the new mode.

Eight configurations pass the unchanged <8% source strain, <3 mm SDF vertex
estimate, sustained motion <0.025 m/s, zero self intersections and zero visible
body triangle crossings. They cover five Skirt2 length/flare/material cases and
three circle angles. An independent three-axis closed-mesh test finds all 6,432
vertices and 11,904 triangle centroids outside the body, without ambiguous rays.
The historical mesh had four inside centroids even though every vertex was
outside. This remains discrete, bounded verification, not continuous collision
or physical-fit certification.

The full same-mesh SDF now has 128×181×65 samples (6,023,680 bytes), covers every
visible body vertex, and has zero odd preprocessing ray rows. All 1,106,560
legacy lower-body samples retain their exact bytes. The body geometry and named
reference measurements are unchanged; this does not add personal upper-body fit.

[Current report](Reports/2026-10-25-body-surface/index.html) contains eight new
meshes and the immutable historical mesh, fixed-camera images, source checks,
independent body-volume checks and raw OBJ/JSON. Its combined snapshot explicitly
records two run sources: after a Circle-only support fix, the unchanged five
Skirt2 results are reused and the three Circle cases plus both flag-off controls
are rechecked. It does not claim one single final nine-selector invocation.

Native Device Hub verification of this body-contact build covered medium and
soft Skirt2, medium 0.75-circle, both displayed intersection counters and local
Files export. The exported soft Skirt2 OBJ matches the report OBJ byte for byte.
See [UI metadata](Reports/2026-10-25-body-surface/ui/verification.json) and the
actual [Skirt2](Reports/2026-10-25-body-surface/ui/app-simulator-skirt2.jpg) and
[circle](Reports/2026-10-25-body-surface/ui/app-simulator-circle.jpg) screenshots.
Displayed 3.1 / 6.6 second times are Simulator observations, not phone benchmarks.

## Generic source-panel triangulation

```sh
sh Tests/NativePattern/run-panel-mesher.sh
```

The generic native mesher has passed 15 panels: both waistband families,
concave Shirt armholes, fitted/darted torsos, Pants, a cut Skirt2, reversed
U contours and a short-chord cubic S curve. Independent checks cover every
original edge ID, shared corner, curve parameter, analytic arc fraction, dense
Green area, containment, CCW manifold disk topology and all source bytes.
The acceptance spacing is at most 3 cm with a curve deviation bound of 50 µm;
these are tessellation tolerances, not physical fabric accuracy. Source acute
corners remain acute and are reported rather than moved to improve angles.
Cancellation, explicit resource budgets and malformed/self-crossing/open inputs
are checked. A simple single boundary loop is supported; this does not imply
that all these garment families can already be assembled and simulated in 3D.

## Separate-panel sewing foundations

```sh
sh Tests/NativePattern/run-sewing.sh
sh Tests/NativePattern/run-sewn-contact.sh
```

Both suites pass. Sewing checks analytic weighted/barycentric XPBD solutions,
mass-normalized compliance, actual gap versus assembly-ramp residual, fixed and
partial pins, per-frame motion limits, cancellation and refusal contracts.
Runtime plans bind source hashes, exact edge identities and explicit directions;
fabric-side `rightWrong` does not silently reverse a path. Ordinary equal-length
seams use the union of both meshes' boundary knots. Gathered/eased seams retain
actual untacked boundary nodes and request local refinement when undersampled.
Their finite tack gaps do not certify a continuously closed gathered seam.

The contact bridge allows only corresponding boundary locations to touch.
Independent tests keep coplanar area overlaps, deep crossings of the same
seam-adjacent face pair and untacked fold intersections active. A shared dart
corner and all incident faces at a boundary tack are handled without an entire
face/panel collision exemption; interior-edge/vertex exemption data is rejected.
These are assembly primitives; general garment placement and composed outfits
still require integration tests before becoming new App capabilities. The
standalone waistband integration is verified below.

## Current App: independent-particle waistband sewing

The full product objective and all outstanding garment/parameter branches are
tracked in [3D coverage](3D-COVERAGE.md). Passing one suite below does not imply
that all garment families, combinations or iPhone performance are complete.

```sh
sh Tests/NativePattern/run-sewn-input.sh
sh Tests/NativePattern/run-sewn-drape.sh
```

The current App routes standalone WB through `GarmentCodeWaistbandAssembly`,
the verified `PreparedInput` factory and `GarmentCodeSewnDrape`. Front/back paper
vertices remain separate; actual barycentric seam gaps are measured rather
than being zero by a welded-DOF construction. All four default/2-mm-perturbed
Straight/Fitted cases pass at the App's 32 solver iterations, 40 source-strain
limiting passes, a 200-mm accumulated internal sewing correction path and a
separate 20-mm maximum single correction. The internal path is not physical net
travel. Source strain remains about 5–6.10%, actual gap is below .5 mm, final
speed is below .025 m/s and all true-body/self crossings and inside samples are
zero. Source/rest/mass/pins/body bytes, cancellation and invalid budgets pass.

The previous 20-mm and 100-mm path budgets' rejected poses are retained in
separate temporary runs; iteration counts or quality gates were not reduced to
obtain a pass. The [current report](Reports/2026-10-25-waistband-sewn/index.html)
contains actual source, plan, reference, mesh and independently checked gaps.
This opens standalone waistbands only, not composed outfits or all dimensions.

Final native UI checks cover Straight medium/soft and Fitted medium/firm, actual
material invalidation and regeneration, camera rotation/reset and body hiding.
All four generated outputs display convergence and zero final crossings.
The [UI metadata](Reports/2026-10-25-waistband-sewn/ui/verification.json) links
actual screenshots and a soft Straight OBJ saved via the native Files sheet.
That exported mesh is independently checked against the unchanged source paper,
actual barycentric seam constraints and closed body, rather than asserted to
match a different material's CLI snapshot. Simulator timing is not a phone
benchmark.

## Experimental circle assembly (not wired into the App)

```sh
sh Tests/NativePattern/run-circle-assembly.sh
GARMENTCODE_CIRCLE_ASSEMBLY_SMOKE=1 sh Tests/NativePattern/run-circle-assembly.sh
```

The default command only verifies source-faithful preparation for .5/.75/1
circle skirts with separate particles and real side-seam constraints. It leaves
the caller's optional strain limiter `nil` and does not simulate that setting.
The explicit smoke switch runs .75 with the caller enabling the experimental
5% / 40-pass limiter, 32 solver iterations, 200-mm internal sewing path and
20-mm single correction, followed by independent source strain, actual seam,
body crossing and three-axis volume checks. The successful exploratory .75 run
took about 56.7 seconds on the Mac; this is not iPhone performance. App circle
skirts continue using the previously verified backend. Composition, other
circle sizes' 3D results and performance remain work to complete.

## Shared full-source assembly and placement foundations

```sh
sh Tests/NativePattern/run-assembly-builder.sh
sh Tests/NativePattern/run-panel-placement.sh
sh Tests/NativePattern/run-lower-placement.sh
sh Tests/NativePattern/run-panel-mesher.sh
sh Tests/NativePattern/run-sewing.sh
sh Tests/NativePattern/run-sewn-input.sh
sh Tests/NativePattern/run-sewn-point-block.sh
```

`AssemblyBuilder` concatenates every actual source panel without welding,
restores original fabric normals, derives all real triangle-edge distances and
within-panel opposite-vertex bends, integrates original area/mass, and validates
the full document, explicit seam hints and exact collision body through the
single `PreparedInput` factory. Both waistband fixtures preserve identical
initial/source/rest/mass/body/sewing state and pass the original physical gates.
Actual OBJ panel groups and output JSON are checked; malformed optional groups
cannot silently omit cloth faces or index outside topology. Previous Circle and
Skirt2 output records still decode and export byte-identically.

`SewnPointBlock` is an explicitly enabled final-sewing option. After the
existing distance ramp reaches one, it solves shared Cartesian attachment
constraints together in the original inverse-mass metric. It caches small
Cholesky blocks and uses matrix-free preconditioned CG for larger or singular
blocks; it never adds artificial compliance to repair rank deficiency. Actual
residuals, unsolved rows, fixed rows and bounded correction paths remain
observable. Cancellation publishes no partial positions, multipliers or path
state. Analytic, rotated, redundant, capped and real 69-row tests pass against
an independent linear oracle. The existing waistband control passes with the
option enabled; the default remains the established scalar path with identical
frozen waistband positions and legacy OBJ bytes. This module test does not
establish full-garment physical convergence.

The point-block runner defaults to the persisted numerical fixture in
`Fixtures/3d-sewn-point-block` and verifies its hashes. That fixture retains the
complete paper source, plan and reference plus exact cloth positions from a
rejected assembled run. It deliberately omits rendering-only body arrays and
does not represent an accepted full-garment or official 3D result.

`LowerPlacement` maps all eight native lower families and their real cuffs,
godets, tiers and optional waistband from current parameters and upstream
component transforms. The two-body, 374-source-panel matrix verifies initial
positions, rotations and fabric normals against pinned official fixtures.
Complete source identity is required; unsupported branches never drop panels.
These separated initial sheets are not yet an assembled garment or a new App
3D route.

Additional native placement and source-branch suites:

```sh
sh Tests/NativePattern/run-upper-placement-complete.sh
sh Tests/NativePattern/run-inverse-sleeve.sh
sh Tests/NativePattern/run-composition-placement.sh
sh Tests/NativePattern/run-composition-rise.sh
sh Tests/NativePattern/run-native-assembly.sh
sh Tests/NativePattern/run-rigid-body-clearance.sh
python3 NativeClothCollision/Scripts/run-checks.py
python3 Tests/NativePattern/run-continuous-body-contact.py
```

The complete upper replay covers 108 cases / 868 actual source panels; the older
`run-upper-placement.sh` retains its historical fixture and is not the latest
complete replay. The optional inverse-sleeve intersection repair preserves the
original 107 source hashes and adds 12 direct official branch controls.
Composition placement checks 160 full meta selections / 1,116 panels against
original component interfaces. Its isolated transforms do not establish physical
sewing. The 48-case composition-rise control checks full 2D geometry and placement
for fitted/loose tops plus circular/asymmetric/many-panel skirts, including
original design provenance.

`NativeAssembly` combines the real native component maps, complete source
meshes and actual stitches without hidden pins. Its numerical preparation and
rigid clearance tests do not establish a settled garment. The rigid clearance
control retains original source/rest/mass and independently tests actual body
crossings, body-volume samples and inter-panel proper/coplanar overlap; it
records the still-open initial seam gap. The continuous body bridge runner
freezes exact App models and the local package before compiling, then executes
analytic, cancellation/rejection and real upper-body motion controls. It proves
motion-path clipping only, not cloth self CCD, accepted garment physics, App
routing or phone performance. Each runner writes its own result; listing a
command here does not claim every current command has passed.

`sh Tests/NativePattern/run-membrane.sh` freezes and verifies original source
triangle metrics, a 3x2 Neo-Hookean energy/gradient/exact Hessian product, a
principal-stretch interval barrier and whole-path feasible step bound. It checks
analytic invariants and independent LAPACK SVD/energy differences on the actual
rejected 60/469-frame capture. This is the joint solver's elasticity/feasibility
foundation, not an accepted sewn garment; see [MEMBRANE.md](MEMBRANE.md).

`sh Tests/NativePattern/run-hinge-bending.sh` verifies the independent internal
source-hinge energy, exact derivatives and separately named PSD approximation.
It retains explicit panel membership, source areas and flat rest angles, and
adds no hinges across sewing interfaces. See [HINGE-BENDING.md](HINGE-BENDING.md).
Neither energy suite alone runs or accepts a complete garment.

`sh Tests/NativePattern/run-elastic-energy-delta.sh` checks stable Double
increments against 25 actual Newton line-search candidates and four complete
active-barrier/bending controls; domain/precision failures remain explicit.
`sh Tests/NativePattern/run-joint-objective.sh` verifies combined inertia,
membrane, principal barrier, internal hinge and real scalar sewing E/g/exact Hv,
as well as their combined stable increment. Neither runner accepts a physical
time step or enables a garment App route. See [ELASTIC-ENERGY-DELTA.md](ELASTIC-ENERGY-DELTA.md)
and [JOINT-OBJECTIVE.md](JOINT-OBJECTIVE.md).

The positive-gap initializer is checked by
`sh Tests/NativePattern/run-native-positive-clearance.sh`, including independent
VF/EE distances, all 211 cases and exact preservation of 633 old mode signatures;
see [POSITIVE-CLEARANCE.md](POSITIVE-CLEARANCE.md). It creates a feasible start,
not a sewn garment.

`sh Tests/NativePattern/run-membrane-path.sh` verifies bounded whole-path source
intervals, including the actual formerly rejected r63; see [MEMBRANE-PATH.md](MEMBRANE-PATH.md).
`sh Tests/NativePattern/run-joint-input.sh` checks real complete-source/SI mass
bridging. `python3 Tests/NativePattern/run-joint-body-objective.py` checks the
actual App-to-native joint body force and exact Hv; `python3 Tests/NativePattern/run-joint-newton.py`
checks an independent analytic target and the first real body-coupled Newton
subproblem. These do not accept a full garment; see [JOINT-BODY-NEWTON.md](JOINT-BODY-NEWTON.md).

The mesher accepts per-source-edge spacing overrides for real sewing refinement
requests. Tests rebuild an initially undersampled gathered seam, retain actual
unattached fold nodes and check source immutability, arc spacing and unchanged
other-edge/default sampling. Imported panel placement follows the pinned
meshgen's Rz*Ry*Rx rotation and declared source units, then shifts the waist
origin. Its tests cover actual torso, leg, sleeve, lapel and hood panels,
normals, unit conversion, cancellation and invalid/missing/zero placement.
These are reusable foundations, not proof of complete garment draping or new
App routes. Earlier reports remain immutable snapshots of their recorded source
versions; changed model files require new integration evidence.

## Independent waistbands: welded reference and source strain limiting

```sh
sh Tests/NativePattern/run-strain-limit.sh
GARMENTCODE_WAISTBAND_OUTPUT_DIR=/private/tmp/TailorAssWaistbandFinal sh Tests/NativePattern/run-cloth-waistband.sh
GARMENTCODE_WAISTBAND_SENSITIVITY=1 GARMENTCODE_WAISTBAND_OUTPUT_DIR=/private/tmp/TailorAssWaistbandSensitivity sh Tests/NativePattern/run-cloth-waistband.sh
python3 Tests/NativePattern/render-waistband-report.py --input-dir /private/tmp/TailorAssWaistbandFinal --sensitivity-dir /private/tmp/TailorAssWaistbandSensitivity --output-dir Tests/NativePattern/Reports/2026-10-25-waistband-3d
```

The nine-case matrix preserves the real rectangular/annular paper, both side
seam metrics, triangle-edge rest lengths, area and material mass. Front centers
align to the actual body's front midplane rather than anchoring an arbitrary
side-seam phase. The optional 5% strain-limit target projects real positions
jointly with the unchanged SDF, body-mesh and cloth-surface contact. It never
rewrites rest lengths or clamps a reported diagnostic. The original 8% final
edge gate, motion/penetration gates and zero intersections remain in force.

The frozen report contains seven quality passes and two explicit rejections:
wide StraightWB at width ratio .35 and source waist multipliers 1.0 /1.05.
Their actual maximum strains remain 15.8880% /10.1799%; a regression-process pass
does not mean all nine meshes passed quality. The second is explicitly another
paper, not a silently enlarged replacement. Independent closed-body volume and
proper-crossing checks put all 1,228 vertices and 1,752 face centers outside the
body without ambiguity. Default Straight/Fitted maximum strains are about
5.504% /5.000%, with original source top/bottom lengths and radial paper depth.

The primitive suite covers analytic inverse-mass tension/compression, pins,
unresolved/collapsed constraints, source immutability, single-correction caps,
budget/finite validation and transactional periodic cancellation. Reproduction
mode compiles once and runs the two defaults at 20/40/80 limiting passes.
All six pass unchanged quality and independent volume checks. Straight 40→80
changes maximum/RMS positions by .368 /.139 mm; the measured final strain still
exceeds the 5% target slightly after contact. This is a bounded numerical budget,
not physical fabric calibration or a guarantee of exact 5% strain. Limiter-off
Circle and standard-body Skirt2 controls retain exactly every old vertex.

This earlier reference uses admissible equal-length welded side seams.
The current separate-panel assembly path additionally requires a `PreparedInput` factory
that verifies canonical source SHA, complete panel/edge/triangle bindings and
directions, area/mass/weights, free fold nodes, and identical collision/rendered
bodies. `run-sewn-input.sh` passes real separate WB and sparse gather inputs plus
38 invalid/cancellation/budget cases, including reversed-face and forged seam
intent flag rejection.
The independent-particle WB integration is checked separately above; composed
garments still need acceptance before being advertised as App features.

## Offline skirt 3D experiment

This is a separate, bounded experiment, not part of the 356-pattern 2D parity
claim. It uses real circle-skirt rest geometry and seam identities, a licensed
anatomical mesh with a same-surface signed-distance field, numerical material
presets, discrete surface self-contact and waist supports. The original circular
proxy/equal-mass configuration is retained as an exact numerical control. It
does not run the GarmentCode Warp simulator.

```sh
GARMENTCODE_CLOTH_OUTPUT_DIR=/private/tmp/TailorAssClothResults sh Tests/NativePattern/run-cloth.sh
sh Tests/NativePattern/run-standard-body.sh
sh Tests/NativePattern/run-cloth-contact.sh
sh Tests/NativePattern/run-cloth-material.sh
GARMENTCODE_CLOTH_OUTPUT_DIR=/private/tmp/TailorAssClothRefined sh Tests/NativePattern/run-cloth-refined.sh
python3 Tests/NativePattern/compare-cloth-reference.py --input /private/tmp/TailorAssClothRefined --output Tests/NativePattern/Reports/2026-10-25-3d-refined/comparison.json
python3 Tests/NativePattern/render-cloth-report.py --input-dir /private/tmp/TailorAssClothRefined --output-dir Tests/NativePattern/Reports/2026-10-25-3d-refined
```

The optimized refined test exports seven configurations, source patterns and raw
diagnostics: the unchanged legacy control, three skirt angles, one longer skirt,
and two additional material presets. Standard-body cases use 32 constraint
iterations, with the legacy control kept at 24. Gates remain sustained motion
below 0.025 m/s, maximum edge strain below 8%, body vertex penetration estimate
below 3 mm, zero final surface crossings, cancellation and source immutability.
The independent Python check compares the .75-sun source against
the pinned `skirt-circle.json`, analytically measures its annular sectors and
checks manifold, consistently oriented welded side seams. The report builder
uses Python's standard library and shows the exact exported mesh with public
GarmentCode and Design2GarmentCode images. Images are reference-only and are
not bundled into the App. Open `Reports/2026-10-25-3d-refined/index.html` locally;
the original `2026-10-25-3d/` report is preserved.

Body tests check two-leg separation, negative interior distance even with a
zero gradient, mesh/SDF alignment, fitting, and projection. Contact tests include
face-interior crossing with distant vertices, edge contact, coplanar overlap,
adjacency exclusions, and an actual cross-seam failure extracted from the old
full-circle skirt. Material tests check SI area masses, refinement and seam mass
conservation, invalid input, damping, and mass-normalized XPBD equivalence.

`converged` is a sustained numerical-motion/strain/contact and final discrete
surface check, not a continuous-collision or physical-fit certificate. Zero welded
seam gap follows shared degrees of freedom by construction. The current report
cannot establish 3D parity: a matched official final mesh/material/body is not
available. Runtime on the Mac or Simulator does not measure iPhone performance.

### Two-panel skirt extension

```sh
GARMENTCODE_CLOTH_OUTPUT_DIR=/private/tmp/TailorAssClothSkirt2 sh Tests/NativePattern/run-cloth-skirt2.sh
python3 Tests/NativePattern/render-skirt2-report.py --input-dir /private/tmp/TailorAssClothSkirt2 --output-dir Tests/NativePattern/Reports/2026-10-25-skirt2-3d
```

`GarmentCodeSkirtDrape` dispatches circular geometry to the existing circle
adapter and builds Skirt2 from its original straight quadrilateral panels and
two actual side seams. Front and back widths remain different. Skirt2 length
is vertical; its flare is a centimetre increment per lower corner, rather than
a circle-skirt angle. Original flat triangles supply rest lengths and area
masses before seam welding. The supported preparation range is natural waist,
1–1.5 gathering, 0–20 cm flare and 5–150 cm vertical length, without cuts or
additional components. Preparation eligibility does not establish that a narrow
straight tube can fit a wider hip circumference.

Stretch constraints cover exactly the actual welded triangle edges, with no
unmeshed diagonal cross-braces that would lock each quad into a rigid plane.
The skirt's minimum grid has 24 columns per panel and six support corrugations;
the standard-body solver retains 32 constraint iterations. Flared trapezoids
use source-indexed peaks at both side-waist seams: their sewn top corner angles
exceed 180 degrees, so fixing them at a body-touching valley would force the
next seam vertex inward. Exact chord marching and a feasible radial-offset
bound preserve each source edge. Rectangular skirts keep their original support
construction.

The default source waist is 109.63394 cm for an 84.3338 cm body waist (1.3
gathering). A corrugated outward support is marched by each source chord length;
the source waist is not compressed to body circumference. Lower rows initialize
around convex hulls of actual horizontal torso/two-leg mesh sections, excluding
disconnected arm/hand loops, while retaining the flat reference metric. This
lets the front outline shrink below the waist instead of keeping an artificial
waist-radius pouch. A row with insufficient source circumference is rejected
clearly rather than projected through a leg.
The support is an experimental gathering fixture, not a simulated sewn waistband.
Diagnostics and the App distinguish source waist, supported waist, gathering
ratio and vertical length. A quiet pose only ends the solver early when the
same final strain, body-penetration and surface gates also pass.

The test driver checks the pinned official `skirt-two-panel.json`, independent
flat area and spring metrics, unequal panel widths, oriented manifold seams,
pin chord lengths, a startup strain bound, source immutability, mass conservation, unsupported inputs,
cancellation and exact circle adapter preservation. Its numerical configurations
cover the default skirt, changed length, flare and two additional materials.
All five configurations pass the unchanged quality gates; the tested maximum
strains are 7.64%, 7.86%, 8.00% (strictly below 8%), 7.59% and 7.66%, respectively.
All final surface crossing counts are zero and body vertex penetration estimates
are at most 0.201 mm. Soft/firm actual position RMS changes are 1.387/2.335 mm.
The lower gather preparation boundary uses flare 20 cm; gather 1 with no flare
is explicitly rejected for insufficient body clearance. These are bounded
numerical checks, not all-size fit coverage. The new report is separate from
both circle reports. Official final 3D mesh parity remains unverified.

Device Hub UI validation on 2026-10-25 used the iPhone 17 / iOS 27 Simulator
Release build. Default Skirt2 completed with medium, soft and firm presets;
observed runtimes were 1.2/1.3/1.3 seconds and displayed fabric masses were
80.0/53.3/124.5 g. Material changes cleared old output; cancellation and subsequent
regeneration, rotation/reset, mannequin/seam visibility and local Files export
were exercised. The saved soft OBJ exactly matches the canonical exported OBJ
(14,004 vertices including the mannequin, 27,908 faces). These are Simulator
observations, not physical-device performance. See
[verification metadata](Reports/2026-10-25-skirt2-3d/ui/verification.json) and the
[actual Device Hub screenshot](Reports/2026-10-25-skirt2-3d/ui/app-simulator-firm.png).
Small body-face pokes remain; UI completion does not extend the vertex-only
body-contact guarantee.

## 2D pattern acceptance

`sh Tests/NativePattern/run-basic.sh` tests the basic-mode centimetre adapter
against actual generated geometry for two body profiles, including rear-centre
shirt length, skirt/pants component lengths and separate waistband height. It
checks hidden professional parameters remain intact, explicit centimetre targets
can be reapplied after body edits, unsupported combinations have no fake control,
active custom-parameter detection and atomic rejection of invalid lengths. This
gate is included in `run-acceptance.sh`. UI mode switching and text-entry drafts
also require Simulator interaction; software checks do not certify physical fit.

`sh Tests/NativePattern/run-localization.sh` checks Chinese display coverage for
all 122 design fields, 26 body measurements, selectable string values and 58
official panel names in the current fixture corpus. It also checks contextual
units and user-facing validation labels. Display text is maintained separately
from the official parameter schema and serialized identifiers.

`sh Tests/NativePattern/run-seams.sh` checks the read-only seam-display index
against four official fixtures (44 stitch groups), preserving source order,
edge references and right/wrong-side flags without changing source JSON. It
also covers same-panel darts, shared edges, duplicate references, stable
screen-space polyline hit testing, tolerance and degenerate/invalid paths.
Palette rendering, tap/list synchronization and the display toggle additionally
require Simulator UI verification; this script does not test rendered colors.

`sh Tests/NativePattern/run-pdf-plan.sh` checks the physical-centimetre print
layout: true-size squares, native quadratic/cubic paths, circular-arc conversion,
negative coordinates, millimetre/absolute-control normalization, panel ordering,
non-overlapping placement, tile coverage/overlap and resource limits. Circular
arcs use CoreGraphics' standard cubic PDF representation; the sampled arc test
has a 0.003 cm bound, not a mathematically exact rational-circle claim.

`sh Tests/NativePattern/run-pdf.sh` reopens PDFs produced by the App's native
renderer, checking full-sheet/A4 MediaBoxes, page counts, stroked vectors rather
than raster images, a physically accurate 10 cm calibration square, assembly
labels, print warnings, clean-outline mode and unchanged source JSON. Tests cover
a known 10 cm square, pants and pencil skirt. To retain sample PDFs for Poppler
visual inspection, run `GARMENTCODE_PDF_OUTPUT_DIR=output/pdf sh
Tests/NativePattern/run-pdf.sh`. UI preview/sharing and physical-printer scaling
still require separate verification; do not infer physical print accuracy from
screen preview zoom or PDF metadata alone.

`sh Tests/NativePattern/run-allowance.sh` checks unequal per-edge allowances,
native curves, winding, bounded acute joins, concavities, fold supporting lines,
invalid input and official fixture panels. Quartz micro-degeneracies may require
vector flattening at a 0.002 cm threshold; this is a numerical cleanup strategy,
not a general industrial accuracy certification. Dart caps and folded-hem corner
truing are not implemented and require manual review/toile testing.

`sh Tests/NativePattern/run-marks.sh` checks manual grainline containment,
straight unstitched folds, true arc-length paired single/double reference marks,
stitch direction, cut-depth limits and exclusions for darts/unequal/shared edges.
`sh Tests/NativePattern/run-manufacturing-pdf.sh` checks validated settings,
unchanged source geometry/JSON and actual full-size/A4 vector output containing
cutting outlines, line styles, marks, cutting quantity and calibration. Set
`GARMENTCODE_PDF_OUTPUT_DIR=output/pdf` to retain full-size, A4 and colored-seam
manufacturing samples. The current PDF gate checks nine physical pages, including
paired text completeness, dense-layout warnings and white badges not crossing
cutting outlines.
These gates are included in `run-acceptance.sh`; they do not certify physical fit.

Current release check: `sh Tests/NativePattern/run-acceptance.sh`. The existing
generator gates passed on 2026-10-23; manufacturing gates were added afterward
and have separate results. This runs whole-garment native acceptance, isolated objective /
length / tangent quality, sampled one-ULP stability, import/export safety,
Chinese display coverage, seam-display indexing/hit testing and PDF print gates.
See `Reports/2026-10-23/acceptance.md` for scope and evidence. The default
`run.sh` retains the former strict numeric comparison for diagnosis; its known
fitted-control differences do not define the user-approved native solver gate.

Native acceptance retains exact topology/labels/arc flags/stitch references and
the old numeric tolerances for unaffected panels (with a 1e-6 cm numerical
floor). Only sleeve/cuff/hood panels in a garment containing fitted curves use
a bidirectional continuous shape bound: 0.3 cm for sleeve/cuff, 0.6 cm for hood.
Target interpolation error is bounded by the second derivative; source
intervals are covered using a derivative bound. Unresolved intervals fail.
Seam-residual drift remains below 0.05 cm. Acceptance cannot be combined with
numeric-skipping audit modes or a case filter. These are software equivalence
limits, not a physical-fit certification or a sewing allowance.

The following sections preserve the investigation and earlier failing strict
diagnostics chronologically; they are not the current release status.

## Model-space contour review

Export sampled contours from the actual Swift geometry evaluator:

```sh
GARMENTCODE_METRICS_AUDIT=1 \
GARMENTCODE_EXPORT_CASE='FittedShirt asymmetric left-sleeve' \
GARMENTCODE_CASE_FILTER='FittedShirt asymmetric left-sleeve' \
GARMENTCODE_EXPORT_DIR=/private/tmp/tailorass-contour-review \
sh Tests/NativePattern/run.sh
python Tests/NativePattern/ReviewContours.py \
  /private/tmp/tailorass-contour-review/FittedShirt_asymmetric_left_sleeve.json \
  --output /private/tmp/tailorass-contour-review/plots
```

The review script needs NumPy and Matplotlib. It reports both same-parameter
point distance and bidirectional sampled point-to-segment shape distance. The
latter is independent of Bezier parameter speed, but remains a discrete
diagnostic, not a certified continuous Hausdorff bound. Checked review images
and metric records are in `Reports/2026-10-23/`. The worst same-parameter sleeve
case has sampled shape distance 0.275518 cm (2.76 mm); the Shirt hood has
0.577850 cm (5.78 mm). These images show local curved-edge differences and
nearly coincident torso outlines.

The fixed-input `--quality-only` gate additionally requires the unchanged
official objective to be no more than 100.1% of the pinned upstream value.
Ten of twelve fits improve that objective; the other two are symmetric copies
of one hood-back input and differ by about 0.054%. Length and tangent gates
continue to apply independently. This does not waive whole-garment shape checks.

## Whole-garment seam diagnostics (2026-10-23)

`GARMENTCODE_METRICS_AUDIT=1 sh Tests/NativePattern/run.sh` retains panel/edge
topology, labels, arc flags and stitch-reference checks, but reports numeric
differences rather than accepting them. It emits `GARMENT_METRICS` JSON lines
with maximum contour-coordinate error, per-edge length error and signed seam
residual drift against the official pattern. It reports the worst edge IDs.
Subtracting the official seam residual preserves intentional ruffle differences;
requiring every paired edge to have equal length would be incorrect.

`GARMENTCODE_SEAM_CHECK=1 sh Tests/NativePattern/run.sh` adds a separate 0.05 cm
(0.5 mm) maximum seam-residual-drift gate. All 356 existing comparison cases pass
this seam/topology gate; the maximum observed drift is 0.023688 cm. This does
not certify contour or physical fit. The largest contour deviation is 0.764857
cm on an asymmetric fitted-shirt sleeve; the largest individual edge-length
deviation is 0.324987 cm on a hood variant. These require shape review, despite
the much smaller changes to stitched length differences. Default strict
comparison is unchanged and still fails. Filtered runs remain explicitly
labelled as filtered and do not establish whole-corpus coverage.

## Native tangent solver (2026-10-23)

With user approval, the default tangent fitting path now uses deterministic
Nelder–Mead on the unchanged upstream objective. Nonconvergence is an error,
not an accepted approximate result. Explicit `--legacy-optimizer` retains the
former L-BFGS-B path for comparison; `--first-step-only` requires that flag.
The new implementation changes neither garment formulas nor parameter ranges.

Commands and separate gates:

- `sh Tests/NativePattern/run-tangent.sh --simplex-only`: known smooth and
  nonsmooth minimizers.
- `sh Tests/NativePattern/run-tangent.sh --stability-only`: one upward ULP in
  the first control's y coordinate in each of 12 fixtures; maximum sampled
  response must be below 0.001 cm. This is not an exhaustive perturbation test.
- `sh Tests/NativePattern/run-tangent.sh --quality-only`: length residual below
  0.01 cm and endpoint unit-tangent residual at most max(0.005, 1.05 × official
  residual). All current fixtures pass; maximum length residual is ~0.00243 cm.
- Without flags, the historical 0.01 cm contour comparison remains failing;
  current maximum is ~0.602 cm. None of the diagnostic-only passes overrides it.

Full garment seam/shape acceptance remains incomplete. The earlier numerical
notes below describe the previous solver unless explicitly stated otherwise.

## Import/export regression

Run `sh Tests/NativePattern/run-import.sh` independently of optimizer acceptance.
It currently passes 12 official-document roundtrip/rejected-import cases, plus
millimeter normalization and oversized-edge sampling checks. Import now rejects
unsupported coordinate modes and unit-conversion overflow before presentation;
sampling caps its floating-point count before conversion to Int. This is model
validation, not a file-picker/share-sheet UI roundtrip or full garment acceptance.

## Current numeric limitation

`GenerateOfficialGoldens.py --tangent-sensitivity` runs only the pinned upstream
Python implementation. It first requires an unperturbed rerun to reproduce the
captured oracle within 1e-8 cm, then perturbs individual control coordinates by
one ULP in both directions. The 16 recorded experiments have maximum sampled
contour changes of 0.252895 cm (sleeve input 1) and 0.436873 cm (hood input 9).
`Fixtures/tangent-upstream-sensitivity.json` records each baseline error, input
delta and output error. This is evidence of sensitivity in these upstream fits,
not proof that every native discrepancy is caused by roundoff and not permission
to loosen the existing gates.

`sh Tests/NativePattern/run-tangent.sh --absolute-inputs --first-step-only`
passes the matrix, arc-length and first-step checks but reports final contour
errors up to 0.3356 cm (sleeve) and 0.4312 cm (hood). Absolute input mode bypasses
relative-control reconstruction for diagnosis only; production does not use it.
No full acceptance pass is claimed. The chronological notes below include
results from earlier implementations, not current guarantees.

Tangent fixtures now record accepted-iteration trajectories. Diagnostics print
the first shift-vector difference exceeding 1e-5. `--first-step-only` checks
the first accepted step in every fixture and is explicitly not full contour
acceptance. This caught an incorrect alpha<=1 cap: unbounded L-BFGS-B uses
min(1/||d||, maximumStep) on iteration zero. Full alpha=1 trials also retain
the subspace candidate directly, matching lnsrlb's copy rather than x+(z-x).

`sh Tests/NativePattern/run-tangent.sh --matrix-only` verifies the compact
formk/subsm direction against a SciPy inverse-Hessian product and independent
dense inverse-BFGS updates for memory sizes 1–10 (plus empty/invalid history).
This matrix-only run passes. The production fitting path now uses that compact
solve; the isolated contour gate still fails, so this does not replace the
full tangent or garment acceptance runs.

The native unconstrained L-BFGS path now restores/restarts after failed line
search rather than accepting a separate Armijo fallback. History vectors,
curvature threshold and relative-reduction scale follow upstream mainlb.
At that stage the two-loop direction calculation still needed comparison with
L-BFGS-B's compact matrix path (now replaced as noted above). Those isolated
errors remained above target (roughly
0.241/0.0515 cm for sleeve inputs and 0.425 cm for Shirt hood front input).

`--deep-neck` generates the FittedShirt V-neck with both depth ratios at 2.
`GARMENTCODE_CASE_FILTER='deep neckline' sh Tests/NativePattern/run.sh` passes
after correcting the inside-edge-based depth limits, including the raised
back waist center. This is a filtered regression, not full acceptance.
`GARMENTCODE_FIT_INPUTS=1 sh Tests/NativePattern/run-tangent.sh --hood-inputs`
logs the actual Shirt/FittedShirt hood fit inputs; the tangent fixture also
contains Shirt hood inputs in addition to FittedShirt hood and Shirt sleeves.

`GARMENTCODE_CASE_FILTER=Hood2Panels sh Tests/NativePattern/run.sh` limits
golden comparisons to names containing that substring; output explicitly says
filtered runs are not full acceptance. It currently fails the Shirt hood
vertex gate even though the fixed-input FittedShirt hood tangent cases are
within the isolated 0.01 cm target. Do not infer assembled-garment accuracy
from an isolated optimizer case. L-BFGS-B line search now uses its own xtol,
step bounds, evaluation limit and warning acceptance instead of BFGS defaults.

Set `GARMENTCODE_OPTIMIZER_TRACE=1` for native fitting iteration counts,
objectives, final gradients and shifts. Tangent oracle records now contain
the equivalent SciPy result metadata and stopping messages. Both implementations
can stop on relative objective reduction while gradients remain nonzero;
the stopping path, not just the objective formula, still needs alignment.

`--tangent-oracles` records the exact upstream cubic fitting inputs/outputs
for Shirt sleeves and FittedShirt hood. Run `sh Tests/NativePattern/run-tangent.sh`
to isolate those fits from panel projection and stitching. This diagnostic
currently fails its 0.01 cm contour target (observed maxima about 0.009–0.275 cm).
It also checks a symmetric S-curve's length against svgpathtools and split
additivity; the former midpoint-chord heuristic incorrectly returned 10 cm
instead of 11.931715684553971 cm. Adaptive integration of analytic speed fixes
that separate defect. Full garment acceptance remains failing while the
L-BFGS-B numeric differences are unresolved.

**Current gate is failing:** the comparator now also reconstructs centimeter
geometry and samples each edge at 33 parameter values, checking the maximum
coordinate error against the case tolerance. Relative Bezier control values
are dimensionless; previous parameter-only passes did not prove physical
contour accuracy. Sleeve and hood cases currently exceed their stated limits.
`GARMENTCODE_CONTOUR_AUDIT=1 sh Tests/NativePattern/run.sh` reports every sampled
contour mismatch for diagnosis, but is explicitly not a passing acceptance run.

`--neckline-variants` generates 14 combined parameter cases across both upper
programs and all seven neckline styles (negative width, front/back depth,
angles, Bezier controls and flipped curves). `--body-dependencies` captures
the complete upstream body dictionary after ten consecutive input edits;
Swift compares each value to 1e-10, including a zero shoulder angle.

The `--asymmetric-components` oracle mode adds ten Shirt/FittedShirt cases:
single-sided CuffBand, CuffSkirt, CuffBandSkirt on either side, and a left
strapless selection (ignored by upstream for non-fitted Shirt). Tests preserve
the `sl_left_`/`sl_right_` cuff panels and their stitches during half assembly.
Sleeved cases use 0.15 cm tolerance; strapless selections use 0.01 cm.
Oracle generation verifies the fixed upstream HEAD and rejects changed sources,
except an optional final newline in the SIGGRAPH SVG, verified byte-for-byte.

Run from the repository root:

```sh
sh Tests/NativePattern/run.sh
```

This compiles the Foundation-only model without launching Xcode or Unity, using a
fresh temporary module cache. It compares generated default geometry against
fixtures produced by the pinned GarmentCode checkout for circle, asymmetric-circle,
two-panel and many-panel skirts, their arc/cut variants, both waistband styles,
and supported circle/two-panel/many-panel waistband combinations, including
variable panel counts and curved panel edges. It compares generated Swift
panels and stitches against official JSON at 0.01 cm tolerance for Pants,
Shirt/FittedShirt, PencilSkirt, GodetSkirt and the SkirtLevels base/tier matrix.
Every SkirtLevels base style is also compared with both waistband styles.
The SIGGRAPH logo cutout uses a bundled, commit-pinned representation of the
official SVG curves. Default, wider/narrower body and slit combinations pass
generated geometry and stitch comparison with the upstream JSON, including
the native dispatcher route. The Sun cutout passes side-slit boundary and
skip cases; both decorative cuts also pass SkirtLevels and GodetSkirt nesting.
The former approximate generator and its private JSON model have been removed;
this suite now exercises the GarmentCode-native path only.

The same run also decodes the pinned upstream parameter catalog and T-shirt
JSON fixture, checks body-derived formulas, verifies circle-arc midpoint/length
against `svgpathtools` oracle values for all SVG arc-flag combinations, checks
Bezier/circle subdivision, interface edge matching, and round-trips panel
vertices, curvature, and stitch markers through the official pattern envelope.

Passing confirms only the named fixtures and geometry semantics. The active UI
now uses the upstream parameter catalog and routes supported choices to Swift
ports, with unsupported programs rejected instead of falling back to the old
approximation. Currently dispatched programs are Shirt, FittedShirt,
SkirtCircle, AsymmSkirtCircle, Skirt2, SkirtManyPanels, StraightWB, FittedWB,
Pants, PencilSkirt, GodetSkirt and SkirtLevels. The named fixtures cover the tested waistband combinations,
default/varied Pants and all cuff types, PencilSkirt and slit variants, plus
default/varied GodetSkirt and the named SkirtLevels base/tier matrix. All three
Pants cuff types also pass their official fixtures at 0.01 cm
tolerance for panel topology, edge geometry, curvature, and stitch references.
The Swift tangent fitter now uses a port of SciPy's Wolfe-1/MINPACK line search,
matching the upstream BFGS behavior on the shortened-leg cases. The PencilSkirt
Sun cutout passes its official fixture at 0.01 cm. Both Shirt and FittedShirt
pass their default torso, all seven official neckline types, all three
sleeveless armhole shapes, their default asymmetric variants, Turtle,
SimpleLapel and Hood2Panels collar components; SimpleLapel also passes its standing-back and
VNeckHalf-front variants for both upper programs. Shirt also passes a
width/length/flare variant, and
FittedShirt passes the strapless variant. Named upper/lower golden cases now
cover Shirt with two-panel, circle, asymmetric-circle, godet, levels,
many-panel skirt and Pants, plus FittedShirt with PencilSkirt. Named
upper/waistband/lower cases cover both waistband styles and Pants;
upper/waistband-only cases cover default, asymmetric and strapless tops. The PencilSkirt
non-default parameter combinations beyond the named fixtures and broader
component combinations remain incomplete. This is not a complete GarmentCode replacement
or a pattern-cutting certification. All four PencilSkirt slit parameters
(front, back, left, right), individually and together, have pinned official
fixtures and pass at 0.01 cm tolerance.

The `meta-grid-defaults.json` oracle contains every non-empty choice in the
3 × 3 × 9 upper/waistband/bottom default-parameter grid (80 patterns). The
Swift dispatcher matches each at 0.15 cm maximum numeric tolerance with exact
panel topology, edge semantics and stitch references. This caught and fixed
the formerly missing pants + waistband route. The grid is a default-parameter
coverage check, not proof for arbitrary parameter combinations.

The same 80 selections also pass with upstream `mean_female.yaml`, stored with
the body inputs in `meta-grid-female.json`. This second body profile activates
front waist darts that the default mean-all body does not need. It exposed and
fixed omitted front-pants dart stitches and the order of multi-edge front waist
interfaces on pants and pencil-skirt-based components. Together the two grids
cover 160 official patterns, retaining exact stitch and topology comparisons.

`fitted-shirt-undarted-back.json` covers a body whose back waist is wider than
its back bust width. The back panel follows the upstream no-dart branch rather
than rejecting the body. Torso, strapless, sleeved, upper + skirt and upper +
waistband variants pass official topology/stitch comparisons; numeric tolerances
are 0.01 cm, or 0.15 cm for the sleeved case.

PencilSkirt flare values 0.8 and 1.2 verify the total-hip-circumference flare
formula and upstream two-stage integer pivot normalization at 0.01 cm.
Three combined flare/rise/hem-angle fixtures additionally verify curved side
edges. These exposed the BFGS line search's previous-objective state: Swift now
carries it between iterations and uses SciPy's infinity-norm stopping test.

Attached sleeves for Shirt and FittedShirt pass official JSON comparisons,
including exact panel topology and stitch references. The default numeric
tolerances are 0.035 cm and 0.08 cm respectively. Sampled sleeve length,
width, angle, opening direction, all three cuff types, connection ruffles and
standing shoulders also pass against their pinned official fixtures, with
variant tolerances from 0.06 cm to 0.15 cm. Swift's native L-BFGS implementation
reaches slightly different control points from SciPy. The sleeve path uses
length based Bezier subdivision and the upstream 0.2 cm opening redistribution
threshold. Untested sleeve parameter combinations remain outside this evidence.
Hood2Panels passes the Shirt and FittedShirt official goldens plus a varied
hood length/depth fixture at 0.04 cm numeric tolerance with exact panel
topology and stitch references. The geometry layer also contains a two-edge
`cut_corner` projection primitive;
its broad curved-edge parameter space is not yet golden-verified.
SimpleLapel also passes an official back `VNeckHalf` input fixture for both
upper programs; upstream overrides that requested back shape to its circular
projection while constructing the collar.

The script leaves its named temporary binary/cache directory in `/private/tmp`;
no repository artifacts are overwritten.
`GenerateOfficialGoldens.py --upper-variants` creates only the extended upper
fixtures and leaves the existing golden files untouched.
