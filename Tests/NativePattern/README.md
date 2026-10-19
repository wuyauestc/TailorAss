# Legacy native generator structural regression

Run from the repository root:

```sh
sh Tests/NativePattern/run.sh
```

This compiles the Foundation-only model without launching Xcode or Unity, using a
fresh temporary module cache. It exercises all 80 non-empty default combinations
(3 upper choices including none × 3 waistbands × 9 bottoms − empty), JSON round
trips, edge labels, and selected invalid input/reference rejection.

Passing does **not** mean that the garments match GarmentCode, assemble completely,
fit a body, or are ready to cut. The current generator does not model all required
seams, curves, mirror/fold semantics or fit constraints. Missing seams cannot be
certified by checking the seams that happen to exist. See the non-3D acceptance
matrix in `M7_GarmentCode_非3D验收清单.md`.

The script leaves its named temporary binary/cache directory in `/private/tmp`;
no repository artifacts are overwritten.
