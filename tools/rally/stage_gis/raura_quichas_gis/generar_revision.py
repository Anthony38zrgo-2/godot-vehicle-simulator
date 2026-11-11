from pathlib import Path
from collections import defaultdict
import heapq
import json
import math
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

BASE = Path(__file__).resolve().parent
OUT = BASE / 'output'
CRS = 'EPSG:32718'


def dump(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding='utf8')


def prepare():
    import numpy as np
    import rasterio as rio
    from rasterio.warp import transform
    from PIL import Image, ImageDraw

    def load(path):
        return json.loads((BASE / path).read_text(encoding='utf8'))

    def project(coords, source='EPSG:4326', target=CRS):
        x, y = zip(*coords)
        return list(zip(*transform(source, target, x, y)))

    roads = BASE / 'data/roads'
    root = ET.parse(roads / 'raura_quichas_highways.osm').getroot()
    nodes = {int(n.get('id')): (float(n.get('lon')), float(n.get('lat'))) for n in root.findall('node')}
    ids = {xy: n for n, xy in nodes.items()}
    candidate = load('data/roads/route_osm_candidate.geojson')['features'][0]
    route = [ids[tuple(xy)] for xy in candidate['geometry']['coordinates']]
    ends = [f['geometry']['coordinates'] for f in load('endpoints.geojson')['features']]
    origin = project(ends)[0]
    xy = dict(zip(nodes, project(list(nodes.values()))))
    assert max(math.dist(a, b) for a,b in zip(ends,project(project(ends),CRS,'EPSG:4326'))) < 1e-8
    adjacency = defaultdict(lambda: defaultdict(list))
    graph = defaultdict(dict)
    ways = []
    excluded = {'footway','cycleway','steps','pedestrian','bridleway','path','proposed','construction','platform','corridor'}
    for way in root.findall('way'):
        tags = {t.get('k'): t.get('v') for t in way.findall('tag')}
        refs = [int(n.get('ref')) for n in way.findall('nd')]
        if len(refs) < 2:
            continue
        record = {'way': int(way.get('id')), 'tags': tags}
        ways.append(refs)
        for a,b in zip(refs,refs[1:]):
            adjacency[a][b].append(record)
            adjacency[b][a].append(record)
            if tags.get('highway') not in excluded and tags.get('access') not in {'no','private'} and tags.get('motor_vehicle') not in {'no','private'}:
                direction = tags.get('oneway')
                if direction != '-1':
                    graph[a][b] = math.dist(xy[a], xy[b])
                if direction not in {'yes','1','true'} and tags.get('junction') != 'roundabout' or direction == '-1':
                    graph[b][a] = math.dist(xy[a], xy[b])

    def shortest(banned):
        queue = [(0, route[0])]
        best = {route[0]: 0}
        parent = {}
        while queue:
            cost, a = heapq.heappop(queue)
            if cost != best[a]:
                continue
            if a == route[-1]:
                path = [a]
                while path[-1] in parent:
                    path.append(parent[path[-1]])
                return cost, tuple(reversed(path))
            for b, length in graph[a].items():
                if (a,b) != banned and cost + length < best.get(b, math.inf):
                    best[b] = cost + length
                    parent[b] = a

    alternatives = set()
    blocked = 0
    for edge in zip(route, route[1:]):
        blocked += edge[1] not in graph[edge[0]]
        result = shortest(edge)
        if result and result[1] != tuple(route):
            alternatives.add(result)
    alternatives = sorted(alternatives)
    OUT.mkdir(exist_ok=True)
    dem_path = BASE / 'data/terrain/raura_copernicus_glo30_utm18s.tif'
    sat_path = BASE / 'data/satellite/raura_sentinel2_rgb_10m_utm18s.tif'
    with rio.open(dem_path) as dem, rio.open(sat_path) as sat:
        terrain = dem.read(1, masked=True)
        rgb = sat.read([1,2,3])
        coverage = sat.dataset_mask()
        rgba = np.dstack((rgb.transpose(1,2,0), coverage))
        Image.fromarray(rgba).save(OUT / 'sentinel.png')
        west,south,east,north = sat.bounds
        z0 = float(next(dem.sample([origin]))[0])

        def local(point, z):
            return [point[0]-origin[0], point[1]-origin[1], z-z0]

        def elevation(point):
            v = next(dem.sample([point], masked=True))[0]
            return None if np.ma.is_masked(v) else float(v)

        def curve(refs):
            result = []
            for node in refs:
                z = elevation(xy[node])
                result.append(local(xy[node], z) if z is not None else None)
            return result

        vertices = []
        for row,col in np.ndindex(terrain.shape):
            vertices.append(local(dem.xy(row,col), z0 if terrain.mask is not np.ma.nomask and terrain.mask[row,col] else float(terrain[row,col])))
        valid = ~np.ma.getmaskarray(terrain)
        faces = []
        for row,col in np.ndindex((dem.height-1,dem.width-1)):
            if valid[row:row+2,col:col+2].all():
                i = row*dem.width+col
                faces.append([i,i+dem.width,i+dem.width+1,i+1])

        def pixel(point):
            row,col = sat.index(*point)
            return col,row

        def has_image(point):
            col,row = pixel(point)
            return 0 <= row < sat.height and 0 <= col < sat.width and bool(coverage[row,col])

        observations = {
            5396244052: ('ambiguo', 'Empalme de servicio a 14 m de C02, apenas 1,4 pixeles Sentinel.'),
            5396244053: ('visible_parcial', 'La traza clara al este coincide con LM-599. El empalme exacto queda ambiguo.'),
            5351308855: ('ambiguo', 'En la cantera, la imagen no separa con claridad LM-599 de las superficies removidas.'),
            5351308851: ('visible_parcial', 'Se distingue un corredor hacia el suroeste. Su union exacta junto a la meta queda ambigua.'),
        }
        features, markers, profile = [], [], []
        pk = 0
        for i,node in enumerate(route):
            if i:
                pk += math.dist(xy[node],xy[route[i-1]])
            z = elevation(xy[node])
            profile.append((round(pk,2), z))
            neighbors = set(adjacency[node]) - set(route[max(0,i-1):i+2])
            if not neighbors:
                continue
            key = f'C{len(features)+1:02d}'
            properties = {'id':key,'node':node,'pk_m':round(pk,2),'sentinel':has_image(xy[node]),
                'ramales':[{'node':n,'ways':adjacency[node][n]} for n in sorted(neighbors)],
                'status':'pendiente_revision_visual' if has_image(xy[node]) else 'sin_cobertura'}
            if properties['sentinel'] and node in observations:
                properties['status'], properties['evidencia'] = observations[node]
            features.append({'type':'Feature','geometry':{'type':'Point','coordinates':nodes[node]},'properties':properties})
            markers.append({'label':f'{key}  {pk/1000:.2f} km','xyz':local(xy[node],z if z is not None else z0)})
        dump(OUT/'cruces.geojson',{'type':'FeatureCollection','features':features})
        (OUT/'perfil_dsm.csv').write_text('pk_m,z_dsm_m\n'+''.join(f'{s},{z if z is not None else ""}\n' for s,z in profile),encoding='utf8')
        map_image = Image.new('RGB',(sat.width,sat.height),'#30243c')
        map_image.paste(Image.fromarray(rgba),mask=Image.fromarray(coverage))
        draw = ImageDraw.Draw(map_image)
        for refs in ways:
            draw.line([pixel(xy[n]) for n in refs],fill='#94d5ff',width=1)
        for _,refs in alternatives:
            draw.line([pixel(xy[n]) for n in refs],fill='#ffb050',width=3)
        draw.line([pixel(xy[n]) for n in route],fill='#34f586',width=3)
        unlabelled = map_image.copy()
        for feature in features:
            p = feature['properties']
            x,y = pixel(xy[p['node']])
            draw.ellipse((x-4,y-4,x+4,y+4),fill='white',outline='black')
            draw.text((x+5,y-10),p['id'],fill='white',stroke_width=2,stroke_fill='black')
        for label,point in zip(('SALIDA','META'),project(ends)):
            draw.text(pixel(point),label,fill='white',stroke_width=2,stroke_fill='black')
        map_image.save(OUT/'mapa_revision.png')
        for feature in features:
            p = feature['properties']
            x,y = pixel(xy[p['node']])
            crop=unlabelled.crop((x-45,y-45,x+45,y+45)).resize((540,540),Image.Resampling.NEAREST)
            overlay=ImageDraw.Draw(crop)
            overlay.ellipse((261,261,279,279),outline='white',width=2)
            overlay.text((12,12),f"{p['id']} | PK {p['pk_m']:.1f} m | norte arriba",fill='white',stroke_width=2,stroke_fill='black')
            crop.save(OUT/f"{p['id']}.png")

        report = [
            '# Rally Raura — Etapa 1', '',
            f'Eje OSM original: 8.299,1 m. Longitud 2D UTM: {pk:.1f} m. Diferencia: {pk-8299.1:+.1f} m.',
            f'Ajustes UTM de extremos: {math.dist(project(ends)[0],xy[route[0]]):.1f} m y {math.dist(project(ends)[1],xy[route[-1]]):.1f} m.',
            f'DSM en extremos del eje: {profile[0][1]} y {profile[-1][1]} m. Ver perfil_dsm.csv. Es un modelo de superficie de 30 m, no una rasante medida.',
            f'Cruces con ramal OSM: {len(features)}. Aristas del candidato incompatibles con el filtro básico de acceso/sentido: {blocked}.',
            'El filtro considera etiquetas presentes, sin inferir accesos que OSM no indica ni comprobar restricciones de giro.',
            f'Alternativas conectadas encontradas al retirar una arista del candidato: {len(alternatives)}.',
            'Este método encuentra desvíos más cortos para esas exclusiones. No enumera todos los itinerarios posibles.',
            *[f'- Alternativa {i}: {d:.1f} m' for i,(d,_) in enumerate(alternatives,1)],
            '', 'Ver mapa_revision.png y los recortes Cxx.png. Verde: candidato. Naranja: alternativas. Celeste: otras vías. Morado: imagen sin datos.',
            '', '## Revision visual de Sentinel-2',
            *[f"- {p['id']} (PK {p['pk_m']:.1f} m, {p['status']}): {p.get('evidencia','Revisar cobertura.')}" for p in (f['properties'] for f in features)],
            '',
            f'Descenso neto DSM: {profile[0][1]-profile[-1][1]:.0f} m.',
            'La diferencia de distancia corresponde al mismo eje medido en UTM frente a la aproximacion esferica original.',
            'La longitud sigue provisional. Para cerrar los empalmes, usar imagen de mayor resolucion, GPX o puntos de paso.',
            'Fuentes: © OpenStreetMap contributors, Copernicus DEM GLO-30 y Sentinel-2. Metadatos originales en data/.',
            '', 'Regeneración desde la carpeta del paquete: .venv/Scripts/python.exe generar_revision.py',
            'Herramientas: Blender 5.2/bpy, Rasterio y Pillow. Se usan las convenciones GeoScene de BlenderGIS. El tooling de pacenotes analiza carreteras construidas y no se requiere para esta revisión GIS.',
        ]
        (OUT/'revision.md').write_text('\n'.join(report)+'\n',encoding='utf8')
        payload = {'origin':origin,'z0':z0,'ends_geo':ends,'terrain':vertices,'faces':faces,
            'bounds':[west-origin[0],south-origin[1],east-origin[0],north-origin[1]],
            'roads':[curve(refs) for refs in ways],'route':curve(route),'alternatives':[curve(r) for _,r in alternatives],
            'markers':markers,'ends':[]}
        for name,p,n in zip(('SALIDA','META'),project(ends),(route[0],route[-1])):
            for label,pt in [(name+' solicitada',p),(name+' OSM',xy[n])]:
                z=elevation(pt)
                payload['ends'].append({'label':label,'xyz':local(pt,z if z is not None else z0)})
        dump(OUT/'scene_input.json',payload)


