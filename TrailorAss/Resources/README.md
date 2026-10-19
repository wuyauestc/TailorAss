# GarmentCode sample fixture

`GarmentCodeTShirtSample.json` is an unmodified sewing-pattern specification generated from the official GarmentCode repository at commit `d449629` using:

- `assets/garment_programs/meta_garment.py` / `MetaGarment`
- `assets/design_params/t-shirt.yaml`
- `assets/bodies/mean_all.yaml`
- `assembly()` followed by `serialize(with_3d=False, with_printable=True)`

The fixture was used to verify the app's JSON decoder and 2D viewer. It contains 8 panels and 16 stitch pairs, with line, circular-arc, and cubic-Bezier edges. During fixture creation only CairoSVG's PNG/PDF conversion calls were stubbed because the development Mac lacks the native Cairo library; the upstream JSON and SVG generation paths were otherwise used. The fixture is for preview/testing, not a professionally validated production pattern.

GarmentCode is distributed under the MIT License; its upstream source and license are available at <https://github.com/maria-korosteleva/GarmentCode>.
