from pathlib import Path
import random,struct
Q=Path(__file__).resolve().parent

def spans(frame,previous):
 out=[];i=0
 while i<len(frame):
  if previous is not None and frame[i]==previous[i]:i+=1;continue
  start=last=i;i+=1
  while i<len(frame):
   if previous is None or frame[i]!=previous[i]:last=i
   elif i-last>4:break
   i+=1
  end=last+1;out.append(struct.pack('<HH',start*2+1,end-start)+bytes(frame[start:end]))
 packet=b''.join(out)
 if len(packet)>32000:raise ValueError('Packet exceeds runtime bound')
 return packet

def full_frame_if_larger(folder):
 """Use independent sector-aligned frames when deltas cost at least raw data.

 WZF1: common 24-byte metadata, header size 4096, frame stride 8192;
 each frame contains 8000 CGA attributes followed by ignored padding.
 WZD1 remains byte-for-byte unchanged for smaller sparse streams.
 """
 raw=folder/'MOVIE.WZV';sidecar=folder/'MOVIE.WZD'
 with raw.open('rb') as f:
  magic,w,h,fps,hs,n,ms,size=struct.unpack('<4s4H3I',f.read(24))
  if (w,h)!=(160,100) or sidecar.stat().st_size<24+n*8000:return False
  temporary=folder/'MOVIE.TMP'
  with temporary.open('wb') as d:
   header=struct.pack('<4s4H3I',b'WZF1',160,100,fps,4096,n,ms,8192)
   d.write(header.ljust(4096,b'\0'))
   for k in range(n):
    frame=f.read(8000)
    if len(frame)!=8000:raise ValueError('Truncated full-frame input')
    d.write(frame);d.write(bytes(192))
  temporary.replace(sidecar)
 return True

def make(folder,w,h,fps,sparse=True,seconds=4):
 folder.mkdir();n=fps*seconds;ms=seconds*1000;rng=random.Random(20261119)
 bg=bytes(rng.randrange(256) for _ in range(w*h//2));previous=None
 with (folder/'MOVIE.WZV').open('wb') as v:
  v.write(struct.pack('<4s4H3I',b'WZV2',w,h,fps,24,n,ms,w*h//2))
  d=(folder/'MOVIE.WZD').open('wb') if (w,h)==(160,100) else None
  if d:d.write(struct.pack('<4s4H3I',b'WZD1',w,h,fps,24,n,ms,32000))
  for k in range(n):
   frame=bytearray(bg) if sparse else bytearray(rng.randrange(256) for _ in bg)
   if sparse:
    left=(k*2)%(w-24)
    for y in range(38,min(50,h)):
     for x in range(left//2,(left+24)//2):frame[y*(w//2)+x]=255
   v.write(frame)
   if d:
    p=spans(frame,previous);d.write(struct.pack('<I',len(p)));d.write(p)
   previous=frame
  if d:d.close()
 (folder/'MOVIE.CUE').write_bytes(struct.pack('<4sIII',b'WZC1',ms,0,ms))
 events=[]
 for t in range(0,ms,125):
  note=60+(t//500)%12 if t%500<375 else 0
  events.append(struct.pack('<I10B',t,note,0,0,0,90 if note else 0,0,0,0,1 if note else 0,0))
 (folder/'MOVIE.WZM').write_bytes(struct.pack('<4sHHIII',b'WZM1',20,14,len(events),ms,0)+b''.join(events))
 print(folder.name,n,'frames; raw', (folder/'MOVIE.WZV').stat().st_size,'encoded',(folder/'MOVIE.WZD').stat().st_size if d else 0)
if __name__=='__main__':
 make(Q/'S16',160,100,16);make(Q/'N8',160,100,8,False);make(Q/'N16',160,100,16,False);make(Q/'AUDIO',256,160,8)
