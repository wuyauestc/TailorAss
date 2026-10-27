# Native lower-garment initial placement

This is an initial construction placement, not a sewn, collision-free, fitted,
or accepted physical garment. It retains every source panel and mesh vertex.
No supports, masses, rest lengths, sewing targets or quality gates change.

`GarmentCodeLowerPlacement.prepare(document:body:design:...)` accepts all eight
native lower styles, their real child panels, and either optional waistband.
It rejects upper/lower outfits as a complete unsupported document; it never
silently removes the upper part. A later whole-outfit mapper must compose those
components together.

Before producing a map it checks the fixed native provenance, exact body and
design metadata, and canonical SHA-256 against complete native regeneration.
Every real source panel must have a matching recipe. Each returned panel owns
its unchanged source mesh, explicit transform, transformed positions and normal.
Imported documents use `GarmentCodePanelPlacement` instead.

## Fixed source and coordinate convention

The source is GarmentCode commit
`d449629979028123a5c4dc9e732a2ec19b7fce31`. The local research source was extracted
read-only from cached Git objects; its extraction record is
`/private/tmp/TailorAssAssemblyResearch/extraction.json`.

Relevant upstream source files:

- `assets/garment_programs/pants.py`: `PantPanel`, `PantsHalf`, `Pants`.
- `skirt_paneled.py`: `SkirtPanel`, `FittedSkirtPanel`, `Skirt2`,
  `SkirtManyPanels`, `PencilSkirt`.
- `circle_skirt.py`: `CircleArcPanel`, `SkirtCircle`, `AsymmSkirtCircle`.
- `bands.py`: both waistbands and all three cuff types.
- `godet.py`, `skirt_levels.py`, `meta_garment.py`.
- `pygarment/garmentcode/panel.py`: pivot truncation, mirror, serialization.
- `base.py`: `place_by_interface`, `place_below`.
- `component.py`, `operators.py`: component pivot, rotation and distribution.

All construction formulas below use centimetres. Final mesh positions use
metres and have `_waist_level / 100` subtracted from Y. The final rotation is
the actual meshgen `Rz * Ry * Rx`, including the original paper winding normal.
No extra back-panel 180-degree turn is invented.

An upstream panel first subtracts integer pivots, truncating toward zero. At
serialization it changes translation by the **full** first vertex `p0`, while
subtracting only `int(p0)` from paper coordinates. For serialized first point
`q0`, source point `q`, and the serialized world translation `a`:

```
pre-assembly point used by component bbox operations = a + R * (q - q0)
final meshgen point                                = a + R * q
```

These differ when `q0` is fractional. The implementation preserves that pinned
upstream convention; it does not subtract the integer pivot twice or silently
remove the fractional serialization offset.

## Recipes

### Pants and real cuffs

Let `D = pants.rise * hips_line`, `C = crotch_hip_diff`, and
`L = (pants.length - actualCuffRatio) * _leg_length`. The cuff ratio is clipped
to the upstream minimum pants length before conversion to centimetres.

For each right panel, with its own quarter-hip `H` and crotch extension `E`:

```
flare = leg_circ * (pants.flare - 1) / 4
p0 = [-flare - int(H + E), -int(L - C)]
anchor = [-0.5 + p0.x, waist_level - hiplineExtension*D - C + p0.y, z]
front: hiplineExtension=1,   z=25
back:  hiplineExtension=1.1, z=-20
```

Front extension is front quarter-hip divided by four; back extension is the
remaining `(leg_circ - hips/2 + 5) * pants.width`. Left source XY is already
mirrored. Its anchor X is the negative right X; there is no second reflection.

`CuffBand`, `CuffSkirt` and `CuffBandSkirt` retain both front/back pieces on
both legs. Constructors reproduce top-centre integer pivots and centring.
The combined cuff skirt is first placed below its band with the upstream
2 cm bbox gap. The entire cuff then uses the original pants bottom interface,
5 cm gap, and `alignment='left'`, which the upstream implementation explicitly
defines as **maximum X to maximum X**. The whole completed half is mirrored.
Short pants with an angled hem use their actual hem edge, not a horizontal
replacement.

