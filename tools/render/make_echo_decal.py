"""Render the ECHO series logo to a transparent-background PNG (printed-sticker decal texture).

The output is a flat orange "ECHO" wordmark on transparency, used by process_weapon.py /
build_knife.py as a *flush texture decal* (印花贴纸) instead of a protruding 3D text mesh.

Usage:  Blender --background --python make_echo_decal.py -- <out.png>
"""
import bpy, sys, os

argv = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")]
OUT = argv[0] if argv else "tools/render/sources/echo_decal.png"

bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene

# --- "ECHO" text, centered, orange ---
bpy.ops.object.text_add(location=(0, 0, 0))
t = bpy.context.active_object
t.data.body = "ECHO"
t.data.align_x = 'CENTER'
t.data.align_y = 'CENTER'
t.data.size = 1.0
t.data.extrude = 0.0  # perfectly flat — pure 2D wordmark
t.data.space_character = 1.15
m = bpy.data.materials.new("echo")
m.use_nodes = True
b = m.node_tree.nodes["Principled BSDF"]
b.inputs["Base Color"].default_value = (0.95, 0.55, 0.15, 1.0)  # series orange
b.inputs["Emission Color"].default_value = (0.95, 0.55, 0.15, 1.0)
b.inputs["Emission Strength"].default_value = 1.0  # unlit → flat printed color
b.inputs["Roughness"].default_value = 0.6
t.data.materials.append(m)

# --- ortho camera straight down -Z, text faces +Z up toward it; transparent film ---
bpy.ops.object.camera_add(location=(0, 0, 5))
cam = bpy.context.active_object
cam.rotation_euler = (0, 0, 0)  # default looks down -Z at the +Z-facing text
cam.data.type = 'ORTHO'
cam.data.ortho_scale = 4.6  # fit "ECHO" with a little margin
sc.camera = cam
sc.render.engine = 'BLENDER_EEVEE'
sc.render.resolution_x = 1024
sc.render.resolution_y = 256
sc.render.film_transparent = True
sc.render.image_settings.file_format = 'PNG'
sc.render.image_settings.color_mode = 'RGBA'
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("ECHO DECAL SAVED", OUT)
