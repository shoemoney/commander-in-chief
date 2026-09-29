# Blender print-art validation

September 7, 2026 — Blender 5.2.1 LTS, build `9e2066aef7ef`.

Validated the existing store-art layouts without changing their artwork, title,
or source scenes. These are illustrated promotional images, not gameplay.

## Evidence

All nine authored layouts opened in separate fresh Blender processes and
passed `tools/verify_steam_media.py`:

- header, main, small, and vertical capsules;
- library capsule, hero, and transparent logo;
- promotional card and transparent overlay.

For each file the verifier checked visible-scene font/image packing, finite
transforms, camera-relative geometry bounds, full render resolution, output
dimensions, nonblank pixels, and the expected opaque/transparent alpha behavior.
It redirected font/image paths to nonexistent files **in memory**, then rendered
from the packed dependencies. Source `.blend` files were not modified.

Fresh renders matched the existing reference images within the verifier's
one-8-bit-channel-step limit. The header matched exactly. The threshold is a
reproduction check, not an art-quality score. A negative control using the small
capsule image as the header reference failed with exit code 1 and a dimension
mismatch report.

The Blender Agent Studio deterministic inspector also passed the header's
geometry hard gates: no invalid vertices, degenerate faces, or missing material
assignments. Its open rectangle edges are intentional print planes, not broken
solid meshes. The title uses font objects; a mesh-only triangle count does not
describe its full evaluated geometry.

Opened and visually inspected the original header and fresh logo, small capsule,
and vertical capsule for legible text and clipping. The remaining layouts were
re-rendered and compared numerically, not independently visually approved.

## Local artifacts

- Sources and reference PNGs: `build/steam-media/deliverables/`.
- Header metrics: `build/steam-media/validation/header-metrics.json`.
- Fresh header: `build/steam-media/validation/header-fresh/`.
- Other fresh renders/reports: `build/steam-media/validation/<layout>-fresh/`.
- Negative control: `build/steam-media/validation/negative-mismatched-reference/`.

Outputs remain ignored build artifacts. The verifier and this evidence record
are source files; no store upload, publication, or approval was performed.

## Repeat

Run from the repository root. Use a new output directory; existing evidence is
never overwritten by the verifier. `--python-exit-code 1` is required so a Python
failure cannot masquerade as a successful Blender exit.

```sh
rtk proxy /Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --python-exit-code 1 \
  --python tools/verify_steam_media.py -- \
  --input build/steam-media/deliverables/header_capsule.blend \
  --reference build/steam-media/deliverables/header_capsule.png \
  --output build/steam-media/validation/header-repeat
```

This checker is scoped to these flat authored print layouts with direct texture
nodes. It is not a general recursive material-dependency scanner. GLB roundtrip,
studio multiview, rigging, and animation checks are not applicable to this PNG
deliverable. No conclusion is drawn about current store specification compliance,
licenses, disclosures, external account approval, or audience response.
