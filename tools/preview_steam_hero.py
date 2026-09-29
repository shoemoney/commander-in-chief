"""Fresh-process Blender crop/logo previews, not Steam client screenshots."""
import argparse
import json
from pathlib import Path
import sys

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_steam_media import rectangle


def preview(source, logo_path, output):
    source, logo_path, output = map(lambda x: Path(x).resolve(), (source, logo_path, output))
    output.mkdir(parents=True, exist_ok=False)
    bpy.ops.wm.open_mainfile(filepath=str(source))
    scene = bpy.context.scene
    original_scale = scene.camera.data.ortho_scale
    full_height = original_scale * 1240 / 3840
    image = bpy.data.images.load(str(logo_path))
    mat = bpy.data.materials.new("Preview_Logo")
    mat.use_nodes = True
    n, links = mat.node_tree.nodes, mat.node_tree.links
    n.clear()
    texture = n.new("ShaderNodeTexImage")
    texture.image = image
    emission = n.new("ShaderNodeEmission")
    links.new(texture.outputs["Color"], emission.inputs["Color"])
    transparent = n.new("ShaderNodeBsdfTransparent")
    mix = n.new("ShaderNodeMixShader")
    links.new(texture.outputs["Alpha"], mix.inputs[0])
    links.new(transparent.outputs[0], mix.inputs[1])
    links.new(emission.outputs[0], mix.inputs[2])
    out = n.new("ShaderNodeOutputMaterial")
    links.new(mix.outputs[0], out.inputs["Surface"])
    logo = rectangle(scene, "Preview_Logo", 1, 1, 0, 0, 0, mat)
    receipts = []
    for name, width, height, protected_only in [
            ("wide-logo", 1920, 620, False),
            ("narrow-logo", 860, 380, False),
            ("protected-center", 860, 380, True)]:
        scene.render.resolution_x, scene.render.resolution_y = width, height
        scene.camera.data.ortho_scale = original_scale * width / 3840 if protected_only else full_height * width / height
        logo.hide_render = protected_only
        if not protected_only:
            canvas_w = scene.camera.data.ortho_scale
            logo_w = canvas_w * .30
            logo_h = logo_w * image.size[1] / image.size[0]
            logo.scale = (logo_w, logo_h, 1)
            logo.location.x = -canvas_w/2 + canvas_w*.035 + logo_w/2
            logo.location.y = -full_height/2 + full_height*.07 + logo_h/2
        scene.render.filepath = str(output / (name + ".png"))
        bpy.context.view_layer.update()
        bpy.ops.render.render(write_still=True)
        receipts.append({"name": name, "size": [width, height],
                         "orthographic_scale": scene.camera.data.ortho_scale,
                         "logo": not protected_only})
    (output / "preview-manifest.json").write_text(json.dumps({
        "source": str(source), "logo": str(logo_path),
        "scope": "local composition simulations, not Steam client verification",
        "renders": receipts}, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True)
    parser.add_argument("--logo", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    preview(args.input, args.logo, args.output)
