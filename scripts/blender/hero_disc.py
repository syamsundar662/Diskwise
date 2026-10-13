"""Builds the Diskwise hero disc in Blender and renders it with a transparent background.

A thick bevelled glass disc, a frosted white hub with a small drive shape on top,
and a ring of glowing tick marks between hub and rim (the app's signature ring).

Run headless:
  /Applications/Blender.app/Contents/MacOS/Blender -b -P scripts/blender/hero_disc.py -- \
      --tint 0.30,0.40,1.0 --glow 0.45,0.80,1.0 --progress 0.72 \
      --out Resources/Art/disc-care.png --blend scripts/blender/disc-care.blend

Options (all optional):
  --tint r,g,b      glass color (linear 0..1)
  --glow r,g,b      tick color
  --progress f      share of ticks lit, 0..1
  --size px         square render size (default 1024)
  --samples n       Cycles samples (default 256)
  --out path        PNG to write
  --blend path      also save the scene here
"""

import math
import sys

import bpy

# MARK: Options

args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []


def option(name, default):
    flag = "--" + name
    return args[args.index(flag) + 1] if flag in args else default


def color(text):
    r, g, b = (float(v) for v in text.split(","))
    return (r, g, b, 1.0)


TINT = color(option("tint", "0.30,0.40,1.0"))
GLOW = color(option("glow", "0.25,0.72,1.0"))
PROGRESS = float(option("progress", "0.72"))
SIZE = int(option("size", "1024"))
SAMPLES = int(option("samples", "256"))
OUT = option("out", "/tmp/disc.png")
BLEND = option("blend", None)
TICKS = 48

# MARK: Scene

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.render.engine = "CYCLES"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.render.resolution_x = SIZE
scene.render.resolution_y = SIZE
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.render.image_settings.color_depth = "8"
# Standard keeps the glow saturated (AgX washes bright colors toward white).
scene.view_settings.view_transform = "Standard"
scene.view_settings.exposure = -0.3
try:
    scene.view_settings.look = "Medium High Contrast"
except TypeError:
    pass

# Use the Apple GPU when available.
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for device in prefs.devices:
        device.use = True
    scene.cycles.device = "GPU"
except Exception as error:  # CPU still works, just slower
    print("Diskwise: GPU not available, rendering on CPU:", error)


def principled(name, **inputs):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    node = mat.node_tree.nodes["Principled BSDF"]
    for key, value in inputs.items():
        if key in node.inputs:
            node.inputs[key].default_value = value
    return mat


def absorbing(mat, rgba, density):
    """Colors light passing through the glass, so thicker parts look deeper."""
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    volume = nodes.new("ShaderNodeVolumeAbsorption")
    volume.inputs["Color"].default_value = rgba
    volume.inputs["Density"].default_value = density
    links.new(volume.outputs["Volume"], nodes["Material Output"].inputs["Volume"])
    return mat


def emissive(name, rgba, strength):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    node = mat.node_tree.nodes["Principled BSDF"]
    node.inputs["Base Color"].default_value = rgba
    node.inputs["Emission Color"].default_value = rgba
    node.inputs["Emission Strength"].default_value = strength
    node.inputs["Roughness"].default_value = 0.2
    return mat


def mix(a, b, t):
    return tuple(a[i] * (1 - t) + b[i] * t for i in range(3)) + (1.0,)


WHITE = (1.0, 1.0, 1.0, 1.0)
glass = absorbing(principled("Glass", **{
    "Base Color": TINT, "Roughness": 0.02, "IOR": 1.5,
    "Transmission Weight": 1.0, "Coat Weight": 1.0, "Coat Roughness": 0.0,
    "Emission Color": TINT, "Emission Strength": 0.12,
}), TINT, 1.6)
# Dark glossy glass with a soft inner glow: the lights only add highlights, not a wash.
face = principled("Face", **{
    "Base Color": mix(TINT, (0, 0, 0, 1), 0.8), "Roughness": 0.04, "IOR": 1.5,
    "Coat Weight": 1.0, "Coat Roughness": 0.0,
    "Emission Color": TINT, "Emission Strength": 0.16,
})
frosted = principled("Frosted", **{
    "Base Color": (0.92, 0.94, 1.0, 1.0), "Roughness": 0.42, "IOR": 1.45,
    "Transmission Weight": 0.25, "Subsurface Weight": 0.35, "Coat Weight": 0.6, "Coat Roughness": 0.2,
})
glyph = principled("Glyph", **{
    "Base Color": mix(TINT, WHITE, 0.62), "Roughness": 0.12, "Coat Weight": 1.0,
})
lit = emissive("TickLit", GLOW, 2.2)
dim = principled("TickDim", **{"Base Color": mix(TINT, WHITE, 0.55), "Roughness": 0.2,
                               "Transmission Weight": 0.6, "Emission Color": TINT, "Emission Strength": 0.15})


def finish(obj, material, bevel=0.0, segments=8):
    obj.data.materials.append(material)
    if bevel > 0:
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.limit_method = "ANGLE"
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(40))
    except Exception:
        bpy.ops.object.shade_smooth()
    obj.select_set(False)
    return obj


root = bpy.data.objects.new("Disc", None)
scene.collection.objects.link(root)


def cylinder(name, radius, depth, z, material, bevel):
    bpy.ops.mesh.primitive_cylinder_add(vertices=160, radius=radius, depth=depth, location=(0, 0, z))
    obj = bpy.context.active_object
    obj.name = name
    obj.parent = root
    return finish(obj, material, bevel, 10)


# MARK: Model

