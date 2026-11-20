"""Create an original compact, fully changing CGA100 run/fill demo. GPL-3.0."""
from pathlib import Path
import argparse,shutil,struct,tempfile
from encode import runs_if_smaller

def demo_frames(n):
 for k in range(n):
  frame=bytearray()
  for y in range(100):
   for block in range(5):
    color=(block+y//10+k)&15
    frame.extend(bytes([(color<<4)|((color+5)&15)])*16)
  mark=48*80+(k*3)%70
  frame[mark:mark+7]=bytes([0xf0,0x1f,0xfe,0x2f,0xfa,0x3f,0xf4])
  yield bytes(frame)

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('out',type=Path)
 p.add_argument('--player',type=Path,help='rebuilt MOVPLAY.EXE to copy')
 p.add_argument('--fps',type=int,choices=(4,8,16),default=8)
 p.add_argument('--seconds',type=int,choices=range(1,11),default=4);a=p.parse_args()
 if a.out.exists():raise SystemExit('Output directory must be new')
 if a.player and not a.player.is_file():raise SystemExit('Player does not exist')
 n=a.fps*a.seconds;ms=a.seconds*1000
 with tempfile.TemporaryDirectory(prefix='buddy-cga-') as temp:
  folder=Path(temp)
  with (folder/'MOVIE.WZV').open('wb') as f:
   f.write(struct.pack('<4s4H3I',b'WZV2',160,100,a.fps,24,n,ms,8000))
   for frame in demo_frames(n):f.write(frame)
  # The independent run export is smaller than this raw full-frame bound.
  with (folder/'MOVIE.WZD').open('wb') as f:
   f.write(struct.pack('<4s4H3I',b'WZF1',160,100,a.fps,4096,n,ms,8192))
   f.truncate(4096+n*8192)
  if not runs_if_smaller(folder):raise SystemExit('Unexpected run export bound')
  a.out.mkdir();shutil.copyfile(folder/'MOVIE.WZD',a.out/'MOVIE.WZD')
 if a.player:shutil.copyfile(a.player,a.out/'MOVPLAY.EXE')
 (a.out/'PLAY.BAT').write_bytes(b'@echo off\r\nMOVPLAY /R\r\n')
 license=Path(__file__).resolve().parents[3]/'LICENSE'
 if license.is_file():shutil.copyfile(license,a.out/'LICENSE')
 print('Created original 160x100 demo:',n,'frames;',a.fps,'fps; sidecar', (a.out/'MOVIE.WZD').stat().st_size,'bytes')
if __name__=='__main__':main()
