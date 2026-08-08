"""Procedural blocky tactical knife (replaces the corrupt downloaded Knife.glb).

Built directly in CANONICAL frame: blade tip -> +Y (Godot -Z forward), up +Z,
origin at grip center. Real length 0.35m. Blocky style to match the character.
Bakes markers: GripRight (handle), Tip (blade point), Guard.

Usage: Blender --background --python build_knife.py -- <out.glb> [--debug-spheres]
"""
import bpy, sys, os
from mathutils import Vector

argv = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")]
OUT = argv[0]
DEBUG = "--debug-spheres" in sys.argv

bpy.ops.wm.read_factory_settings(use_empty=True)
MODEL = "Knife_Echo"   # 战术匕首「回声」 — distinctive model name / node prefix

def mat(rgba):
    m = bpy.data.materials.new("m")
    c = (rgba[0], rgba[1], rgba[2], 1.0)
    m.diffuse_color = c
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = c
    bsdf.inputs["Roughness"].default_value = 0.6
    return m

STEEL = mat((0.62, 0.64, 0.68, 1))
STEEL_DARK = mat((0.35, 0.37, 0.40, 1))
GRIP = mat((0.16, 0.13, 0.11, 1))   # dark polymer
GUARD = mat((0.22, 0.22, 0.24, 1))

def box(name, loc, scale, material):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)  # size=1 -> dimension 1
    o = bpy.context.active_object
    o.name = name
    o.scale = scale  # dimension == scale (NOT scale/2)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    o.data.materials.append(material)
    return o

def wedge_blade():
    """Tanto-ish tapered blade. Tip +Y. Returns mesh object."""
    # cross-section: X thickness, Z from edge(bottom) to spine(top)
    yb, yt = 0.015, 0.215          # base and tip Y
    th = 0.004                      # half thickness (X)
    e0, s0 = 0.004, 0.036           # edge & spine Z at base
    # taper profile: full height until yk, then spine dives to tip
    yk = 0.150
    verts = []
    # 3 stations: base, knee, tip
    for (y, ez, sz, t) in [(yb, e0, s0, th), (yk, e0, s0, th), (yt, 0.016, 0.018, 0.0015)]:
        verts += [(-t, y, ez), (t, y, ez), (t, y, sz), (-t, y, sz)]
    faces = []
    # two segments (base->knee, knee->tip), each a 4-vert ring
    for seg in range(2):
        a = seg*4; b = (seg+1)*4
        faces += [(a+0,b+0,b+1,a+1),  # edge side (bottom)
                  (a+3,a+2,b+2,b+3),  # spine side (top)
                  (a+1,b+1,b+2,a+2),  # +X face
                  (a+0,a+3,b+3,b+0)]  # -X face
    faces += [(0,1,2,3), (8,11,10,9)]  # base cap, tip cap
    me = bpy.data.meshes.new("blade")
    me.from_pydata(verts, [], faces); me.update()
    o = bpy.data.objects.new(MODEL+"_Blade", me)
    bpy.context.scene.collection.objects.link(o)
    o.data.materials.append(STEEL)
    return o

# --- build parts (origin at grip center); parts OVERLAP so they join solidly ---
blade = wedge_blade()                                    # tip +Y to 0.215, base Y=0.015
box(MODEL+"_Guard", (0, 0.005, 0.018), (0.052, 0.024, 0.052), GUARD)   # Y[-0.007,0.017] overlaps blade base
box(MODEL+"_Handle", (0, -0.060, 0.012), (0.030, 0.125, 0.038), GRIP)  # Y[-0.1225,0.0025] overlaps guard
box(MODEL+"_Pommel", (0, -0.128, 0.013), (0.034, 0.024, 0.042), STEEL_DARK)  # Y[-0.14,-0.116] overlaps handle

# diagnostic: each part's world Y/Z range
for o in bpy.context.scene.objects:
    if o.type == 'MESH':
        ys = [(o.matrix_world @ v.co).y for v in o.data.vertices]
        zs = [(o.matrix_world @ v.co).z for v in o.data.vertices]
        print("PART %s: Y[%.3f,%.3f] Z[%.3f,%.3f]" % (o.name, min(ys), max(ys), min(zs), max(zs)))

# join all into one mesh named Knife_Body
for o in bpy.context.scene.objects:
    if o.type == 'MESH':
        o.select_set(True)
bpy.context.view_layer.objects.active = blade
bpy.ops.object.join()
blade.name = MODEL+"_Body"

# markers (canonical frame, origin=grip)
MARKERS = {
    "GripRight": (0.0, -0.060, 0.012),
    "Tip":       (0.0, 0.215, 0.017),
    "Guard":     (0.0, 0.005, 0.018),
}

# ECHO series imprint on blade left face (-X), reads along the blade
bpy.ops.object.text_add(location=(-0.005, 0.10, 0.018))
_t = bpy.context.active_object
_t.name = MODEL + "_EchoMark"
_t.data.body = "ECHO"; _t.data.size = 0.020; _t.data.extrude = 0.0008
_t.data.align_x = 'CENTER'; _t.data.align_y = 'CENTER'
_t.rotation_euler = (1.5708, 0, -1.5708)  # face -X, read along blade, up +Z
_mm = bpy.data.materials.new("EchoMark"); _mm.diffuse_color = (1.0, 0.45, 0.05, 1.0)
_mm.use_nodes = True
_mm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (1.0, 0.45, 0.05, 1.0)
_t.data.materials.append(_mm)
bpy.ops.object.convert(target='MESH')

if DEBUG:
    for k, v in MARKERS.items():
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.008, location=v)
        s = bpy.context.active_object
        m = bpy.data.materials.new(k); m.diffuse_color=(1,0,0,1); s.data.materials.append(m)
    bpy.ops.object.light_add(type='SUN', location=(3,-3,6)); bpy.context.active_object.data.energy=4
    bpy.ops.object.light_add(type='SUN', location=(-2,2,5)); bpy.context.active_object.data.energy=2
    w=bpy.data.worlds.new("w"); w.use_nodes=True
    w.node_tree.nodes["Background"].inputs[0].default_value=(0.95,0.95,0.97,1)
    bpy.context.scene.world=w
    sc=bpy.context.scene; sc.render.engine='BLENDER_EEVEE'
    sc.render.resolution_x=1000; sc.render.resolution_y=700
    def shot(loc, look, fn, orth):
        bpy.ops.object.camera_add(location=loc); cam=bpy.context.active_object
        d=Vector(look)-Vector(loc); cam.rotation_euler=d.to_track_quat('-Z','Y').to_euler()
        cam.data.type='ORTHO'; cam.data.ortho_scale=orth; sc.camera=cam
        sc.render.filepath=fn; bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)
    shot((0.6,0.1,0.1),(0,0.05,0.01), OUT+"_side.png", 0.45)
    shot((0.25,-0.3,0.35),(0,0.05,0.0), OUT+"_iso.png", 0.5)
    print("KNIFE DEBUG RENDER DONE")
else:
    for k, v in MARKERS.items():
        e = bpy.data.objects.new(MODEL+"_"+k, None); e.empty_display_size=0.015; e.location=v
        bpy.context.scene.collection.objects.link(e)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True,
                              export_apply=True, export_extras=True, export_animations=False)
    print("EXPORTED Knife -> %s" % OUT)
