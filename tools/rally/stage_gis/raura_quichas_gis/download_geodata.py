#!/usr/bin/env python3
"""Raura -> Cantera Quichas: OSM, Copernicus GLO-30 DEM and Sentinel-2 RGB.

Requires network access from the user's computer. Python 3.10+.
The downloader never substitutes synthetic elevation or invented roads.
"""
from __future__ import annotations
import argparse
import datetime as dt
import heapq
import json
import math
from pathlib import Path
import sys
import time
import xml.etree.ElementTree as ET
from urllib.parse import quote

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.transform import from_origin
from rasterio.warp import reproject, transform_bounds
import requests

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'data'
# Bounding box [W, S, E, N] in EPSG:4326. ~8.8 x 10 km around BOTH points.
BBOX = (-76.7900, -10.5400, -76.7100, -10.4500)
CRS = 'EPSG:32718'  # WGS 84 / UTM zone 18S; units metres
POINTS = {
    'Nevado Raura (inicio)': {'lat': -10.4777375, 'lon': -76.750671875, 'plus_code': '57X5G6CX+WP4'},
    'Cantera Quichas (meta)': {'lat': -10.5115125, 'lon': -76.748640625, 'plus_code': '57X5F7Q2+9GX'},
}
DEM_TILE='Copernicus_DSM_COG_10_S11_00_W077_00_DEM'
DEM_URL=f'https://copernicus-dem-30m.s3.eu-central-1.amazonaws.com/{DEM_TILE}/{DEM_TILE}.tif'
STAC_URL='https://earth-search.aws.element84.com/v1/search'
USER_AGENT='RallyManiac-GIS-Downloader/1.0 (research dataset download)'


def save_json(path: Path, obj):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding='utf-8')


def geom_feature(geometry, props):
    return {'type':'Feature','geometry':geometry,'properties':props}


def write_aoi():
    west, south, east, north = BBOX
    box_coords=[[[west,south],[east,south],[east,north],[west,north],[west,south]]]
    save_json(ROOT / 'aoi.geojson',geom_feature({'type':'Polygon','coordinates':box_coords}, {'name':'Raura–Cantera Quichas area; bounding box only','crs':'EPSG:4326'}))
    features=[]
    for name,p in POINTS.items():
        features.append(geom_feature({'type':'Point','coordinates':[p['lon'],p['lat']]},{'name':name,'plus_code':p['plus_code'],'note':'Centro del Plus Code (no implica carretera OSM cercana)'}))
    save_json(ROOT / 'endpoints.geojson',{'type':'FeatureCollection','features':features})


def output_grid(res_m):
    left,bottom,right,top=transform_bounds('EPSG:4326',CRS,*BBOX, densify_pts=21)
    width=int(math.ceil((right-left)/res_m))
    height=int(math.ceil((top-bottom)/res_m))
    return width,height,from_origin(left,top,res_m,res_m)


def warp_url_to_tiff(url, path, resolution_m, bands, dtype, src_nodata, dst_nodata, resampling=Resampling.bilinear):
    width,height,affine=output_grid(resolution_m)
    path.parent.mkdir(parents=True,exist_ok=True)
    # GDAL/rasterio only requests necessary ranges from each cloud-optimized GeoTIFF.
    env={'GDAL_DISABLE_READDIR_ON_OPEN':'YES', 'CPL_VSIL_CURL_ALLOWED_EXTENSIONS':'.tif',
         'GDAL_HTTP_MAX_RETRY':'3','GDAL_HTTP_RETRY_DELAY':'2', 'AWS_NO_SIGN_REQUEST':'YES'}
    with rasterio.Env(**env):
        with rasterio.open(url) as src:
            if src.count < max(bands):
                raise ValueError(f'El GeoTIFF tiene {src.count} bandas, se pidieron {bands}: {url}')
            kwargs={'driver':'GTiff','height':height,'width':width,'count':len(bands),
                    'dtype':dtype,'crs':CRS,'transform':affine,'compress':'deflate',
                    'predictor':3 if dtype=='float32' else 2,'tiled':True,
                    'BIGTIFF':'IF_SAFER'}
            if dst_nodata is not None: kwargs['nodata']=dst_nodata
            with rasterio.open(path,'w',**kwargs) as dst:
                for target_idx,source_idx in enumerate(bands, start=1):
                    tmp=np.full((height,width),dst_nodata if dst_nodata is not None else 0,dtype=dtype)
                    reproject(source=rasterio.band(src,source_idx),destination=tmp,
                              src_transform=src.transform,src_crs=src.crs,
                              src_nodata=src.nodata if src_nodata is None else src_nodata,
                              dst_transform=affine,dst_crs=CRS,dst_nodata=dst_nodata,
                              resampling=resampling)
                    dst.write(tmp,target_idx)
    print(f'OK {path} ({width} x {height}, {CRS})')


