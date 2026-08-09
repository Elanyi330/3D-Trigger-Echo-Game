"""Procedural blocky character — clean rebuild (replaces the broken v5/v7 Player.glb).

Design goals:
  * blocky / Minecraft-inspired style, but well-proportioned (arms long enough to hold weapons)
  * 1.78m tall, feet at z=0, faces Blender +Y  (== Godot -Z forward, verified by cal_query)
  * single-bone-per-box weights (avoids the ARMATURE_AUTO snap/stretch pitfall)
  * named 16-bone skeleton incl. Hand.L / Hand.R for weapon attachment
  * tintable uniform material (player/teammate/enemy differ only by color)

Usage:
  Blender --background --python build_character.py -- <out.glb> [--debug] [--tint R,G,B]
"""
import bpy, sys, os, math
from mathutils import Vector

argv = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")]
OUT = argv[0]
DEBUG = "--debug" in sys.argv
TINT = (0.35, 0.48, 0.32)   # default player green uniform
for a in sys.argv:
    if a.startswith("--tint="):
        TINT = tuple(float(x) for x in a.split("=")[1].split(","))

bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------------------------------------------------------------- materials
def mat(rgba, rough=0.7):
    m = bpy.data.materials.new("m")
    c = (rgba[0], rgba[1], rgba[2], 1.0)
    m.diffuse_color = c
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = c
    b.inputs["Roughness"].default_value = rough
    return m

UNIFORM = mat(TINT)                       # tintable body
UNIFORM_DARK = mat(tuple(t*0.7 for t in TINT))  # darker limbs
SKIN = mat((0.85, 0.68, 0.55))            # head + hands
BOOT = mat((0.15, 0.13, 0.12))            # feet
ACCENT = mat((0.12, 0.12, 0.14))          # belt/pads

# ---------------------------------------------------------------- mesh boxes
# CS 人物身高照搬（用户：比例/身高/判定全对标 CS）：CS 站立 72u × 0.0254 = 1.8288m。
# 本构建头顶 z=1.78m → 统一数据级缩放因子 S（几何/骨骼同步缩放，非 object 变换——避免骨骼绑定双缩放坑）。
S = 1.8288 / 1.78   # ≈1.0274

def box(name, center, size, material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(center[0]*S, center[1]*S, center[2]*S))
    o = bpy.context.active_object
    o.name = name
    o.scale = (size[0]*S, size[1]*S, size[2]*S)   # size=1 cube -> dimension == scale
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)  # bake to world space
    o.data.materials.append(material)
    return o

# proportions (z ranges): foot 0-0.08, shin 0.08-0.48, thigh 0.48-0.86,
# pelvis 0.86-1.00, torso 1.00-1.46, neck 1.46-1.52, head 1.52-1.78
# each entry: (mesh, bone) — merged into ONE skinned mesh (avoids node/bone name clashes)
parts = []
def P(name, center, size, material, bone):
    o = box(name, center, size, material)
    parts.append((o, bone))
    return o
P("Torso",   (0, 0, 1.23), (0.42, 0.24, 0.46), UNIFORM, "Spine")
P("Pelvis",  (0, 0, 0.93), (0.40, 0.24, 0.14), UNIFORM_DARK, "Root")
P("Head",    (0, 0.005, 1.65), (0.26, 0.26, 0.26), SKIN, "Head")
EYE = mat((0.10, 0.10, 0.12))
P("Eye_L", (0.06, 0.135, 1.68), (0.045, 0.02, 0.06), EYE, "Head")
P("Eye_R", (-0.06, 0.135, 1.68), (0.045, 0.02, 0.06), EYE, "Head")
# arms: shoulder z=1.42, elbow z=1.10, wrist z=0.80, hand 0.70-0.80
for s, sx in [("L", 0.265), ("R", -0.265)]:
    P("UpperArm_"+s, (sx, 0, 1.26), (0.11, 0.13, 0.34), UNIFORM, "UpperArm_"+s)
    P("Forearm_"+s,  (sx, 0, 0.95), (0.10, 0.11, 0.30), UNIFORM_DARK, "Forearm_"+s)
    P("Hand_"+s,     (sx, 0.0, 0.735), (0.10, 0.11, 0.13), SKIN, "Hand_"+s)
# legs: hip z=0.86, knee z=0.48, ankle z=0.08
for s, sx in [("L", 0.11), ("R", -0.11)]:
    P("UpperLeg_"+s, (sx, 0, 0.67), (0.16, 0.18, 0.38), UNIFORM_DARK, "UpperLeg_"+s)
    P("LowerLeg_"+s, (sx, 0, 0.28), (0.14, 0.16, 0.40), UNIFORM, "LowerLeg_"+s)
    P("Foot_"+s,     (sx, 0.05, 0.04), (0.14, 0.26, 0.08), BOOT, "Foot_"+s)  # toes +Y

# ---------------------------------------------------------------- skeleton
arm = bpy.data.armatures.new("Armature")
arm_obj = bpy.data.objects.new("Player_Armature", arm)
bpy.context.scene.collection.objects.link(arm_obj)
bpy.context.view_layer.objects.active = arm_obj
bpy.ops.object.mode_set(mode='EDIT')

