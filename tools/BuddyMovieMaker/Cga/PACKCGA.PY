"""Create a new, video-only CGA export; never changes the source movie.
Python 3 on a development host. GPL-3.0, matching the DOS runtime.
"""
from pathlib import Path
import argparse,struct
from encode import spans,full_frame_if_larger
p=argparse.ArgumentParser();p.add_argument('movie',type=Path);p.add_argument('out',type=Path);a=p.parse_args()
with a.movie.open('rb') as f:
 h=f.read(24)
 if len(h)!=24:raise SystemExit('Short video header')
 magic,w,height,fps,hs,n,ms,size=struct.unpack('<4s4H3I',h)
 if magic!=b'WZV2' or hs!=24 or (w,height) not in [(160,100),(256,160)] or fps not in (2,4,8,16) or size!=w*height//2 or not 0<ms<=600000 or not 0<n<=9600 or not (n-1)*1000//fps<ms<=n*1000//fps or a.movie.stat().st_size!=24+n*size:
  raise SystemExit('Unsupported or invalid WZV2 input')
 if a.out.exists():raise SystemExit('Output directory must be new')
 a.out.mkdir();previous=None
 with (a.out/'MOVIE.WZV').open('wb') as v,(a.out/'MOVIE.WZD').open('wb') as d:
  v.write(struct.pack('<4s4H3I',b'WZV2',160,100,fps,24,n,ms,8000));d.write(struct.pack('<4s4H3I',b'WZD1',160,100,fps,24,n,ms,32000))
  for k in range(n):
   src=f.read(size)
   if len(src)!=size:raise SystemExit('Input became truncated')
   if (w,height)==(160,100):frame=src
   else:
    frame=bytearray(8000)
    for y in range(100):
     sy=y*height//100
     for x in range(0,160,2):
      sx=x*w//160;b=src[sy*(w//2)+sx//2];hi=b&15 if sx&1 else b>>4
      sx=(x+1)*w//160;b=src[sy*(w//2)+sx//2];lo=b&15 if sx&1 else b>>4
      frame[y*80+x//2]=(hi<<4)|lo
   v.write(frame);packet=spans(frame,previous);d.write(struct.pack('<I',len(packet)));d.write(packet);previous=frame
 (a.out/'MOVIE.CUE').write_bytes(struct.pack('<4sIII',b'WZC1',ms,0,ms))
full_frame_if_larger(a.out)
print('Created video-only CGA export:',a.out,'frames:',n,'fps:',fps)
