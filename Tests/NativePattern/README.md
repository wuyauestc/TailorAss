# GarmentCode native pattern acceptance

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