def build():
    import bpy
    from mathutils import Quaternion, Vector

    data = json.loads((OUT/'scene_input.json').read_text(encoding='utf8'))
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene['SRID'] = CRS
    scene['scale'] = 1.0
    bpy.context.preferences.filepaths.save_version = 0
    scene['crs x'],scene['crs y'] = data['origin']
    scene['longitude'],scene['latitude'] = data['ends_geo'][0]
    scene['raura_z_origin_m'] = data['z0']

    def collection(name,parent):
        c=bpy.data.collections.new(name)
        parent.children.link(c)
        return c

    def material(name,color):
        m=bpy.data.materials.new(name)
        m.diffuse_color=color
        return m

    def mesh(name, verts, faces, coll, mat):
        m=bpy.data.meshes.new(name)
        m.from_pydata(verts,[],faces)
        m.update()
        m.materials.append(mat)
        o=bpy.data.objects.new(name,m)
        coll.objects.link(o)
        return o

    image=bpy.data.images.load(str(OUT/'sentinel.png'))
    image.pack()
    photo=material('Sentinel RGB',(0.4,0.4,0.4,1))
    photo.use_nodes=True
    nt=photo.node_tree
    tex=nt.nodes.new('ShaderNodeTexImage')
    tex.image=image
    em=nt.nodes.new('ShaderNodeEmission')
    mix=nt.nodes.new('ShaderNodeMixRGB')
    mix.inputs[1].default_value=(0.09,0.045,0.12,1)
    nt.links.new(tex.outputs['Alpha'],mix.inputs[0])
    nt.links.new(tex.outputs['Color'],mix.inputs[2])
    nt.links.new(mix.outputs[0],em.inputs['Color'])
    nt.links.new(em.outputs[0],nt.nodes.get('Material Output').inputs['Surface'])
    w,s,e,n=data['bounds']

    def uv_image(obj):
        uv=obj.data.uv_layers.new()
        for i,loop in enumerate(obj.data.loops):
            x,y,_=obj.data.vertices[loop.vertex_index].co
            uv.data[i].uv=((x-w)/(e-w),(y-s)/(n-s))

    flat_z=min(v[2] for v in data['terrain'])-15
    for is_flat in (True,False):
        mode=collection('01 Mapa plano' if is_flat else '02 Relieve DSM',scene.collection)
        mode.hide_viewport=not is_flat
        mode.hide_render=not is_flat
        terrain=collection('Imagen Sentinel' if is_flat else 'Terreno con imagen Sentinel',mode)
        if is_flat:
            obj=mesh('Imagen UTM',[(w,s,flat_z),(e,s,flat_z),(e,n,flat_z),(w,n,flat_z)],[(0,1,2,3)],terrain,photo)
        else:
            obj=mesh('Terreno DSM 30 m',data['terrain'],data['faces'],terrain,photo)
        uv_image(obj)

        def lines(name, paths, color, radius, offset):
            coll=collection(name,mode)
            mat=material(name,color)
            cu=bpy.data.curves.new(name,'CURVE')
            cu.dimensions='3D'
            cu.bevel_depth=radius
            cu.bevel_resolution=1
            for path in paths:
                run=[]
                for p in [*path,None]:
                    if p is not None:
                        x,y,z=p
                        run.append((x,y,(flat_z if is_flat else z)+offset,1))
                    else:
                        if len(run)>=2:
                            spl=cu.splines.new('POLY')
                            spl.points.add(len(run)-1)
                            for point,co in zip(spl.points,run):
                                point.co=co
                        run=[]
            cu.materials.append(mat)
            coll.objects.link(bpy.data.objects.new(name,cu))

        lines('Red OSM',data['roads'],(.15,.60,1,1),3,5)
        lines('Alternativas',data['alternatives'],(1,.36,.04,1),5,10)
        lines('Candidato', [data['route']],(.03,1,.25,1),6,16)
        for title,key,color in [('Cruces','markers',(1,1,1,1)),('Salida y meta','ends',(1,.82,.12,1))]:
            coll=collection(title,mode)
            mat=material(title,color)
            for item in data[key]:
                x,y,z=item['xyz']
                z=(flat_z if is_flat else z)+28
                font=bpy.data.curves.new(item['label'],'FONT')
                font.body=item['label']
                font.size=38 if key=='markers' else 24
                font.materials.append(mat)
                o=bpy.data.objects.new(item['label'],font)
                o.location=(x+8,y+5,z)
                coll.objects.link(o)
                mark=bpy.data.objects.new(item['label']+' punto',None)
                mark.empty_display_size=12
                mark.location=(x,y,z)
                coll.objects.link(mark)

    center=Vector(((w+e)/2,(s+n)/2,0))
    cameras=collection('Camaras',scene.collection)
    for name,offset in [('Mapa superior',(0,0,13000)),('Relieve oblicuo',(0,-9000,8500))]:
        cam=bpy.data.cameras.new(name)
        cam.type='ORTHO'
        cam.ortho_scale=11500
        cam.clip_end=50000
        o=bpy.data.objects.new(name,cam)
        cameras.objects.link(o)
        o.location=center+Vector(offset)
        o.rotation_euler=(center-o.location).to_track_quat('-Z','Y').to_euler()
        if name=='Mapa superior':
            scene.camera=o
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                space=area.spaces.active
                space.clip_end=50000
                space.region_3d.view_perspective='ORTHO'
                space.region_3d.view_rotation=Quaternion((1,0,0,0))
                space.region_3d.view_location=center
                space.region_3d.view_distance=10000
                space.shading.type='MATERIAL'
                space.overlay.show_floor=False
                space.overlay.show_axis_x=False
                space.overlay.show_axis_y=False
    text=bpy.data.texts.new('LEEME')
    text.write('Activa solo una coleccion principal en el Outliner. Para el relieve, activa 02 y elige la camara Relieve oblicuo.\n\n'+(OUT/'revision.md').read_text(encoding='utf8'))
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'raura_stage1_revision.blend'))


if __name__ == '__main__':
    if '--blender-build' in sys.argv:
        build()
    else:
        prepare()
        blender = shutil.which('blender') or r'C:\Program Files\Blender Foundation\Blender 5.2\blender.exe'
        subprocess.run([blender,'-b','--factory-startup','--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--blender-build'],check=True)
