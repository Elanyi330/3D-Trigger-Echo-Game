"""Weapon processing pipeline — the single source of truth for weapon assets.

Takes a raw downloaded .glb and produces a CANONICAL weapon .glb:
  * muzzle oriented to Blender +Y  (== Godot -Z forward, verified by cal_query)
  * up = +Z, right = +X
  * normalized to REAL-world length (viewmodel x1.4 is applied later in Godot)
  * origin placed at the right-hand grip (GripRight)
  * named marker empties baked in (model-prefixed), -> Marker3D in Godot:
      Muzzle, GripRight, GripLeft, Magazine, Bolt, EjectPort, Sight, PullRing
  * mesh nodes renamed to model-prefixed distinctive names

Config-driven: add a new weapon by appending to WEAPONS below.

Marker positions are given in the RAW imported frame (what measure.py shows),
then transformed to canonical along with the mesh, so what you read off the
profile render is what you type here.

Run orient+render first (MARKERS={} or DEBUG_SPHERES) to read coords, then fill
markers and re-run. Set DEBUG_SPHERES=1 to render visible labeled marker spheres
for visual verification instead of exporting empties.

Usage:
  Blender --background --python process_weapon.py -- <KEY> [--debug-spheres]
"""
import bpy, sys, math
from mathutils import Vector, Matrix

# ----------------------------------------------------------------------------
# WEAPON CONFIGS
#   rot_z: rotation about Blender Z (deg) to bring muzzle to +Y
#   real_len: real-world length (m) along the barrel axis
#   mesh_rename: map imported mesh name -> distinctive name (model-prefixed)
#   markers: raw-frame local positions (m) for each component (None = skip)
# ----------------------------------------------------------------------------
WEAPONS = {
    "AK47_Echo": {
        "src": "tools/render/sources/AK47.glb",
        "out": "Assets/Models/Weapons/Rifle/AK47_Echo/AK47_Echo.glb",
        "rot_z": -90.0,          # muzzle -X -> +Y
        "real_len": 0.86,
        "mesh_rename": {"AK": "AK47_Echo_Body"},
        # raw-frame point that becomes the origin (right-hand grip)
        "grip_raw": (0.270, 0.0, -0.12),
        "mark": {"pos": (-0.048, 0.05, 0.120), "size": 0.038},  # ECHO imprint, receiver left face
        # markers in CANONICAL FINAL frame (origin = grip, muzzle +Y, up +Z, m)
        # measured off the canonical bare profile render.
        "markers": {
            "Muzzle":    (0.0, 0.432, 0.176),
            "GripRight": (0.0, 0.0, 0.0),
            "GripLeft":  (0.0, 0.140, 0.105),
            "Magazine":  (0.0, 0.030, -0.100),
            "Bolt":      (0.036, -0.020, 0.150),
            "EjectPort": (0.047, 0.020, 0.150),
            "Sight":     (0.0, -0.050, 0.215),
        },
    },
    "Glock18_Echo": {
        "src": "tools/render/sources/Glock18.glb",
        "out": "Assets/Models/Weapons/Pistol/Glock18_Echo/Glock18_Echo.glb",
        "rot_z": 90.0,           # muzzle +X -> +Y (probe: grip at -X rear)
        "real_len": 0.20,
        "mesh_rename": {"Muzzle": "Glock18_Echo_Body"},
        "grip_raw": (-0.10, 0.0, -0.04),  # grip centroid (probe), raw frame
        "mark": {"pos": (-0.018, 0.05, 0.058), "size": 0.020},  # ECHO imprint, slide left face
        "markers": {  # canonical frame — refined via bare measure + debug render
            "Muzzle":    (0.0, 0.171, 0.055),
            "GripRight": (0.0, 0.0, 0.0),
            "Magazine":  (0.0, -0.020, -0.036),
            "Bolt":      (0.0, 0.020, 0.060),   # slide (recoils back on fire)
            "EjectPort": (0.016, 0.030, 0.075),
            "Sight":     (0.0, -0.020, 0.090),
        },
    },
    "Grenade_M67_Echo": {
        "src": "tools/render/sources/Grenade_M67.glb",
        "out": "Assets/Models/Weapons/Throwable/Grenade_M67_Echo/Grenade_M67_Echo.glb",
        "rot_z": 0.0,            # already upright (fuse +Z up)
        "real_len": 0.10,        # max dim (body+fuse)
        "mesh_rename": {"Frag_West": "Grenade_M67_Echo_Body"},
        "grip_raw": (0.0, 0.0, -0.02),  # body center (palm wrap)
        "mark": {"pos": (-0.036, 0.0, -0.02), "size": 0.016},  # ECHO imprint, body left
        "markers": {  # canonical frame
            "GripRight": (0.0, 0.0, 0.0),
            "PullRing":  (0.035, 0.0, 0.050),  # the ring, upper side
            "Spoon":     (0.0, 0.0, 0.045),    # lever pivot top
        },
    },
}