### Skirt2 and PencilSkirt

Skirt2 uses its actual source width and length, including waist ruffles,
flare and bottom cuts. Its anchor is
`[-int(bottomWidth/2), waist_level-int(length), z]`, with front/back Z `25/-20`.

For PencilSkirt, with panel quarter-hip `H`, `lowWidth = hips*(flare-1)/4+H`,
`angleShift = tan(low_angle)*lowWidth`, and the panel's extended hip depth:

```
anchor.x = H - lowWidth - int(H)
anchor.y = waist_level + angleShift
           - int(max(length + extendedHipDepth, abs(angleShift)))
anchor.z = 25 front, -20 back
```

Front/back depth factors are `1/1.05`. The source's real darts, slits and
decorative cut geometry remain present.

### Circular and multi-panel skirts

Circle and asymmetric circle panels use the actual unmodified top chord:
`anchor = [-topChord/2, waist_level, +15/-15]`. Different hem lengths, side
lengths and cuts remain part of the source.

For ManyPanels, `W = adjustedWaist/n`, `L` is the original rise-plus-leg-length
formula, `B = W*(1+suns*L*2*pi/adjustedWaist)`, and `F=(B-W)/2`:

```
distance = actual curved hem length / (2*tan(pi/n))
baseYAngle = -90 + atan2(W/2, distance)
p0 = [-int(F), -int(L), 0]
panel i rotation = baseYAngle + i*360/n about Y
panel i anchor = Ry(i*360/n)*[-distance, waist_level, 0]
                 + Ry(baseYAngle+i*360/n)*p0
```

Equivalent Euler triples are compared by independent basis vectors, since
SciPy may serialize a pure Y rotation using two 180-degree Euler components.

### Godet inserts

Base placement follows its true Skirt2 or PencilSkirt recipe. As upstream does,
the insert placement uses the base panel's **pre-cut** 3D bbox. For `N` inserts
per panel, width `W`, depth `D`, and index `i`:

```
anchor.x = baseBBox.center.x - N*W/2 + i*W
anchor.y = baseBBox.min.y + D - int(D)
anchor.z = basePanel.z + sign(basePanel.z)*5
```

The real post-cut base panels and every actual insert are returned. The source
check verifies the upstream slit-suppressed base geometry, including when the
original design inputs retain nonzero ordinary Pencil slit values.

### SkirtLevels

The original length split is preserved:

```
total = levels.length * leg_length
baseLength = total*base_length_frac + hips_line*levels.rise
tierLength = total*(1-base_length_frac)/num_levels
```

The next body's waist and back waist are the previous real hem lengths times
`level_ruffle`. Each tier uses its actual selected skirt type and is rotated by
`-basePencil.low_angle` about its own component bbox top-centre pivot. Then its
real top interface is placed against the previous real bottom interface with
the original 5 cm gap direction. All tiers stay in the returned map.

### Waistband/Meta placement

Both StraightWB and FittedWB use the lower component's actual rise. The complete
lower component is moved using the original top/bottom interface bbox centres,
its own whole-component bbox, and normalized gap direction. This preserves
small asymmetric X shifts; it does not reduce the operation to a guessed Y
offset. Curved bboxes use nine internal vertices; Beziers sample by arc length,
matching the actual upstream implementation rather than renderer bounds.

## Reproducible checks

Run:

```
Tests/NativePattern/run-lower-placement.sh
```

The script copies every dependency, resource and fixture before compilation,
checks the catalogue's fixed source commit, and writes exact SHA-256 input
manifests. `GenerateOfficialGoldens.py`, which enforces the upstream Git commit,
is included in that snapshot. No Python clothing runtime is needed for the
Swift regression.

Initial evidence was retained separately:

- 136 official panels: `/private/tmp/TailorAssLowerPlacementTest3.log` and its
  immutable compilation snapshot recorded on the first log line.
