"""Blender headless asset inspector.
Imports a .glb, frames it, draws RGB world-axis arrows (+X red/+Y green/+Z blue),
adds a 0.1m ground grid, and renders front/right/top/iso views to PNGs.
Also prints a geometry report (dimensions, long axis, per-axis min/max) so we can
determine muzzle direction numerically instead of guessing.

Usage:
  Blender --background --python inspect_asset.py -- <glb_path> <out_prefix> [target_size]
"""
import bpy
import sys
import math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
GLB = argv[0]
OUT = argv[1]
TARGET = float(argv[2]) if len(argv) > 2 else None

# ---- wipe scene ----
bpy.ops.wm.read_factory_settings(use_empty=True)

# ---- import ----
bpy.ops.import_scene.gltf(filepath=GLB)
bpy.context.view_layer.update()

# collect mesh objects (evaluated, world space)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']

def world_bbox(objs):
    mn = Vector((1e9, 1e9, 1e9))
    mx = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        for corner in o.bound_box:
            w = o.matrix_world @ Vector(corner)
            mn = Vector(map(min, mn, w))
            mx = Vector(map(max, mx, w))
    return mn, mx

mn, mx = world_bbox(meshes)
center = (mn + mx) / 2
dims = mx - mn
print("\n==== GEOMETRY REPORT ====")
print("file:", GLB)
print("mesh objects:", len(meshes))
print("bbox min: (%.4f, %.4f, %.4f)" % (mn.x, mn.y, mn.z))
print("bbox max: (%.4f, %.4f, %.4f)" % (mx.x, mx.y, mx.z))
print("dims   X: %.4f  Y: %.4f  Z: %.4f" % (dims.x, dims.y, dims.z))
long_axis = max(('X', 'Y', 'Z'), key=lambda a: getattr(dims, a.lower()))
print("long axis:", long_axis)
print("center: (%.4f, %.4f, %.4f)" % (center.x, center.y, center.z))
print("mesh names:", [o.name for o in meshes][:20])
print("=========================\n")

# ---- normalize to target size along long axis if requested ----
if TARGET:
    cur = getattr(dims, long_axis.lower())
    if cur > 0:
        s = TARGET / cur
        for o in bpy.context.scene.objects:
            if o.parent is None:
                o.scale = (o.scale[0]*s, o.scale[1]*s, o.scale[2]*s)
        bpy.context.view_layer.update()
        mn, mx = world_bbox(meshes)
        center = (mn + mx)/2
        dims = mx - mn
        print("normalized scale %.4f -> new dims %.3f %.3f %.3f" % (s, dims.x, dims.y, dims.z))

# sit on ground: shift so min z = 0 (Blender Z-up world)
for o in bpy.context.scene.objects:
    if o.parent is None:
        o.location.z -= mn.z
bpy.context.view_layer.update()
mn, mx = world_bbox(meshes)
center = (mn + mx)/2
dims = mx - mn

# ---- axis arrows ----
def mat(color):
    m = bpy.data.materials.new("m")
    m.diffuse_color = (*color, 1.0)
    return m

def arrow(axis_dir, color, name):
    L = max(dims.length, 0.5) * 0.9
    r = L * 0.02
    d = Vector(axis_dir).normalized()
    # shaft
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=L, location=d*(L/2))
    shaft = bpy.context.active_object
    shaft.data.materials.append(mat(color))
    # orient shaft +Z to d
    shaft.rotation_mode = 'QUATERNION'
    shaft.rotation_quaternion = Vector((0,0,1)).rotation_difference(d)
    # head
    bpy.ops.mesh.primitive_cone_add(radius1=r*3, depth=L*0.12, location=d*(L + L*0.06))
    head = bpy.context.active_object
    head.data.materials.append(mat(color))
    head.rotation_mode = 'QUATERNION'
    head.rotation_quaternion = Vector((0,0,1)).rotation_difference(d)
    # label
    bpy.ops.object.text_add(location=d*(L*1.25))
    t = bpy.context.active_object
    t.data.body = name
    t.data.size = L*0.12
    t.data.materials.append(mat(color))

arrow((1,0,0),(1,0.1,0.1),"+X")
arrow((0,1,0),(0.1,0.9,0.1),"+Y")
arrow((0,0,1),(0.2,0.3,1),"+Z")

# ---- ground grid (0.1m cells) ----
grid = bpy.data.meshes.new("grid")
size = max(dims.length, 1.0)
verts=[]; edges=[]
n = int(size/0.1)+1
half = n*0.1/2
for i in range(n+1):
    p=-half+i*0.1
    verts.append((p,-half,0)); verts.append((p,half,0))
    verts.append((-half,p,0)); verts.append((half,p,0))
for i in range(n+1):
    b=i*4
    edges.append((b,b+1)); edges.append((b+2,b+3))
grid.from_pydata(verts,edges,[])
go=bpy.data.objects.new("grid",grid)
bpy.context.scene.collection.objects.link(go)
gm=bpy.data.materials.new("gm"); gm.diffuse_color=(0.3,0.3,0.3,1)
grid.materials.append(gm)

# ---- lights ----
def sun(loc, energy):
    bpy.ops.object.light_add(type='SUN', location=loc)
    s=bpy.context.active_object
    s.data.energy=energy
sun((5,-5,10),3.0)
sun((-5,5,6),2.0)
bpy.ops.object.light_add(type='SUN', location=(0,0,20))
bpy.context.active_object.data.energy=1.5

# ---- camera helper ----
def render(campos, look, fname, ortho_scale):
    bpy.ops.object.camera_add(location=campos)
    cam=bpy.context.active_object
    direction = Vector(look)-Vector(campos)
    cam.rotation_euler = direction.to_track_quat('-Z','Y').to_euler()
    cam.data.type='ORTHO'
    cam.data.ortho_scale=ortho_scale
    bpy.context.scene.camera=cam
    bpy.context.scene.render.filepath=fname
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)

# render settings
sc=bpy.context.scene
sc.render.engine='BLENDER_EEVEE'
sc.render.resolution_x=700
sc.render.resolution_y=700
sc.render.film_transparent=False
world=bpy.data.worlds.new("w")
world.use_nodes=True
world.node_tree.nodes["Background"].inputs[0].default_value=(0.9,0.9,0.92,1)
world.node_tree.nodes["Background"].inputs[1].default_value=1.0
sc.world=world

R = dims.length
sc_ortho = R*1.5
# front: camera at -Y looking toward +Y (shows X right, Z up)
render((center.x, center.y-R*2, center.z), center, OUT+"_front.png", sc_ortho)
# right: camera at +X looking toward -X (shows Y, Z)
render((center.x+R*2, center.y, center.z), center, OUT+"_right.png", sc_ortho)
# top: camera at +Z looking down (shows X, Y)
render((center.x, center.y, mx.z+R*2), center, OUT+"_top.png", sc_ortho)
# iso 3/4
render((center.x+R*1.5, center.y-R*1.5, mx.z+R*1.2), center, OUT+"_iso.png", sc_ortho)
print("RENDER DONE", OUT)