# bone table: name -> (head, tail). Character faces +Y.
BONES = {
    "Root":       ((0, 0, 0.93), (0, 0, 1.01)),
    "Spine":      ((0, 0, 1.01), (0, 0, 1.30)),
    "Neck":       ((0, 0, 1.46), (0, 0, 1.56)),
    "Head":       ((0, 0, 1.56), (0, 0, 1.78)),
    "Shoulder_L": ((0.21, 0, 1.42), (0.265, 0, 1.42)),
    "UpperArm_L": ((0.265, 0, 1.42), (0.265, 0, 1.10)),
    "Forearm_L":  ((0.265, 0, 1.10), (0.265, 0, 0.80)),
    "Hand_L":     ((0.265, 0, 0.80), (0.265, 0, 0.70)),
    "Shoulder_R": ((-0.21, 0, 1.42), (-0.265, 0, 1.42)),
    "UpperArm_R": ((-0.265, 0, 1.42), (-0.265, 0, 1.10)),
    "Forearm_R":  ((-0.265, 0, 1.10), (-0.265, 0, 0.80)),
    "Hand_R":     ((-0.265, 0, 0.80), (-0.265, 0, 0.70)),
    "UpperLeg_L": ((0.11, 0, 0.86), (0.11, 0, 0.48)),
    "LowerLeg_L": ((0.11, 0, 0.48), (0.11, 0, 0.08)),
    "Foot_L":     ((0.11, 0, 0.08), (0.11, 0.12, 0.02)),
    "UpperLeg_R": ((-0.11, 0, 0.86), (-0.11, 0, 0.48)),
    "LowerLeg_R": ((-0.11, 0, 0.48), (-0.11, 0, 0.08)),
    "Foot_R":     ((-0.11, 0, 0.08), (-0.11, 0.12, 0.02)),
}
PARENT = {"Spine":"Root","Neck":"Spine","Head":"Neck",
    "Shoulder_L":"Spine","UpperArm_L":"Shoulder_L","Forearm_L":"UpperArm_L","Hand_L":"Forearm_L",
    "Shoulder_R":"Spine","UpperArm_R":"Shoulder_R","Forearm_R":"UpperArm_R","Hand_R":"Forearm_R",
    "UpperLeg_L":"Root","LowerLeg_L":"UpperLeg_L","Foot_L":"LowerLeg_L",
    "UpperLeg_R":"Root","LowerLeg_R":"UpperLeg_R","Foot_R":"LowerLeg_R"}
eb = arm.edit_bones
name2bone = {}
for nm, (h, t) in BONES.items():
    b = eb.new(nm)
    b.head = (h[0]*S, h[1]*S, h[2]*S)  # 骨骼同步 CS 身高缩放
    b.tail = (t[0]*S, t[1]*S, t[2]*S)
    name2bone[nm] = b
for nm, par in PARENT.items():
    name2bone[nm].parent = name2bone[par]
bpy.ops.object.mode_set(mode='OBJECT')

# ---------------------------------------------------------------- bind (single bone per box, then ONE merged skinned mesh)
# 1) per-part vertex group (bone name) so groups merge correctly on join
for o, bone in parts:
    vg = o.vertex_groups.new(name=bone)
    vg.add(list(range(len(o.data.vertices))), 1.0, 'REPLACE')
# 2) join all parts into a single mesh (keeps material slots + merges vertex groups)
bpy.ops.object.select_all(action='DESELECT')
for o, bone in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0][0]
bpy.ops.object.join()
body = parts[0][0]
body.name = "Soldier_Echo_Body"
# 3) clear object transform so the skinned mesh sits at the armature origin
body.location = (0, 0, 0)
# 4) one armature modifier on the merged mesh
mod = body.modifiers.new("Armature", 'ARMATURE')
mod.object = arm_obj
body.parent = arm_obj

# ---------------------------------------------------------------- export / debug
if DEBUG:
    bpy.ops.object.light_add(type='SUN', location=(4,-4,8)); bpy.context.active_object.data.energy=3.5
    bpy.ops.object.light_add(type='SUN', location=(-4,2,6)); bpy.context.active_object.data.energy=2
    w=bpy.data.worlds.new("w"); w.use_nodes=True
    w.node_tree.nodes["Background"].inputs[0].default_value=(0.92,0.92,0.95,1)
    bpy.context.scene.world=w
    # ground plane
    bpy.ops.mesh.primitive_plane_add(size=4, location=(0,0,0))
    pl=bpy.context.active_object; pm=mat((0.7,0.7,0.72)); pl.data.materials.append(pm)
    sc=bpy.context.scene; sc.render.engine='BLENDER_EEVEE'
    sc.render.resolution_x=800; sc.render.resolution_y=1000
    def shot(loc, look, fn, orth):
        bpy.ops.object.camera_add(location=loc); cam=bpy.context.active_object
        d=Vector(look)-Vector(loc); cam.rotation_euler=d.to_track_quat('-Z','Y').to_euler()
        cam.data.type='ORTHO'; cam.data.ortho_scale=orth; sc.camera=cam
        sc.render.filepath=fn; bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)
    c=(0,0,0.9)
    shot((0,-4,0.9), c, OUT+"_front.png", 2.0)   # from -Y (front, since faces +Y)
    shot((4,0,0.9), c, OUT+"_side.png", 2.0)     # from +X
    shot((2.5,-3,2.2), c, OUT+"_iso.png", 2.2)
    print("CHAR DEBUG RENDER DONE  faces+Y")
else:
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True,
                              export_apply=True, export_extras=True, export_animations=False)
    print("EXPORTED Character -> %s (bones=%d)" % (OUT, len(BONES)))
