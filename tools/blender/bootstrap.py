"""Small background bpy entry point. Generated scripts remain ordinary Python."""
import json
import os
from pathlib import Path
import hashlib
import sys
import bpy
from mathutils import Vector

config = json.loads(Path(sys.argv[sys.argv.index('--') + 1]).read_text(encoding='utf-8'))
os.chdir(config['workspace'])
if config.get('blend'):
    bpy.ops.wm.open_mainfile(filepath=config['blend'], load_ui=False, use_scripts=False)
# Private job preferences only; do not litter the game with source.blend1 files.
bpy.context.preferences.filepaths.save_version = 0
if config.get('script'):
    # Hide private CLI arguments from the player's reusable asset script.
    sys.argv = [config['script']]
    sys.path.insert(0, config['workspace'])
    source = Path(config['script']).read_bytes()
    if hashlib.sha256(source).hexdigest() != config.get('script_sha256'):
        raise RuntimeError('Approved Python snapshot changed; request fresh player approval.')
    exec(compile(source, config['script'], 'exec'), {'__name__': '__main__', '__file__': config['script']})

scene = bpy.context.scene
if config.get('render'):
    if scene.camera is None:
        raise RuntimeError('Set scene.camera in the bpy script before requesting a render.')
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = config['render']
    bpy.ops.render.render(write_still=True)

objects = list(scene.objects)
mesh_objects = [o for o in objects if o.type == 'MESH']
corners = [o.matrix_world @ Vector(c) for o in mesh_objects for c in o.bound_box]

def material_advisories():
    """Bounded hints about live shader graphs, not an export validity verdict."""
    materials = {slot.material for obj in mesh_objects for slot in obj.material_slots if slot.material}
    findings = []
    procedural = {'TEX_NOISE', 'TEX_VORONOI', 'TEX_MUSGRAVE', 'TEX_WAVE',
                  'TEX_MAGIC', 'TEX_BRICK', 'TEX_CHECKER', 'TEX_GRADIENT', 'TEX_WHITE_NOISE'}
    ordered = sorted(materials, key=lambda m: m.name)
    for material in ordered[:64]:
        if not material.use_nodes or not material.node_tree:
            continue
        pending = [n for n in material.node_tree.nodes if n.type == 'OUTPUT_MATERIAL' and n.is_active_output]
        visited, risky = set(), set()
        while pending and len(visited) < 256:
            node = pending.pop()
            if node in visited:
                continue
            visited.add(node)
            if node.type in procedural or node.type in {'GROUP', 'SCRIPT'} or (node.type.startswith('BSDF_') and node.type != 'BSDF_PRINCIPLED'):
                risky.add(node.bl_idname)
            for socket in node.inputs:
                pending.extend(link.from_node for link in socket.links)
        if risky or pending:
            findings.append({'material': material.name[:128], 'nodes': sorted(risky)[:8],
                             'message': 'Connected procedural/custom shaders may not survive glTF export. Bake to image textures and inspect the imported game.' if risky else 'Shader graph exceeds the inspection budget; verify its exported appearance.'})
        if len(findings) == 16:
            break
    return findings, len(ordered) > 64 or len(findings) == 16

advisories, advisory_limit = material_advisories()
# Discover ordinary output artifacts without traversing the entire game/history.
artifacts = []
directories = {Path(config['workspace']) / 'art'}
if config.get('render'):
    directories.add(Path(config['render']).parent)
for directory in sorted(directories):
    if directory.is_dir() and not directory.is_symlink():
        for path in sorted(directory.iterdir()):
            if len(artifacts) >= 64:
                break
            if path.suffix.lower() in {'.glb', '.blend', '.png'} and path.is_file() and not path.is_symlink():
                artifacts.append({'path': str(path.relative_to(config['workspace'])), 'bytes': path.stat().st_size})
report = {
    'blender_version': bpy.app.version_string,
    'object_count': len(objects),
    'mesh_count': len(mesh_objects),
    'vertices': sum(len(o.data.vertices) for o in mesh_objects),
    'polygons': sum(len(o.data.polygons) for o in mesh_objects),
    'world_bounds': {'min': [min(c[i] for c in corners) for i in range(3)], 'max': [max(c[i] for c in corners) for i in range(3)]} if corners else None,
    'artifacts': artifacts,
    'material_advisories': advisories,
    'material_inspection_limited': advisory_limit,
    'objects_truncated': len(objects) > 256,
    'objects': [{
        'name': o.name, 'type': o.type,
        'parent': o.parent.name if o.parent else None,
        'world_location': list(o.matrix_world.translation),
        'location': list(o.location), 'dimensions': list(o.dimensions),
        'vertices': len(o.data.vertices) if o.type == 'MESH' else None,
        'polygons': len(o.data.polygons) if o.type == 'MESH' else None,
        'materials': [s.material.name if s.material else None for s in o.material_slots],
    } for o in objects[:256]],
    'camera': scene.camera.name if scene.camera else None,
    'engine': scene.render.engine,
    'resolution': [scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage],
    'frame_range': [scene.frame_start, scene.frame_end],
    'render': config.get('render'),
}
Path(config['directory'], 'report.json').write_text(json.dumps(report), encoding='utf-8')
