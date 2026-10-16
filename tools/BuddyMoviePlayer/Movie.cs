using System.Text;
namespace BuddyMoviePlayer;
public record Score(int Time, byte[] Notes, byte[] Velocities, byte Retrigger);
public record Instrument(int Time, byte[] Programs);
public record Speech(int Start, int End, byte[] Samples);
public sealed class Movie : IDisposable
{
 public readonly FileStream Video;
 public int Width, Height, Fps, Frames, Duration, FrameBytes;
 public readonly List<Score> Scores=[];
 public readonly List<Instrument> Instruments=[];
 public readonly List<Speech> Speeches=[];
 public readonly List<(int Time,string Text)> Captions=[];
 public bool Vibrato;
 static void Require(bool ok,string message) { if(!ok)throw new InvalidDataException(message); }
 static int U16(byte[] b,int p)=>BitConverter.ToUInt16(b,p);
 static int I32(byte[] b,int p)=>BitConverter.ToInt32(b,p);
 static bool Magic(byte[] b,string s)=>b.Length>=4&&Encoding.ASCII.GetString(b,0,4)==s;
 static byte[] Read(string p,int max) { Require(new FileInfo(p).Length<=max,$"{Path.GetFileName(p)} exceeds format limits.");return File.ReadAllBytes(p); }
 public Movie(string path)
 {
  Video=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.Read);
  try {
   byte[] h=new byte[24];Video.ReadExactly(h);
   Width=U16(h,4);Height=U16(h,6);Fps=U16(h,8);Frames=I32(h,12);Duration=I32(h,16);FrameBytes=Width*Height/2;
   Require(Magic(h,"WZV2")&&U16(h,10)==24&&Width>=4&&Width<=320&&Width%4==0&&Height>=1&&Height<=200&&Fps is 2 or 4 or 8&&I32(h,20)==FrameBytes,"Unsupported WZV header. Expected packed WZV2 (including legacy 64×48).");
   Require(Frames>0&&Frames<=4800&&Duration>0&&Duration<=600000&&Duration<=Frames*(1000/Fps)&&Duration>(Frames-1)*(1000/Fps),"Invalid frame count or duration.");
   Require(Video.Length==24L+(long)Frames*FrameBytes,"Truncated video or unexpected trailing bytes.");
   string stem=Path.Combine(Path.GetDirectoryName(path)!,Path.GetFileNameWithoutExtension(path));
   string Side(string ext)=>stem+ext;
   foreach(string file in Directory.GetFiles(Path.GetDirectoryName(path)!)) {
    string ext=Path.GetExtension(file).ToUpperInvariant();
    if(Path.GetFileNameWithoutExtension(file).Equals(Path.GetFileNameWithoutExtension(path),StringComparison.OrdinalIgnoreCase)&&ext.StartsWith(".WZ")&&ext is not (".WZV" or ".WZM" or ".WZI"))throw new InvalidDataException("Unsupported sidecar: "+Path.GetFileName(file));
   }
   if(File.Exists(Side(".WZM"))) {
    byte[] b=Read(Side(".WZM"),140020);Require(b.Length>=20&&Magic(b,"WZM1")&&U16(b,4)==20&&U16(b,6)==14&&I32(b,12)==Duration&&I32(b,16)==0,"Invalid or mismatched WZM1 header.");
    int n=I32(b,8);Require(n>0&&n<=10000&&b.Length==20+n*14,"Invalid WZM length.");int prev=-1;
    for(int p=20;p<b.Length;p+=14) { int t=I32(b,p);Require(t>prev&&t<=Duration&&(b[p+12]&240)==0&&b[p+13]==0,"Invalid WZM time or flags.");prev=t;
     var notes=b[(p+4)..(p+8)];var vel=b[(p+8)..(p+12)];
     for(int i=0;i<4;i++)Require(vel[i]<=127&&((notes[i]==0&&vel[i]==0)||(vel[i]>0&&notes[i]>=(i==3?35:45)&&notes[i]<=(i==3?81:96))),"Invalid WZM note/velocity.");Scores.Add(new(t,notes,vel,b[p+12]));
    }
   }
   string req=Path.Combine(Path.GetDirectoryName(path)!,"INST.REQ");
   if(File.Exists(req))Require(Read(req,4).SequenceEqual(Encoding.ASCII.GetBytes("WZI1"))&&File.Exists(Side(".WZI")),"INST.REQ requires a valid WZI1 sidecar.");
   if(File.Exists(Side(".WZI"))) {
    Require(Scores.Count>0,"WZI requires WZM music.");byte[] b=Read(Side(".WZI"),80020);
    Require(b.Length>=20&&Magic(b,"WZI1")&&U16(b,4)==20&&U16(b,6)==8&&I32(b,12)==Duration&&(U16(b,16)&65534)==0&&U16(b,18)==0x102,"Unsupported WZI version, flags or duration.");
    int n=I32(b,8);Require(n>0&&n<=10000&&b.Length==20+n*8,"Invalid WZI length.");Vibrato=(U16(b,16)&1)!=0;int prev=-1;
    for(int p=20;p<b.Length;p+=8) {int t=I32(b,p);Require(t>prev&&t<=Duration&&(p!=20||t==0)&&b[p+7]==0,"Invalid WZI event.");prev=t;byte[] programs=b[(p+4)..(p+7)];Require(programs.All(x=>x<=112&&x%16==0),"Unsupported WZI program.");Instruments.Add(new(t,programs));}
   }
   if(File.Exists(Side(".CUE"))) {byte[] b=Read(Side(".CUE"),16);Require(b.Length==16&&Magic(b,"WZC1")&&I32(b,4)==Duration&&I32(b,8)>=0&&I32(b,8)<I32(b,12)&&I32(b,12)<=Duration,"Invalid CUE sidecar.");}
   if(File.Exists(Side(".LRC"))) {
    byte[] captionBytes=Read(Side(".LRC"),20000);Require(captionBytes.All(x=>x<=127),"Captions must be ASCII.");string[] lines=Encoding.ASCII.GetString(captionBytes).Split('\n');int prev=-1;
    foreach(string raw in lines) {string line=raw.TrimEnd('\r');if(line.Length==0||line.StartsWith('#'))continue;int p=line.IndexOf('|');Require(p>0&&int.TryParse(line[..p],out _),"Invalid caption time.");int t=int.Parse(line[..p]);string text=line[(p+1)..];Require(t>prev&&t<=Duration&&text.Length<=52&&text.All(c=>c>=32&&c<=126)&&Captions.Count<256,"Invalid caption cue.");prev=t;Captions.Add((t,new string(text.ToUpperInvariant().Select(c=>c>90?'?':c).ToArray())));}
   }
   string sp=Path.Combine(Path.GetDirectoryName(path)!,"SPEECH.PCM");
   if(File.Exists(sp)) {
    byte[] b=Read(sp,360200);Require(b.Length>=8&&Magic(b,"SPC1")&&U16(b,6)==0&&U16(b,4)>0&&U16(b,4)<=16,"Unsupported speech header.");int p=8,prev=-150,total=0;
    for(int i=0;i<U16(b,4);i++) {Require(p+12<=b.Length,"Truncated speech.");int start=I32(b,p),end=I32(b,p+4),len=U16(b,p+8);Require(U16(b,p+10)==0&&start>=prev+150&&start<end&&end<=Duration&&len>0&&len<=48000&&(long)(end-start)*6==len&&p+12+len<=b.Length,"Invalid speech window.");p+=12;byte[] samples=b[p..(p+len)];Require(samples.All(x=>x>=1&&x<=72),"Invalid speech PWM sample.");p+=len;total+=len;Speeches.Add(new(start,end,samples));prev=end;}
    Require(p==b.Length&&total<=360000,"Speech trailing data or oversized stream.");
    foreach(var s in Speeches) {var state=Scores.LastOrDefault(x=>x.Time<=s.Start);Require(state==null||state.Notes.All(x=>x==0),"Speech overlaps active music; unsupported combination.");Require(!Scores.Any(x=>x.Time>s.Start&&x.Time<s.End+80&&x.Notes.Any(n=>n!=0)),"Speech overlaps imminent music; unsupported combination.");}
   }
  } catch {Video.Dispose();throw;}
 }
 public byte[] Frame(int ms) {var data=new byte[FrameBytes];Video.Position=24L+Math.Min(Frames-1,ms*Fps/1000)*(long)FrameBytes;Video.ReadExactly(data);return data;}
 public string Caption(int ms)=>Captions.LastOrDefault(x=>x.Time<=ms).Text??"";
 public void Dispose()=>Video.Dispose();
}
