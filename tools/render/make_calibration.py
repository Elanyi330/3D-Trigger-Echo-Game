"""Axis calibration: build a labeled arrow + empties in Blender, export GLB.
Blender convention used: +Y = forward, +Z = up, +X = right.
We then query in Godot where TIP/UP land to nail the Blender->glTF->Godot map.
"""
import bpy
import sys

argv = sys.argv[sys.argv.index("--") + 1:]
OUT = argv[0]

bpy.ops.wm.read_factory_settings(use_empty=True)

# Visible shaft along +Y (Blender forward candidate)
bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=2.0, location=(0, 1.0, 0), rotation=(1.5708, 0, 0))
shaft = bpy.context.active_object
# Cone head pointing +Y at the tip
bpy.ops.mesh.primitive_cone_add(radius1=0.15, depth=0.4, location=(0, 2.2, 0), rotation=(1.5708, 0, 0))
head = bpy.context.active_object
# Up box offset +Z
bpy.ops.mesh.primitive_cube_add(size=0.3, location=(0, 1.0, 0.6))
upbox = bpy.context.active_object
upbox.scale = (1, 1, 2)

# Named empties to query in Godot
def empty(name, loc):
    e = bpy.data.objects.new(name, None)
    e.location = loc
    bpy.context.scene.collection.objects.link(e)
    return e

empty("CAL_TIP", (0, 2.4, 0))   # Blender +Y tip
empty("CAL_UP", (0, 0, 1.0))    # Blender +Z up
empty("CAL_RIGHT", (1.0, 0, 0)) # Blender +X right

bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True,
                          export_apply=True, export_extras=True, export_animations=False)
print("CAL EXPORTED", OUT)
