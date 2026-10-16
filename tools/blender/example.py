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

def bake_base_color(obj, material, size=64):
    """Bake a procedural Base Color into a UV image, without scene lighting.

    Input node colors are scene-linear. Let Blender handle the sRGB image
    encoding: do not manually gamma-correct image.pixels or bake lighting.
    This example's cube already has UVs; unwrap other meshes first.
    """
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = 1
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    image = bpy.data.images.new(material.name + 'BaseColor', width=size, height=size, alpha=False)
    image.colorspace_settings.name = 'sRGB'
    target = material.node_tree.nodes.new('ShaderNodeTexImage')
    target.image = image
    material.node_tree.nodes.active = target
    bpy.ops.object.bake(type='DIFFUSE', pass_filter={'COLOR'}, margin=2)
    # Replace the live procedural input; glTF exports this recognized graph.
    shader = material.node_tree.nodes.get('Principled BSDF')
    material.node_tree.links.new(target.outputs['Color'], shader.inputs['Base Color'])
    image.pack()
    return image

asset = empty('AssetRoot', (0, 0, 0))
body = box('Body', (0, 0, 1), (1, 1, 2), (0.2, 0.5, 0.8, 1), asset)
material = body.data.materials[0]
noise = material.node_tree.nodes.new('ShaderNodeTexNoise')
noise.inputs['Scale'].default_value = 5
ramp = material.node_tree.nodes.new('ShaderNodeValToRGB')
ramp.color_ramp.elements[0].color = (0.04, 0.16, 0.36, 1)
ramp.color_ramp.elements[1].color = (0.16, 0.36, 0.64, 1)
material.node_tree.links.new(noise.outputs['Fac'], ramp.inputs['Fac'])
material.node_tree.links.new(ramp.outputs['Color'], material.node_tree.nodes['Principled BSDF'].inputs['Base Color'])
bake_base_color(body, material)
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
