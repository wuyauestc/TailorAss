# Joint-solver experimental fabric presets

`GarmentCodeJointFabric` supplies SI constitutive coefficients separately from the legacy distance-compliance presets. Density remains paired with the original selected source preset. These values are numerical experiments; they are not measurements of silk, cotton, denim or any real fabric.

| Preset | Density kg/m² | Membrane μ N/m | Membrane λ N/m | Hinge kb N·m | Sew c m/N |
|---|---:|---:|---:|---:|---:|
| soft | .12 | 155 | 85 | .00005 | .00000001 |
| medium | .18 | 310 | 170 | .0002 | .00000001 |
| firm | .28 | 620 | 340 | .0008 | .00000001 |

μ/λ control the existing 3×2 membrane energy; kb multiplies the existing angular internal-edge energy. They do not reinterpret legacy stretch, shear or two-hop bend compliance as continuum moduli. Density multiplies original source triangle area and stays in kilograms in the actual joint inertial term. Increasing stiffness and density together does not imply a simple final drape ratio.

The medium material factory is compared bit for bit with the actual existing `JointSimulation.swift` regression's `Materials(...)` expression. The runner extracts that frozen expression directly; it does not maintain a second baseline parameter table. All 15 SI scalars and both physical raw-Hessian modes are included.

Source settings keep the selected density preset, standard anatomical mannequin, surface/body collision selection and default .04m target mesh edge. The resource-directory and explicit target-edge override are forwarded. Factory output does not load an avatar or certify arbitrary caller-supplied target edges; the existing native preparation validates them. It adds no legacy source-strain clamp. Body and self feasibility gaps/barriers remain numerical settings shared by all presets, not measured fabric thickness: body floor .5mm plus2mm activation, self floor0 plus.5mm activation, principal stretch interval(.93,1.07).

## Independent component checks

```sh
python3 Tests/NativePattern/run-joint-fabric.py \
  --package-proof /path/to/frozen/native/package/proof
```

The runner takes a unique complete Swift-source/fixture snapshot and links the already verified native package archive. It compiles strict Swift 5 Release with MainActor defaults, complete concurrency and warnings as errors, without rebuilding C++ or running cloth simulation.

The tests exercise actual energies and derivatives rather than only checking the table:

- A .5m² patch under shear γ=.02 has analytic membrane energy `A μ γ²/2`, directional derivative `A μ γ` and second derivative `A μ`; finite differences also check the computed force response.
- A separate 2% uniaxial stretch checks both μ and λ against the independent logarithmic Neo-Hookean density.
- A real .35-radian fold about the patch's actual shared edge checks angular energy `kb × 7.5 × θ²` and a finite-difference directional derivative. The fold energy changes by4 between adjacent presets; membrane response changes by2.
- A tenfold change of all lengths produces100-fold area mass and membrane energy, unchanged same-angle hinge energy and inverse-length bending force. This checks SI dimensions without changing coefficients.
- A rigid1mm translation at the existing dt produces the analytic mass-weighted inertial energy and per-vertex force in the actual `JointObjective.Frame`.
- The complete unchanged canonical Circle+StraightWB source has2,000 vertices,3,472 triangles and4,948 internal hinges. All original source areas contribute to masses. Affine shear agrees with its independently summed source area; a prescribed smooth curvature produces nonzero real hinge forces.
- The activated principal feasibility barrier's energy and gradient remain bitwise identical across presets.

All source probes are prescribed configurations. Passing them establishes the factory's units, bindings and isolated constitutive responses. It does not establish cloth settling, final garment sensitivity, personal fit, manufacturing accuracy or material calibration. The test changes no source/rest lengths, mass formula, pins, collision floor or solver acceptance threshold.
