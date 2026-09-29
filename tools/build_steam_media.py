"""Reproducible Blender typography/layout for illustrated Steam artwork.

Run in Blender with -- --project <repo> --output <directory>.
This creates a NEW scene, never clears an existing user scene. Outputs are
marketing art, not gameplay screenshots. The flat emission artwork retains the
source colors; title lettering uses matte print colors for thumbnail clarity.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys

import bpy

ENGINE = "CYCLES"
SAMPLES = 16
CANVAS_WIDTH = 16.0
LAYOUTS = {
    "header_capsule": (920, 430),
    "main_capsule": (1232, 706),
    "small_capsule": (462, 174),
    "vertical_capsule": (748, 896),
    "library_capsule": (600, 900),
    "library_hero": (3840, 1240),
    "library_logo": (1280, 540),
    "promo_card": (1920, 1080),
    "promo_overlay": (1920, 1080),
}

# Manually inspected face/hair bounds, tied to the exact panoramic source.
HERO_SOURCE_SHA256 = "7ed9980740cb2bc3eb16c0f25100f504eba29e3a6cb800e48a5b98f67ab035ed"
HERO_FACE_BOX = (1040, 300, 1170, 450)


def hero_background(scene, material, generated):
    """Fit the dedicated panorama without stretching its content."""
    width, height = LAYOUTS["library_hero"]
    source = generated / "library-hero-v3.png"
    if hashlib.sha256(source.read_bytes()).hexdigest() != HERO_SOURCE_SHA256:
        raise ValueError("Hero source changed; re-inspect face bounds before rendering")
    art = bpy.data.images.load(str(source))
    art.pack()
    art_mat = material.copy()
    art_mat.name = "CIC_HeroIllustration"
    art_mat.node_tree.nodes.get("Image Texture").image = art
    obj = rectangle(scene, "CIC_Background", CANVAS_WIDTH,
                    CANVAS_WIDTH * height / width, 0, 0, -1, art_mat)
    crop_h = (art.size[0] / art.size[1]) / (width / height)
    for loop, xy in zip(obj.data.uv_layers.active.data,
                        [(0, .5-crop_h/2), (1, .5-crop_h/2),
                         (1, .5+crop_h/2), (0, .5+crop_h/2)]):
        loop.uv = xy
    scene["hero_face_source_box"] = HERO_FACE_BOX
    scene["hero_source_size"] = tuple(art.size)
    scene["hero_safe_box"] = (1490, 430, 2350, 810)
    scene["hero_source_sha256"] = HERO_SOURCE_SHA256
    return obj


def solid_material(name, color, emission=False):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    if emission:
        shader = nodes.new("ShaderNodeEmission")
        shader.inputs["Color"].default_value = (*color, 1)
    else:
        shader = nodes.new("ShaderNodeBsdfPrincipled")
        shader.inputs["Base Color"].default_value = (*color, 1)
        shader.inputs["Metallic"].default_value = 0.38
        shader.inputs["Roughness"].default_value = 0.34
    material.node_tree.links.new(shader.outputs[0], output.inputs["Surface"])
    return material


def rectangle(scene, name, width, height, x, y, z, material):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([(-width/2, -height/2, 0), (width/2, -height/2, 0),
                     (width/2, height/2, 0), (-width/2, height/2, 0)], [], [(0, 1, 2, 3)])
    uv = mesh.uv_layers.new(name="ArtworkUV")
    for loop, value in zip(uv.data, [(0, 0), (1, 0), (1, 1), (0, 1)]):
        loop.uv = value
    obj = bpy.data.objects.new(name, mesh)
    scene.collection.objects.link(obj)
    obj.location = (x, y, z)
    obj.data.materials.append(material)
    return obj


def title_line(scene, text, font, material, x, y, width, z=0.1):
    curve = bpy.data.curves.new("Title_" + text, "FONT")
    curve.body = text
    curve.font = font
    curve.size = 1
    curve.extrude = 0.015
    curve.bevel_depth = 0.008
    curve.bevel_resolution = 2
    obj = bpy.data.objects.new("Title_" + text, curve)
    scene.collection.objects.link(obj)
    curve.materials.append(material)
    bpy.context.view_layer.update()
    scale = width / max(obj.dimensions.x, 0.001)
    obj.scale = (scale, scale, scale)
    obj.location = (x, y, z)
    return obj


def build(project_root, output_root, generated_root=None, layouts=None):
    project = Path(project_root).resolve()
    output = Path(output_root).resolve()
    generated = Path(generated_root).resolve() if generated_root else output / "generated"
    deliverables = output / "deliverables"
    deliverables.mkdir(parents=True, exist_ok=False)
    scene = bpy.data.scenes.new("CIC_SteamMedia")
    bpy.context.window.scene = scene
    scene.render.engine = ENGINE
    scene.cycles.device = "CPU"
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 4
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.image_settings.color_depth = "8"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.view_settings.exposure = 0
    scene.view_settings.gamma = 1
    scene.world = bpy.data.worlds.new("CIC_World")
    scene.world.use_nodes = True
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.035, 0.04, 0.05, 1)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.3

    camera_data = bpy.data.cameras.new("CIC_Orthographic")
    camera = bpy.data.objects.new("CIC_Orthographic", camera_data)
    scene.collection.objects.link(camera)
    camera.location = (0, 0, 20)
    camera_data.type = "ORTHO"
    camera_data.sensor_fit = "HORIZONTAL"
    camera_data.ortho_scale = CANVAS_WIDTH
    scene.camera = camera
    for name, loc, power, color in [
        ("CIC_Key", (-4, 5, 8), 1500, (1, 0.83, 0.55)),
        ("CIC_Fill", (5, -2, 6), 800, (0.65, 0.79, 1))]:
        data = bpy.data.lights.new(name, "AREA")
        data.energy = power
        data.shape = "DISK"
        data.size = 8
        data.color = color
        obj = bpy.data.objects.new(name, data)
        scene.collection.objects.link(obj)
        obj.location = loc

    font = bpy.data.fonts.load(str(generated / "Anton-Regular.ttf"))
    art = bpy.data.images.load(str(generated / "keyart-fal-v2.png"))
    art.pack()
    font.pack()
    artwork = bpy.data.materials.new("CIC_IllustratedBackground")
    artwork.use_nodes = True
    nodes = artwork.node_tree.nodes
    nodes.clear()
    shader = nodes.new("ShaderNodeEmission")
    texture = nodes.new("ShaderNodeTexImage")
    texture.image = art
    texture.interpolation = "Linear"
    out = nodes.new("ShaderNodeOutputMaterial")
    artwork.node_tree.links.new(texture.outputs["Color"], shader.inputs["Color"])
    artwork.node_tree.links.new(shader.outputs[0], out.inputs["Surface"])
    gold = solid_material("CIC_PrintGold", (0.88, 0.50, 0.13), True)
    ivory = solid_material("CIC_WarmIvory", (0.92, 0.85, 0.68), True)
    ink = solid_material("CIC_PrintInk", (0.012, 0.015, 0.018), True)
    red = solid_material("CIC_RedRule", (0.48, 0.035, 0.025), True)
    accent = solid_material("CIC_GoldRule", (0.8, 0.45, 0.11), True)

    manifest = {"blender": bpy.app.version_string, "engine": ENGINE, "samples": SAMPLES,
                "device": "CPU", "color_management": "Standard / None / exposure 0 / gamma 1",
                "content": "illustrated promotional art; not gameplay", "layouts": {}}
    for layout in layouts or LAYOUTS:
        width, height = LAYOUTS[layout]
        for key in list(scene.keys()):
            if key.startswith("hero_"):
                del scene[key]
        for obj in list(scene.objects):
            if obj.type not in ("CAMERA", "LIGHT"):
                bpy.data.objects.remove(obj, do_unlink=True)
        scene.render.resolution_x = width
        scene.render.resolution_y = height
        scene.render.film_transparent = layout in ("library_logo", "promo_overlay")
        canvas_h = CANVAS_WIDTH * height / width
        portrait = height > width
        if layout == "library_hero":
            hero_background(scene, artwork, generated)
        elif layout not in ("library_logo", "promo_overlay"):
            background = rectangle(scene, "CIC_Background", 16, canvas_h, 0, 0, -1, artwork)
            # v2 has deliberate dark side space but unwanted top/bottom bars.
            # Crop only those bars; never stretch the illustrated character.
            source_aspect = art.size[0] / art.size[1]
            crop_h = 0.81
            crop_w = min(1.0, (width / height) * crop_h / source_aspect)
            if crop_w == 1.0:
                crop_h = source_aspect / (width / height)
            center_x = 0.72 if portrait else 0.5
            left = min(max(0, center_x - crop_w / 2), 1 - crop_w)
            for uv, xy in zip(background.data.uv_layers.active.data,
                              [(left, .5-crop_h/2), (left+crop_w, .5-crop_h/2),
                               (left+crop_w, .5+crop_h/2), (left, .5+crop_h/2)]):
                uv.uv = xy

        if layout != "library_hero":
            if portrait:
                title_width, center_y, max_height = 13.6, -canvas_h * .34, canvas_h * .27
                rectangle(scene, "CIC_TitleBacking", 16, canvas_h * .32, 0,
                          -canvas_h * .34, -0.2, ink)
            elif layout in ("small_capsule", "library_logo"):
                title_width, center_y, max_height = 14.0, 0, canvas_h - 1.2
                if layout == "small_capsule":
                    rectangle(scene, "CIC_TitleBacking", 16, canvas_h, 0, 0, -0.2, ink)
            else:
                title_width, center_y, max_height = 7.3, 0, canvas_h - 1.6
            line1 = title_line(scene, "COMMANDER", font, ivory, 0, 0, title_width)
            line2 = title_line(scene, "IN CHIEF", font, gold, 0, 0, title_width)
            bpy.context.view_layer.update()
            gap = .18
            total_height = line1.dimensions.y + line2.dimensions.y + gap
            fit = min(1.0, max_height / total_height)
            for obj in (line1, line2):
                obj.scale *= fit
            title_width *= fit
            gap *= fit
            bpy.context.view_layer.update()
            total_height = line1.dimensions.y + line2.dimensions.y + gap
            x = -title_width/2 if portrait or layout in ("small_capsule", "library_logo") else -7
            # Place using evaluated glyph bounds, not baseline guesses; shorter
            # words at the same width are taller and used to overlap COMMANDER.
            from mathutils import Vector
            def bounds(obj):
                return [obj.matrix_world @ Vector(v) for v in obj.bound_box]
            bottom = center_y - total_height/2
            for obj, target_bottom in ((line2, bottom),
                                        (line1, bottom + line2.dimensions.y + gap)):
                pts = bounds(obj)
                obj.location.x += x - min(p.x for p in pts)
                obj.location.y += target_bottom - min(p.y for p in pts)
            rectangle(scene, "CIC_UpperRule", title_width, .065,
                      x + title_width/2, center_y + total_height/2 + .25, .05, accent)
            rectangle(scene, "CIC_LowerRule", title_width, .11,
                      x + title_width/2, bottom - .25, .05, red)
        path = deliverables / (layout + ".png")
        scene.render.filepath = str(path)
        # Retain each layout as a self-contained, directly renderable source.
        bpy.ops.wm.save_as_mainfile(filepath=str(deliverables / (layout + ".blend")))
        bpy.ops.render.render(write_still=True)
        manifest["layouts"][layout] = {"size": [width, height], "image": str(path)}
    (deliverables / "render-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("STEAM MEDIA RENDER COMPLETE", flush=True)
    return manifest


if __name__ == "__main__" and "--" in sys.argv:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--generated-root", help="Read existing illustration/font assets without copying them")
    parser.add_argument("--layout", action="append", choices=LAYOUTS, help="Render only the selected layout(s)")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    build(args.project, args.output, args.generated_root, args.layout)
