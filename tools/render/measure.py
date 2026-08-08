"""Measurement profiler: render a weapon GLB as an orthographic side profile
with a labeled numeric grid so feature coordinates can be read off precisely.

Usage: Blender --background --python measure.py -- <glb> <out.png> [view]
  view: 'side' (XZ plane, camera -Y) | 'top' (XY plane, camera +Z) | 'front' (YZ, camera +X)
"""
import bpy, sys
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
GLB, OUT = argv[0], argv[1]
VIEW = argv[2] if len(argv) > 2 else 'side'

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=GLB)
bpy.context.view_layer.update()
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']

def world_bbox(objs):
    mn = Vector((1e9,)*3); mx = Vector((-1e9,)*3)
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            mn = Vector(map(min, mn, w)); mx = Vector(map(max, mx, w))
    return mn, mx
mn, mx = world_bbox(meshes)
center = (mn+mx)/2; dims = mx-mn
print("BBOX min %s max %s dims %s" % (tuple(round(v,3) for v in mn), tuple(round(v,3) for v in mx), tuple(round(v,3) for v in dims)))

# origin marker (red sphere at 0,0,0)
bpy.ops.mesh.primitive_uv_sphere_add(radius=0.01, location=(0,0,0))
org = bpy.context.active_object
om = bpy.data.materials.new("org"); om.diffuse_color=(1,0,0,1)
org.data.materials.append(om)

# numeric grid on the view plane
def gridmat(c):
    m=bpy.data.materials.new("g"); m.diffuse_color=(*c,1); return m
gm = gridmat((0.75,0.75,0.75))
STEP=0.05
# build grid lines as thin curves on the appropriate plane
def line(p1,p2):
    cu=bpy.data.curves.new("l","CURVE"); cu.dimensions='3D'
    sp=cu.splines.new('POLY'); sp.points.add(1)
    sp.points[0].co=(*p1,1); sp.points[1].co=(*p2,1)
    cu.bevel_depth=0.0012
    ob=bpy.data.objects.new("l",cu); bpy.context.scene.collection.objects.link(ob)
    cu.materials.append(gm)

def text(body, loc, size=0.02):
    bpy.ops.object.text_add(location=loc)
    t=bpy.context.active_object; t.data.body=body; t.data.size=size
    t.data.align_x='CENTER'
    tm=gridmat((0.1,0.1,0.6)); t.data.materials.append(tm)
    return t

import math
if VIEW=='side':  # X horizontal, Z vertical, camera at -Y
    x0=int(mn.x/STEP)-1; x1=int(mx.x/STEP)+1
    z0=int(mn.z/STEP)-1; z1=int(mx.z/STEP)+1
    for i in range(x0,x1+1):
        line((i*STEP,0,z0*STEP),(i*STEP,0,z1*STEP))
    for k in range(z0,z1+1):
        line((x0*STEP,0,k*STEP),(x1*STEP,0,k*STEP))
    # labels every 2 steps
    for i in range(x0,x1+1):
        if i%2==0: text("%.2f"%(i*STEP),(i*STEP,-0.01,(z0)*STEP-0.02))
    for k in range(z0,z1+1):
        if k%2==0: text("%.2f"%(k*STEP),((x0)*STEP-0.03,-0.01,k*STEP))
    ext=max(dims.x,dims.z)
    campos=(center.x, center.y-ext*3, center.z)
    ortho=ext*1.25
elif VIEW=='top':  # X horizontal, Y vertical(ish), camera +Z
    x0=int(mn.x/STEP)-1; x1=int(mx.x/STEP)+1
    y0=int(mn.y/STEP)-1; y1=int(mx.y/STEP)+1
    for i in range(x0,x1+1): line((i*STEP,y0*STEP,0),(i*STEP,y1*STEP,0))
    for k in range(y0,y1+1): line((x0*STEP,k*STEP,0),(x1*STEP,k*STEP,0))
    for i in range(x0,x1+1):
        if i%2==0: text("%.2f"%(i*STEP),(i*STEP,(y0)*STEP-0.02,0.01))
    for k in range(y0,y1+1):
        if k%2==0: text("%.2f"%(k*STEP),((x0)*STEP-0.03,k*STEP,0.01))
    ext=max(dims.x,dims.y)
    campos=(center.x, center.y, mx.z+ext*3)
    ortho=ext*1.25
else:  # front: Y horizontal, Z vertical, camera +X
    y0=int(mn.y/STEP)-1; y1=int(mx.y/STEP)+1
    z0=int(mn.z/STEP)-1; z1=int(mx.z/STEP)+1
    for k in range(y0,y1+1): line((0,k*STEP,z0*STEP),(0,k*STEP,z1*STEP))
    for j in range(z0,z1+1): line((0,y0*STEP,j*STEP),(0,y1*STEP,j*STEP))
    ext=max(dims.y,dims.z)
    campos=(mx.x+ext*3, center.y, center.z)
    ortho=ext*1.25

# lights
bpy.ops.object.light_add(type='SUN', location=(5,-5,10)); bpy.context.active_object.data.energy=4
bpy.ops.object.light_add(type='SUN', location=(-3,-2,8)); bpy.context.active_object.data.energy=2

bpy.ops.object.camera_add(location=campos)
cam=bpy.context.active_object
d=Vector(center)-Vector(campos)
# choose up so text reads upright
up='Y'
if VIEW=='top': up='Y'
cam.rotation_euler=d.to_track_quat('-Z',up).to_euler()
cam.data.type='ORTHO'; cam.data.ortho_scale=ortho
bpy.context.scene.camera=cam
sc=bpy.context.scene
sc.render.engine='BLENDER_EEVEE'
sc.render.resolution_x=1400; sc.render.resolution_y=1400
w=bpy.data.worlds.new("w"); w.use_nodes=True
w.node_tree.nodes["Background"].inputs[0].default_value=(0.95,0.95,0.97,1)
sc.world=w
# texts must face camera; rotate all text to lie flat facing camera
for o in bpy.context.scene.objects:
    if o.type=='FONT':
        o.rotation_euler=d.to_track_quat('-Z',up).to_euler()
sc.render.filepath=OUT
bpy.ops.render.render(write_still=True)
print("MEASURE DONE", OUT)
