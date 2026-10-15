"""Small background bpy entry point. Generated scripts remain ordinary Python."""
import json
import os
from pathlib import Path
import runpy
import sys
import bpy

config = json.loads(Path(sys.argv[sys.argv.index('--') + 1]).read_text(encoding='utf-8'))
os.chdir(config['workspace'])
if config.get('blend'):
    bpy.ops.wm.open_mainfile(filepath=config['blend'], load_ui=False, use_scripts=False)
if config.get('script'):
    # Hide private CLI arguments from the player's reusable asset script.
    sys.argv = [config['script']]
    sys.path.insert(0, config['workspace'])
    runpy.run_path(config['script'], run_name='__main__')

scene = bpy.context.scene
if config.get('render'):
    if scene.camera is None:
        raise RuntimeError('Set scene.camera in the bpy script before requesting a render.')
    scene.render.image_settings.file_format = 'PNG'
    scene.render.filepath = config['render']
    bpy.ops.render.render(write_still=True)

objects = list(scene.objects)
report = {
    'blender_version': bpy.app.version_string,
    'object_count': len(objects),
    'objects_truncated': len(objects) > 256,
    'objects': [{
        'name': o.name, 'type': o.type,
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