DEBUG_SPHERES = "--debug-spheres" in sys.argv
BARE = "--bare" in sys.argv
argv = [a for a in sys.argv[sys.argv.index("--") + 1:] if not a.startswith("--")]
KEY = argv[0]
CFG = WEAPONS[KEY]
import os
ROOT = os.getcwd()
SRC = os.path.join(ROOT, CFG["src"])
OUT = os.path.join(ROOT, CFG["out"])
if BARE:
    OUT = os.path.join(ROOT, "tools/render/out/%s_bare.glb" % KEY)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
bpy.context.view_layer.update()
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']

def world_bbox(objs):
    mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
    return mn, mx

# Detach from any parents / keep flat: move all meshes to world transform, unparent
for o in meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
bpy.context.view_layer.update()

# Remove non-mesh leftovers (armatures/empties from source) for a clean weapon
for o in list(bpy.context.scene.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o, do_unlink=True)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']

# ---- Step 1: rotate muzzle -> +Y (about Z), keep up=+Z ----
rz = math.radians(CFG["rot_z"])
R = Matrix.Rotation(rz, 4, 'Z')
for o in meshes:
    o.matrix_world = R @ o.matrix_world
bpy.context.view_layer.update()

# ---- Step 2: normalize so the LONGEST dimension == real_len ----
mn, mx = world_bbox(meshes)
dims = mx - mn
cur_len = max(dims.x, dims.y, dims.z)
scale = CFG["real_len"] / cur_len
S = Matrix.Scale(scale, 4)
for o in meshes:
    o.matrix_world = S @ o.matrix_world
bpy.context.view_layer.update()

# ---- Step 3: origin at right-hand grip (grip_raw transformed to canonical) ----
grip = S @ (R @ Vector(CFG["grip_raw"]))
T = Matrix.Translation(-grip)
for o in meshes:
    o.matrix_world = T @ o.matrix_world
bpy.context.view_layer.update()

# ---- Step 4: markers are given in canonical FINAL frame (origin=grip) -> use as-is ----
markers = {} if BARE else {k: Vector(v) for k, v in CFG["markers"].items() if v is not None}

# ---- Step 5: apply transforms, rename meshes ----
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
for o in meshes:
    if o.name in CFG["mesh_rename"]:
        o.name = CFG["mesh_rename"][o.name]
    elif not o.name.startswith(KEY):
        o.name = "%s_%s" % (KEY, o.name)

# ---- Step 5b: ECHO series imprint on body side (-X face) ----
def add_echo_mark(pos, size):
    bpy.ops.object.text_add(location=pos)
    t = bpy.context.active_object
    t.name = "%s_EchoMark" % KEY
    t.data.body = "ECHO"
    t.data.size = size
    t.data.extrude = 0.0012
    t.data.align_x = 'CENTER'
    t.data.align_y = 'CENTER'
    # face -X (weapon left / player-visible), read along -Y, up +Z
    t.rotation_euler = (math.radians(90), 0, math.radians(-90))
    m = bpy.data.materials.new("EchoMark")
    m.diffuse_color = (1.0, 0.45, 0.05, 1.0)   # accent orange
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (1.0, 0.45, 0.05, 1.0)
    b.inputs["Roughness"].default_value = 0.4
    t.data.materials.append(m)
    # convert to mesh so it exports cleanly
    bpy.ops.object.convert(target='MESH')
    return t

if "mark" in CFG:
    mk = CFG["mark"]
    add_echo_mark(Vector(mk["pos"]), mk["size"])
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']

mn, mx = world_bbox(meshes)
print("CANONICAL %s: bbox min %s max %s dims %s (real_len=%.3f)" % (
    KEY, tuple(round(v,3) for v in mn), tuple(round(v,3) for v in mx),
    tuple(round(v,3) for v in mx- mn), CFG["real_len"]))
