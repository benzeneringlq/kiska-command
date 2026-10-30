#!/usr/bin/env python3
"""Fetch USGS 3DEP in UTM 60N and bake offline, metre-scale Kiska terrain.
Requires numpy, Pillow and tifffile. No network access is used by the game.
"""
import argparse, hashlib, json, math, pathlib, urllib.parse, urllib.request
import numpy as np
import tifffile
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'game/data/terrain'
SERVICE = 'https://elevation.nationalmap.gov/arcgis/rest/services/3DEPElevation/ImageServer'
SPAN = 49152
N = 1025

def utm(lon, lat):
    # WGS84 transverse Mercator, central meridian 177E (zone 60 north).
    a, e2, k = 6378137., 0.0066943799901413165, .9996
    p = math.radians(lat); l = math.radians(lon - 177)
    ep = e2 / (1-e2); t = math.tan(p)**2; c = ep*math.cos(p)**2
    v = a/math.sqrt(1-e2*math.sin(p)**2); q = math.cos(p)*l
    m = a*((1-e2/4-3*e2**2/64-5*e2**3/256)*p-(3*e2/8+3*e2**2/32+45*e2**3/1024)*math.sin(2*p)+(15*e2**2/256+45*e2**3/1024)*math.sin(4*p)-35*e2**3/3072*math.sin(6*p))
    x=500000+k*v*(q+(1-t+c)*q**3/6+(5-18*t+t*t+72*c-58*ep)*q**5/120)
    y=k*(m+v*math.tan(p)*(q*q/2+(5-t+9*c+4*c*c)*q**4/24+(61-58*t+t*t+600*c-330*ep)*q**6/720))
    return x,y

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--cached-tiff',type=pathlib.Path)
    args=parser.parse_args(); OUT.mkdir(parents=True,exist_ok=True)
    cx,cy=utm(177.45,51.98)
    # Export pixels are cell centres. Half-cell padding makes first/last samples
    # correspond exactly to game coordinates -SPAN/2 and +SPAN/2.
    edge=SPAN/2+SPAN/(N-1)/2
    params=dict(bbox=f'{cx-edge},{cy-edge},{cx+edge},{cy+edge}',bboxSR=32660,imageSR=32660,size=f'{N},{N}',format='tiff',pixelType='F32',interpolation='RSP_BilinearInterpolation',renderingRule='{"rasterFunction":"None"}',f='json')
    url=SERVICE+'/exportImage?'+urllib.parse.urlencode(params)
    if args.cached_tiff:
        raw=args.cached_tiff.read_bytes()
    else:
        with urllib.request.urlopen(url,timeout=90) as response: meta=json.load(response)
        if 'href' not in meta: raise RuntimeError(meta)
        with urllib.request.urlopen(meta['href'],timeout=120) as response: raw=response.read()
        pathlib.Path('/tmp/kiska-utm.tif').write_bytes(raw)
    import io
    h=tifffile.imread(io.BytesIO(raw)).astype('<f4')
    if h.shape!=(N,N): raise ValueError(f'Wrong dimensions: {h.shape}')
    if not np.isfinite(h).all() or h.max()<1000: raise ValueError('Missing or corrupt island elevations')
    # 3DEP encodes surrounding ocean as zero. This is a synthetic shallow sea
    # floor, NOT bathymetry. Retain all positive land heights without exaggeration.
    h[h<=0]=-8
    (OUT/'kiska.f32').write_bytes(h.tobytes())
    land=h>0; f=np.clip(h/1250,0,1)
    colors=np.zeros((N,N,3),dtype=np.float64); colors[:]=[29,65,80]
    base=np.stack([83+f*92,103+f*65,66+f*92],axis=-1)
    dz,dx=np.gradient(h,48); shade=np.clip(.85+(-dx-dz)*.8,.45,1.2)
    colors[land]=(base*shade[:,:,None])[land]
    Image.fromarray(np.uint8(np.clip(colors,0,255))).save(OUT/'kiska_map.png')
    metadata=dict(source='USGS National Map 3DEP',service=SERVICE,request=url,crs='EPSG:32660',centre_utm=[cx,cy],span_m=SPAN,samples=N,sample_spacing_m=48,orientation='row 0 north; +x east; +z south',vertical_scale=1,download_date='2026-10-30',source_tiff_sha256=hashlib.sha256(raw).hexdigest(),height_sha256=hashlib.sha256(h.tobytes()).hexdigest(),min_m=float(h.min()),max_m=float(h.max()),note='48 m output sampling is not a claim of source survey resolution. Ocean = synthetic -8 m. Camps, roads and grading are fictional gameplay additions.')
    (OUT/'kiska.json').write_text(json.dumps(metadata,indent=2)+'\n')
    print(json.dumps(metadata,indent=2))
    # Print geographic landmarks in local metres for scene placement.
    for name,lon,lat in [('volcano',177.6035,52.1031),('harbor',177.558,51.970),('south',177.30,51.88)]:
        x,y=utm(lon,lat); print(name,round(x-cx),round(cy-y))
if __name__=='__main__': main()