BODY_H = 0.30
top = BODY_H / 2
cylinder("Body", 1.0, BODY_H, 0, glass, 0.11)
cylinder("Face", 0.84, 0.06, top - 0.018, face, 0.02)
cylinder("Hub", 0.40, 0.17, top + 0.07, frosted, 0.06)

# A small drive shape on the hub.
bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, top + 0.175))
drive = bpy.context.active_object
drive.name = "Drive"
drive.scale = (0.34, 0.20, 0.06)
drive.parent = root
bpy.ops.object.transform_apply(scale=True)
finish(drive, glyph, 0.035, 6)
bpy.ops.mesh.primitive_cube_add(size=1, location=(0.05, -0.1005, top + 0.18))
slot = bpy.context.active_object
slot.name = "DriveLights"
slot.scale = (0.16, 0.012, 0.016)
slot.parent = root
bpy.ops.object.transform_apply(scale=True)
finish(slot, lit, 0.008, 3)

# The tick ring.
lit_count = round(PROGRESS * TICKS)
for i in range(TICKS):
    angle = -2 * math.pi * i / TICKS + math.pi / 2  # clockwise from 12 o'clock
    r = 0.62
    bpy.ops.mesh.primitive_cube_add(size=1, location=(r * math.cos(angle), r * math.sin(angle), top + 0.018))
    tick = bpy.context.active_object
    tick.name = f"Tick{i:02d}"
    tick.scale = (0.024, 0.10, 0.022)
    tick.rotation_euler = (0, 0, angle - math.pi / 2)
    tick.parent = root
    bpy.ops.object.transform_apply(scale=True)
    finish(tick, lit if i < lit_count else dim, 0.009, 3)

# Three-quarter view, tilted toward the camera like the app's hero art.
root.rotation_euler = (math.radians(58), math.radians(-8), math.radians(-22))

# MARK: Camera and light

cam_data = bpy.data.cameras.new("Camera")
cam_data.lens = 85
cam = bpy.data.objects.new("Camera", cam_data)
cam.location = (0, -7.4, 0.15)
cam.rotation_euler = (math.radians(90), 0, 0)
scene.collection.objects.link(cam)
scene.camera = cam


def area(name, location, size, energy, rgb=(1, 1, 1)):
    data = bpy.data.lights.new(name, "AREA")
    data.size = size
    data.energy = energy
    data.color = rgb
    obj = bpy.data.objects.new(name, data)
    obj.location = location
    direction = -obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.collection.objects.link(obj)


area("Key", (-3.5, -3.5, 4.5), 2.0, 420, (1.0, 0.98, 0.96))
area("Rim", (3.5, 3.0, 2.5), 3.0, 700, mix(TINT, WHITE, 0.6)[:3])
area("Fill", (3.5, -4.0, -0.5), 5.0, 80, (0.9, 0.95, 1.0))


def strip(name, location, scale, strength):
    """A bright panel seen only in reflections and refractions: the white streaks on glass."""
    bpy.ops.mesh.primitive_plane_add(size=1, location=location)
    plane = bpy.context.active_object
    plane.name = name
    plane.scale = scale
    plane.rotation_euler = (-plane.location).to_track_quat("Z", "Y").to_euler()
    mat = emissive(name + "Light", WHITE, strength)
    plane.data.materials.append(mat)
    plane.visible_camera = False
    plane.visible_shadow = False


strip("StripLeft", (-3.2, -1.5, 1.2), (0.35, 4.0, 1), 7)
strip("StripTop", (0.4, -0.6, 3.6), (4.0, 0.3, 1), 5)
strip("StripRight", (3.0, -2.2, -0.4), (0.25, 3.0, 1), 3)

# World: a soft vertical gradient the glass can refract and reflect (the camera sees transparency).
world = bpy.data.worlds.new("World")
scene.world = world
world.use_nodes = True
nodes, links = world.node_tree.nodes, world.node_tree.links
background = nodes["Background"]
coords = nodes.new("ShaderNodeTexCoord")
split = nodes.new("ShaderNodeSeparateXYZ")
ramp = nodes.new("ShaderNodeValToRGB")
ramp.color_ramp.elements[0].position = 0.35
ramp.color_ramp.elements[0].color = mix(TINT, (0, 0, 0, 1), 0.92)
ramp.color_ramp.elements[1].position = 0.8
ramp.color_ramp.elements[1].color = mix(TINT, (0, 0, 0, 1), 0.7)
links.new(coords.outputs["Generated"], split.inputs["Vector"])
links.new(split.outputs["Z"], ramp.inputs["Fac"])
links.new(ramp.outputs["Color"], background.inputs["Color"])
background.inputs["Strength"].default_value = 1.0

# MARK: Framing: center the disc and make it fill 80 percent of the frame.

from bpy_extras.object_utils import world_to_camera_view


def projected_bounds():
    bpy.context.view_layer.update()
    depsgraph = bpy.context.evaluated_depsgraph_get()
    xs, ys = [], []
    for obj in root.children:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.to_mesh()
        for vertex in mesh.vertices:
            point = world_to_camera_view(scene, cam, evaluated.matrix_world @ vertex.co)
            xs.append(point.x)
            ys.append(point.y)
        evaluated.to_mesh_clear()
    return min(xs), max(xs), min(ys), max(ys)


x0, x1, y0, y1 = projected_bounds()
cam_data.lens *= 0.80 / max(x1 - x0, y1 - y0)
x0, x1, y0, y1 = projected_bounds()
cam_data.shift_x += (x0 + x1) / 2 - 0.5
cam_data.shift_y += (y0 + y1) / 2 - 0.5

# MARK: Render

scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("Diskwise: rendered", OUT)
if BLEND:
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("Diskwise: saved", BLEND)
