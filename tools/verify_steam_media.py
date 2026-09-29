"""Fresh-process Blender verification for the existing flat print layouts.

Run Blender --background --factory-startup --python this_file -- --input FILE.blend
--reference FILE.png --output NEW_DIRECTORY. Never modifies the source .blend.
This verifies reproducibility and packaging, not Steam approval or art quality.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy
import numpy as np
from bpy_extras.object_utils import world_to_camera_view
from mathutils import Vector


def hero_contract(scene, issues):
    """Project the inspected source face box through the actual mesh UVs."""
    required = ("hero_face_source_box", "hero_source_size", "hero_source_sha256")
    if any(key not in scene for key in required):
        issues.append("hero lacks source-bound critical-content annotations")
        return {}
    if (scene.render.resolution_x, scene.render.resolution_y) != (3840, 1240):
        issues.append("hero must render at 3840x1240")
    if any(obj.type == "FONT" and not obj.hide_render for obj in scene.objects):
        issues.append("hero must not contain title text")
    obj = scene.objects.get("CIC_Background")
    if obj is None or obj.type != "MESH" or not obj.data.uv_layers.active:
        issues.append("hero artwork mesh/UV mapping missing")
        return {}
    image_nodes = [node for slot in obj.material_slots if slot.material
                   for node in slot.material.node_tree.nodes
                   if node.type == "TEX_IMAGE" and node.image]
    if len(image_nodes) != 1:
        issues.append("hero verifier requires one directly mapped source image")
        return {}
    image = image_nodes[0].image
    if not image.packed_file or hashlib.sha256(bytes(image.packed_file.data)).hexdigest() != scene["hero_source_sha256"]:
        issues.append("hero packed illustration differs from the inspected source")
    sw, sh = scene["hero_source_size"]
    if list(image.size) != [sw, sh]:
        issues.append("hero source dimensions differ from annotations")
    x0, y0, x1, y1 = scene["hero_face_source_box"]
    obj.data.calc_loop_triangles()
    uv = obj.data.uv_layers.active.data
    projected = []
    for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1)):
        target = np.array([x / sw, 1-y / sh])
        for tri in obj.data.loop_triangles:
            uvs = np.array([tuple(uv[i].uv) for i in tri.loops])
            matrix = np.column_stack((uvs[0]-uvs[2], uvs[1]-uvs[2]))
            if abs(np.linalg.det(matrix)) < 1e-12:
                continue
            a, b = np.linalg.solve(matrix, target-uvs[2])
            weights = (a, b, 1-a-b)
            if min(weights) < -1e-5:
                continue
            point = sum((obj.data.vertices[i].co * float(w)
                         for i, w in zip(tri.vertices, weights)), Vector())
            p = world_to_camera_view(scene, scene.camera, obj.matrix_world @ point)
            projected.append((p.x*3840, (1-p.y)*1240))
            break
    if len(projected) != 4:
        issues.append("critical face/hair box is outside the artwork UV mapping")
        return {}
    box = [min(p[0] for p in projected), min(p[1] for p in projected),
           max(p[0] for p in projected), max(p[1] for p in projected)]
    # Conservative interpretation: use 860x380 even on the full-size asset.
    if box[0] < 1490 or box[1] < 430 or box[2] > 2350 or box[3] > 810:
        issues.append("critical face/hair content escapes the protected center")
    scale_x, scale_y = (box[2]-box[0])/(x1-x0), (box[3]-box[1])/(y1-y0)
    if abs(scale_x/scale_y-1) > .001:
        issues.append("hero character is stretched instead of uniformly scaled")
    return {"face_box_px": box, "safe_box_px": [1490, 430, 2350, 810],
            "source_sha256": scene["hero_source_sha256"],
            "annotation_scope": "manually inspected hair/face bounding box, not automatic face recognition"}


def verify(source, reference, output):
    source, reference, output = map(lambda p: Path(p).resolve(), (source, reference, output))
    if output.exists():
        raise ValueError("Use a new output directory; previous evidence is not overwritten")
    output.mkdir(parents=True)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    issues, dependencies, bounds = [], [], {}
    if scene.name != "CIC_SteamMedia" or scene.camera is None:
        raise ValueError("Expected the authored CIC_SteamMedia scene and camera")
    if scene.render.resolution_percentage != 100:
        issues.append("render resolution percentage is not 100")
    bpy.context.view_layer.update()
    hero = hero_contract(scene, issues) if source.stem == "library_hero" else None

    # Check only visible scene dependencies. The saved .blend can also contain
    # unused factory-startup datablocks; those are not deliverable dependencies.
    images, fonts = set(), set()
    for obj in scene.objects:
        if obj.hide_render:
            continue
        if not all(np.isfinite(v) for row in obj.matrix_world for v in row):
            issues.append(f"nonfinite transform: {obj.name}")
        if obj.type == "FONT":
            for attr in ("font", "font_bold", "font_italic", "font_bold_italic"):
                font = getattr(obj.data, attr)
                if font and font.filepath != "<builtin>":
                    fonts.add(font)
        for slot in obj.material_slots:
            mat = slot.material
            if mat and mat.use_nodes:
                for node in mat.node_tree.nodes:
                    if node.type == "TEX_IMAGE" and node.image:
                        images.add(node.image)
        if obj.type in {"MESH", "FONT"}:
            projected = [world_to_camera_view(scene, scene.camera, obj.matrix_world @ Vector(p))
                         for p in obj.bound_box]
            extent = [min(p.x for p in projected), min(p.y for p in projected),
                      max(p.x for p in projected), max(p.y for p in projected)]
            bounds[obj.name] = extent
            if min(p.z for p in projected) <= 0 or min(extent[:2]) < -0.001 or max(extent[2:]) > 1.001:
                issues.append(f"geometry outside the print canvas: {obj.name}")

    for kind, items in (("image", images), ("font", fonts)):
        for item in items:
            packed = bool(item.packed_file)
            dependencies.append({"kind": kind, "name": item.name, "packed": packed})
            if not packed:
                issues.append(f"unpacked {kind}: {item.name}")
            # Remove source-machine fallback in memory. Packed data must suffice.
            item.filepath = str(output / "absent-source-files" / item.name)
    report = {"source": str(source), "reference": str(reference),
              "blender": bpy.app.version_string, "dependencies": dependencies,
              "projected_bounds": bounds, "issues": issues,
              "scope": "authored 2D print camera; GLB/multiview/animation not applicable"}
    if hero is not None:
        report["hero_contract"] = hero
    if not issues:
        scene.render.filepath = str(output / "fresh-render.png")
        bpy.ops.render.render(write_still=True)
        actual = bpy.data.images.load(scene.render.filepath, check_existing=False)
        expected = bpy.data.images.load(str(reference), check_existing=False)
        size = list(actual.size)
        report["size"] = size
        if size != list(expected.size):
            issues.append("fresh render and reference dimensions disagree")
        else:
            a = np.empty(len(actual.pixels), dtype=np.float32)
            b = np.empty(len(expected.pixels), dtype=np.float32)
            actual.pixels.foreach_get(a)
            expected.pixels.foreach_get(b)
            difference = np.abs(a - b)
            report["max_channel_difference"] = float(difference.max())
            report["mean_channel_difference"] = float(difference.mean())
            report["alpha_range"] = [float(a[3::4].min()), float(a[3::4].max())]
            if not np.isfinite(a).all() or np.ptp(a[0::4]) == 0:
                issues.append("nonfinite or flat fresh render")
            # Same Blender/scene/sampling should reproduce quantized PNG pixels.
            # Allow one encoded 8-bit channel step, not a visual-quality score.
            if difference.max() > 1.0 / 255.0 + 1e-6:
                issues.append("fresh render differs from reference by more than one channel step")
            transparent = source.stem in {"library_logo", "promo_overlay"}
            if transparent and not (a[3::4].min() == 0 and a[3::4].max() > 0):
                issues.append("transparent overlay lacks both clear and visible pixels")
            if not transparent and a[3::4].min() < 1:
                issues.append("opaque capsule contains transparent pixels")
    report["passed"] = not issues
    (output / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("STEAM MEDIA VERIFY", "PASS" if not issues else "FAIL", source.name, issues, flush=True)
    if issues:
        raise RuntimeError("; ".join(issues))


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--reference", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    verify(args.input, args.reference, args.output)