def download_dem():
    path=OUT/'terrain'/'raura_copernicus_glo30_utm18s.tif'
    print('DEM: Copernicus GLO-30 (modelo de superficie; no LiDAR).')
    warp_url_to_tiff(DEM_URL,path,30,[1],'float32',None,-9999.0)
    save_json(OUT/'terrain'/'dem_source.json',{'url':DEM_URL,'dataset':'Copernicus DEM GLO-30 Public, 2021','region':BBOX,'crs':CRS,'note':'DSM 30 m. La interpolación a 30m no añade detalles nuevos.'})


def osm_query():
    w,s,e,n=BBOX
    return f'[out:xml][timeout:180];(way["highway"]({s},{w},{n},{e}););(._;>;);out body;'


def download_osm():
    query=osm_query()
    endpoints=['https://overpass.kumi.systems/api/interpreter',
               'https://overpass-api.de/api/interpreter',
               'https://overpass.private.coffee/api/interpreter']
    errors=[]
    for url in endpoints:
        try:
            print(f'OSM: consultando {url}')
            r=requests.post(url,data={'data':query},timeout=210,headers={'User-Agent':USER_AGENT})
            r.raise_for_status()
            if '<osm' not in r.text[:400]:
                raise ValueError('Respuesta inesperada de Overpass (no es XML OSM)')
            xml_path=OUT/'roads'/'raura_quichas_highways.osm'
            xml_path.parent.mkdir(parents=True,exist_ok=True)
            xml_path.write_bytes(r.content)
            convert_osm_to_geojson(xml_path)
            print('OK OSM XML y GeoJSON de carreteras')
            return
        except Exception as exc:
            errors.append(f'{url}: {exc}')
            print('  Falló:',exc)
    raise RuntimeError('No se pudo descargar OSM. '+ '; '.join(errors))


def distance_m(a,b):
    lat1,lon1=a;lat2,lon2=b
    r=6371000.0
    p=math.pi/180
    x=(lon2-lon1)*p*math.cos((lat1+lat2)*p/2)
    y=(lat2-lat1)*p
    return r*math.hypot(x,y)


