"""Copy into the game's art/build.py and adapt. Blender Z-up -> Godot Y-up.
FrontMarker lies toward Blender -Y (Godot +Z); RightMarker toward +X.
Keep animated accessories parented under their named pivot, not as siblings.
"""
from pathlib import Path
import bpy
from mathutils import Vector

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def empty(name, location, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.parent = parent
    obj.location = location
    return obj

def box(name, location, scale, color, parent):
    bpy.ops.mesh.primitive_cube_add(size=1)
    obj = bpy.context.object
    obj.name = name
    obj.parent = parent
    obj.location = location
    obj.scale = scale
    material = bpy.data.materials.new(name + 'Material')
    material.use_nodes = True
    material.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = color
    obj.data.materials.append(material)
    return obj

asset = empty('AssetRoot', (0, 0, 0))
box('Body', (0, 0, 1), (1, 1, 2), (0.2, 0.5, 0.8, 1), asset)
head_pivot = empty('HeadPivot', (0, 0, 2), asset)
box('Head', (0, 0, 0.4), (0.8, 0.8, 0.8), (0.9, 0.7, 0.4, 1), head_pivot)
box('FrontMarker', (0, -1, 1), (0.4, 0.4, 0.4), (0.9, 0.1, 0.1, 1), asset)
box('RightMarker', (2, 0, 1), (0.4, 0.4, 0.4), (0.1, 0.9, 0.1, 1), asset)

# Preview-only camera/lights are deliberately excluded from the export.
bpy.ops.object.camera_add(location=(6, -8, 5))
camera = bpy.context.object
camera.name = 'PreviewCamera'
camera.rotation_euler = (Vector((0.5, 0, 1.2)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
scene = bpy.context.scene
scene.camera = camera
for location, energy in [((2, -4, 6), 900), ((-4, 1, 4), 650)]:
    bpy.ops.object.light_add(type='AREA', location=location)
    lamp = bpy.context.object
    lamp.name = 'PreviewLight'
    lamp.data.energy = energy
    lamp.data.shape = 'DISK'
    lamp.data.size = 5
    lamp.rotation_euler = (Vector((0, 0, 1)) - lamp.location).to_track_quat('-Z', 'Y').to_euler()
scene.world.color = (0.15, 0.15, 0.15)
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 8
scene.render.resolution_x = 512
scene.render.resolution_y = 512
scene.render.resolution_percentage = 100

out = Path.cwd() / 'art'
out.mkdir(exist_ok=True)
bpy.ops.wm.save_as_mainfile(filepath=str(out / 'source.blend'))
bpy.ops.object.select_all(action='DESELECT')
for obj in [asset, *asset.children_recursive]:
    obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out / 'model.glb'), export_format='GLB',
                          use_selection=True, export_yup=True,
                          export_cameras=False, export_lights=False)