for k, v in markers.items():
    print("  marker %s_%s -> %s" % (KEY, k, tuple(round(x,3) for x in v)))

if DEBUG_SPHERES:
    # visible labeled spheres for verification (no export)
    COLORS = {"Muzzle":(1,0,0),"GripRight":(0,1,0),"GripLeft":(0,0.6,1),
              "Magazine":(1,0.5,0),"Bolt":(1,0,1),"EjectPort":(1,1,0),
              "Sight":(0,1,1),"PullRing":(1,0.3,0.6)}
    for k, v in markers.items():
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.016, location=v)
        s = bpy.context.active_object
        m = bpy.data.materials.new(k); m.diffuse_color = (*COLORS.get(k,(1,1,1)),1)
        s.data.materials.append(m)
        # label offset out to the +X side so it doesn't overlap the model
        bpy.ops.object.text_add(location=(v.x+0.06, v.y, v.z))
        t = bpy.context.active_object; t.data.body = k; t.data.size = 0.03
        tm = bpy.data.materials.new("t"+k); tm.diffuse_color=(*COLORS.get(k,(1,1,1)),1)
        t.data.materials.append(tm)
        # leader line from label to sphere
        cu=bpy.data.curves.new("lead","CURVE"); cu.dimensions='3D'
        sp=cu.splines.new('POLY'); sp.points.add(1)
        sp.points[0].co=(v.x,v.y,v.z,1); sp.points[1].co=(v.x+0.055,v.y,v.z,1)
        cu.bevel_depth=0.0015; ob=bpy.data.objects.new("lead",cu)
        bpy.context.scene.collection.objects.link(ob); cu.materials.append(tm)
    # lights + cameras
    bpy.ops.object.light_add(type='SUN', location=(5,-5,10)); bpy.context.active_object.data.energy=4
    bpy.ops.object.light_add(type='SUN', location=(-3,-2,8)); bpy.context.active_object.data.energy=2
    w=bpy.data.worlds.new("w"); w.use_nodes=True
    w.node_tree.nodes["Background"].inputs[0].default_value=(0.95,0.95,0.97,1)
    bpy.context.scene.world=w
    sc=bpy.context.scene; sc.render.engine='BLENDER_EEVEE'
    sc.render.resolution_x=1100; sc.render.resolution_y=900
    mn, mx = world_bbox([o for o in bpy.context.scene.objects if o.type=='MESH'])
    c=(mn+mx)/2; ext=(mx-mn).length
    texts=[o for o in bpy.context.scene.objects if o.type=='FONT']
    def shot(loc, look, fn, orth):
        bpy.ops.object.camera_add(location=loc); cam=bpy.context.active_object
        d=Vector(look)-Vector(loc); q=d.to_track_quat('-Z','Y').to_euler()
        cam.rotation_euler=q
        cam.data.type='ORTHO'; cam.data.ortho_scale=orth; sc.camera=cam
        for t in texts: t.rotation_euler=q  # billboard labels
        sc.render.filepath=fn; bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)
    base=os.path.join(ROOT,"tools/render/out/%s_markers"%KEY)
    # side profile (muzzle along Y, so view from +X shows Y horiz, Z vert)
    shot((c.x+ext*2, c.y, c.z), c, base+"_side.png", ext*0.7)
    shot((c.x, c.y-ext*2, c.z), c, base+"_front.png", ext*0.7)
    shot((c.x, c.y, mx.z+ext*2), c, base+"_top.png", ext*0.7)
    shot((c.x+ext, c.y-ext, mx.z+ext*0.8), c, base+"_iso.png", ext*0.8)
    print("DEBUG MARKER RENDER DONE", KEY)
else:
    # ---- Step 6: bake marker empties (model-prefixed) ----
    for k, v in markers.items():
        e = bpy.data.objects.new("%s_%s" % (KEY, k), None)
        e.empty_display_size = 0.02
        e.location = v
        # orient marker so its -Z (Godot forward after import) points along barrel +Y
        # Blender: marker local +Y is barrel dir; we keep identity (axes already canonical)
        bpy.context.scene.collection.objects.link(e)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', export_yup=True,
                              export_apply=True, export_extras=True, export_animations=False)
    print("EXPORTED %s -> %s" % (KEY, OUT))