def convert_osm_to_geojson(osm_path):
    root=ET.parse(osm_path).getroot()
    nodes={int(n.attrib['id']):(float(n.attrib['lat']),float(n.attrib['lon'])) for n in root.findall('node')}
    roads=[];graph={};kept=0
    excluded={'footway','cycleway','steps','pedestrian','bridleway','path','proposed','construction','platform','corridor'}
    for way in root.findall('way'):
        tags={t.attrib['k']:t.attrib['v'] for t in way.findall('tag')}
        kind=tags.get('highway','')
        ids=[int(e.attrib['ref']) for e in way.findall('nd')]
        ids=[i for i in ids if i in nodes]
        if len(ids)<2:continue
        roads.append(geom_feature({'type':'LineString','coordinates':[[nodes[i][1],nodes[i][0]] for i in ids]},
                       {**tags,'osm_id':way.attrib['id']}))
        if kind not in excluded:
            kept+=1
            for x,y in zip(ids,ids[1:]):
                weight=distance_m(nodes[x],nodes[y])
                graph.setdefault(x,[]).append((y,weight))
                graph.setdefault(y,[]).append((x,weight))
    save_json(OUT/'roads'/'all_roads_wgs84.geojson',{'type':'FeatureCollection','features':roads})
    print(f'  Vías OSM {len(roads)}; trazados candidatos transitables {kept}')
    # Candidato más corto según OSM; NO garantiza continuidad real ni estado transitable.
    if not graph:
        print('  Sin vías OSM conectables en el área; habrá que trazar manualmente.')
        return
    starts=list(POINTS.values()); s=(starts[0]['lat'],starts[0]['lon']);t=(starts[1]['lat'],starts[1]['lon'])
    nearest=[]
    for p in (s,t):
        node=min(graph,key=lambda k: distance_m(p,nodes[k]))
        nearest.append((node,distance_m(p,nodes[node])))
    if max(nearest[0][1],nearest[1][1])>800:
        print('  No se propone ruta: uno de los extremos está a más de 800 m de los nodos OSM.')
        save_json(OUT/'roads'/'route_status.json',{'status':'no_nearby_osm','distances_m':[x[1] for x in nearest]})
        return
    source=nearest[0][0];target=nearest[1][0];queue=[(0.0,source)];best={source:0.0};prev={}
    while queue:
        d,x=heapq.heappop(queue)
        if d>best[x]:continue
        if x==target:break
        for y,w in graph[x]:
            nd=d+w
            if nd<best.get(y,float('inf')):
                best[y]=nd;prev[y]=x;heapq.heappush(queue,(nd,y))
    if target not in best:
        save_json(OUT/'roads'/'route_status.json',{'status':'disconnected','distances_m':[x[1] for x in nearest]})
        print('  No hay ruta conectada en OSM; se conserva la red completa para edición.')
        return
    path=[target]
    while path[-1]!=source:path.append(prev[path[-1]])
    path.reverse()
    route=geom_feature({'type':'LineString','coordinates':[[nodes[i][1],nodes[i][0]] for i in path]},
                       {'name':'CANDIDATO OSM, revisar y corregir en Blender','distance_m':round(best[target],1),
                        'start_snap_m':round(nearest[0][1],1),'end_snap_m':round(nearest[1][1],1),
                        'warning':'No es una ruta validada ni garantiza camino vehicular continuo.'})
    save_json(OUT/'roads'/'route_osm_candidate.geojson',{'type':'FeatureCollection','features':[route]})
    print('  Ruta candidata OSM:',round(best[target]/1000,2),'km; revisar en QGIS.')


def query_sentinel():
    payload={
      'collections':['sentinel-2-l2a'], 'bbox':list(BBOX),
      'datetime':'2025-04-01T00:00:00Z/2026-11-10T23:59:59Z',
      'query':{'eo:cloud_cover':{'lt':30}}, 'limit':100,
    }
    r=requests.post(STAC_URL,json=payload,timeout=90,headers={'User-Agent':USER_AGENT,'Accept':'application/geo+json'})
    r.raise_for_status()
    return r.json()


def find_best_scene():
    items=query_sentinel().get('features',[])
    # Require bounding box fully covered by one scene (approx by STAC bbox).
    suitable=[]
    for i in items:
        b=i.get('bbox')
        if not b or len(b)<4:continue
        if not (b[0]<=BBOX[0] and b[1]<=BBOX[1] and b[2]>=BBOX[2] and b[3]>=BBOX[3]):continue
        assets=i.get('assets',{})
        if 'visual' not in assets and not all(x in assets for x in ('red','green','blue')):continue
        suitable.append(i)
    if not suitable:
        raise RuntimeError('No hubo escenas Sentinel-2 que cubran toda el área con nube <30%. Amplía fechas o usa Copernicus Browser.')
    suitable.sort(key=lambda i:(float(i.get('properties',{}).get('eo:cloud_cover',100)),
                                -int(i.get('properties',{}).get('datetime','2000')[:4])))
    item=suitable[0]
    print(f"Escena Sentinel: {item.get('id')} (nubes del tile={item.get('properties',{}).get('eo:cloud_cover')}%)")
    return item