- Expanded 374 official panels: `/private/tmp/TailorAssLowerPlacementTest5.log`,
  `/private/tmp/TailorAssLowerPlacement/placement-proof-374.json`, and
  `preserved-136-and-374-input-manifests.json` in the same report directory.
- Latest complete run and minimal 2D reproductions:
  `/private/tmp/TailorAssLowerPlacementFinal/`.
- After the two minimal 2D fixes, the unchanged 374-panel placement matrix and
  source-provenance checks passed again in
  `/private/tmp/TailorAssLowerPlacementAfterBranches/`.

The 374-panel matrix includes all eight defaults; all three real cuffs; Pants
length/rise/width/flare changes; Pencil flare, low rise, positive/negative hem
angles, Sun and SIGGRAPH cuts; curved multi-panels; varied Godet count/width/
depth; all 12 base/tier combinations; varied level count/ruffle/rise; and all
lower/no-waistband/StraightWB/FittedWB combinations on two actual body fixtures.
Maximum translation error in those runs was `4.768372e-9 m`. Every rotation
basis, full panel set, source mesh position, normal and canonical source hash
is checked. These are placement tolerances, not changes to physical acceptance.

## Two 2D branches exposed and repaired

These were separate paper-generation issues. The initial failing source inputs
and before-fix results remain in `LowerPlacementFinal/known-2d-branches/`.
After-fix results in `LowerPlacementAfterBranches/known-2d-branches/` report
both as resolved. No placement or physical gate was weakened.

1. **Godet + Pencil front slit.** Minimal change: GodetSkirt with PencilSkirt
   base and `pencil-skirt.front_slit=0.2`. Upstream `godet.py:38` passes
   `slit=False`, and `PencilSkirt` forwards zero slit values in that case.
   The native branch previously called `pencilSkirt` without suppressing the
   four slit values: 15 front edges instead of the upstream-suppressed 12.
   It now clears the four values only in a copied base design. Original full
   input provenance remains unchanged, ordinary Pencil slits remain active,
   and the full Godet source now passes placement with nonzero slit inputs.
2. **Pants lower-only waistband rise.** Minimal changes: Pants, FittedWB,
   `pants.rise=0.75`, default `skirt.rise=1`. Upstream MetaGarment passes
   `Lower.get_rise()` to the waistband. The current lower-only native switch
   previously omitted Pants and fell back to skirt.rise. Its top length was
   `84.3338 cm`; the correct pants-rise formula gives `85.29101 cm`.
   The switch now explicitly selects pants.rise. Varying unrelated skirt.rise
   no longer changes either waistband's source geometry.

Long-term regression:

```
Tests/NativePattern/run-lower-branches.sh
```

The checked-in `Fixtures/lower-branch-oracles.json` was generated by the
**unmodified official** `MetaGarment` from the pinned source using NumPy 1.26.4
and SciPy 1.13.1. It records the explicit resolved body input, every upstream
source-file SHA-256, the extraction proof, and the regeneration script hash.
`GenerateLowerBranchGoldens.py` regenerates it from an exact upstream checkout
or the recorded read-only extraction. Regression itself has no dependency on
that checkout or Python clothing packages.

The 25 new full-source cases cover both waistbands, pants rise 0.5/0.75/1,
independent skirt.rise 0.5/1 perturbations, four individual Godet slit inputs,
combined slits with/without both waistbands, and four individual/combined
ordinary Pencil slit inputs. All geometry, source topology/stitch references,
input provenance and complete native placement checks pass. These add 134
source-panel placement comparisons. Maximum geometry/edge-length discrepancy
is `3.180662e-7 cm`, and maximum new placement discrepancy is `2.001483e-16 m`.

The existing full `run-acceptance.sh` suite also passed after the two fixes:
356-case native geometry acceptance plus tangent quality/stability, import,
localization, seams, vector/A4 PDFs, allowances, marks, manufacturing PDFs and
basic-mode checks. Its retained log is
`/private/tmp/TailorAssLowerBranchFullAcceptance.log`.