def download_satellite():
    item=find_best_scene()
    assets=item['assets']
    tiff=OUT/'satellite'/'raura_sentinel2_rgb_10m_utm18s.tif'
    tiff.parent.mkdir(parents=True,exist_ok=True)
    if 'visual' in assets:
        url=assets['visual']['href']
        if url.startswith('s3://'):
            raise RuntimeError('La escena visual solo tiene un URI S3; usa el navegador Copernicus o configura un driver S3 en GDAL.')
        warp_url_to_tiff(url,tiff,10,[1,2,3],'uint8',None,0,Resampling.bilinear)
    else:
        width,height,affine=output_grid(10)
        env={'GDAL_DISABLE_READDIR_ON_OPEN':'YES','GDAL_HTTP_MAX_RETRY':'3','AWS_NO_SIGN_REQUEST':'YES'}
        with rasterio.Env(**env):
            with rasterio.open(tiff,'w',driver='GTiff',height=height,width=width,count=3,
                                 dtype='uint8',crs=CRS,transform=affine,
                                 compress='deflate',tiled=True,photometric='RGB',nodata=0) as dst:
                for band_index,band_name in enumerate(('red','green','blue'),start=1):
                    with rasterio.open(assets[band_name]['href']) as src:
                        data=np.zeros((height,width),dtype='float32')
                        reproject(source=rasterio.band(src,1),destination=data,
                                  src_transform=src.transform,src_crs=src.crs,
                                  dst_transform=affine,dst_crs=CRS,src_nodata=src.nodata,
                                  dst_nodata=0,resampling=Resampling.bilinear)
                        # Crude reflectance stretch for display, not calibrated RGB.
                        dst.write((np.clip((data-200)/2800.0,0,1)*255).astype('uint8'),band_index)
    meta={'stac_item_id':item.get('id'),'datetime':item.get('properties',{}).get('datetime'),
          'tile_cloud_cover_percent':item.get('properties',{}).get('eo:cloud_cover'),
          'source':'Earth Search v1 / Sentinel-2 L2A',
          'resolution_m':10,'crs':CRS,'bbox':BBOX,
          'notice':'Tile cloud % is NOT local AOI cloud%; inspect imagery for shadows, cloud, seasonal snow.'}
    save_json(OUT/'satellite'/'scene_source.json',meta)
    save_json(OUT/'satellite'/'scene_stac_item.json',item)


def main():
    parser=argparse.ArgumentParser(description='Preparar datos de la ruta Raura – Cantera Quichas')
    parser.add_argument('--only',choices=['all','dem','osm','satellite'],default='all')
    args=parser.parse_args()
    write_aoi()
    print(f'AOI WGS84 {BBOX}, destino raster {CRS}; no incluye rutas inventadas.')
    todo=['dem','osm','satellite'] if args.only=='all' else [args.only]
    errors={}
    for kind in todo:
        try:
            {'dem':download_dem,'osm':download_osm,'satellite':download_satellite}[kind]()
        except Exception as exc:
            errors[kind]=str(exc)
            print('ERROR',kind,exc,file=sys.stderr)
    if errors:
        save_json(ROOT/'download_errors.json',errors)
        print('Algunos proveedores no respondieron: consultar download_errors.json.',file=sys.stderr)
        sys.exit(2)
    print('Listo. Abrir data/terrain/, data/roads/ y data/satellite/ en QGIS o BlenderGIS.')

if __name__=='__main__':main()
