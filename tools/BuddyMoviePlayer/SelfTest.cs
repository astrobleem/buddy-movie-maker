using System.Text;
namespace BuddyMoviePlayer;
static class SelfTest
{
 static readonly List<string> Results=[];
 static void Check(bool ok,string name) {if(!ok)throw new Exception("FAIL: "+name);Results.Add("PASS: "+name);}
 static void Reject(Action action,string name) {try{action();}catch(InvalidDataException){Results.Add("PASS: reject "+name);return;}catch(EndOfStreamException){Results.Add("PASS: reject "+name);return;}throw new Exception("Accepted "+name);}
 public static void Fixture(string folder,int width,int height,int duration=2000) {
  Directory.CreateDirectory(folder);int frames=(duration+249)/250;
  using(var w=new BinaryWriter(File.Create(Path.Combine(folder,"MOVIE.WZV")))) {w.Write(Encoding.ASCII.GetBytes("WZV2"));w.Write((ushort)width);w.Write((ushort)height);w.Write((ushort)4);w.Write((ushort)24);w.Write(frames);w.Write(duration);w.Write(width*height/2);for(int f=0;f<frames;f++)for(int i=0;i<width*height/2;i++)w.Write((byte)(((f%16)<<4)|(i%16)));}
  using(var w=new BinaryWriter(File.Create(Path.Combine(folder,"MOVIE.WZM")))) {w.Write(Encoding.ASCII.GetBytes("WZM1"));w.Write((ushort)20);w.Write((ushort)14);w.Write(5);w.Write(duration);w.Write(0);
   void State(int time,byte n,byte drum,byte retrigger) {w.Write(time);w.Write(new byte[]{n,0,0,drum});w.Write(new byte[]{(byte)(n==0?0:127),0,0,(byte)(drum==0?0:127)});w.Write(retrigger);w.Write((byte)0);}
   State(0,60,38,9);State(250,60,38,9);State(500,64,42,9);State(750,0,0,0);State(duration,0,0,0);
  }
  using(var w=new BinaryWriter(File.Create(Path.Combine(folder,"MOVIE.WZI")))) {w.Write(Encoding.ASCII.GetBytes("WZI1"));w.Write((ushort)20);w.Write((ushort)8);w.Write(2);w.Write(duration);w.Write((ushort)1);w.Write((ushort)0x102);w.Write(0);w.Write(new byte[]{96,0,0,0});w.Write(250);w.Write(new byte[]{16,0,0,0});}
  File.WriteAllText(Path.Combine(folder,"MOVIE.LRC"),"0|SYNTHETIC BUDDY TEST\n1000|SPEECH WINDOW\n1500|\n");
  using(var w=new BinaryWriter(File.Create(Path.Combine(folder,"SPEECH.PCM")))) {w.Write(Encoding.ASCII.GetBytes("SPC1"));w.Write((ushort)1);w.Write((ushort)0);w.Write(1000);w.Write(1250);w.Write((ushort)1500);w.Write((ushort)0);for(int i=0;i<1500;i++)w.Write((byte)(36+20*Math.Sin(2*Math.PI*300*i/6000)));}
 }
 public static void Run(string output,bool audioChecks=true) {
  Directory.CreateDirectory(output);
  try {
   Check(WaveAudio.ToMilliseconds(WaveAudio.TimeSamples,24000)==1000,"MMTIME sample count uses frames per second");
   Check(WaveAudio.ToMilliseconds(WaveAudio.TimeBytes,48000)==1000,"MMTIME byte count uses bytes per second");
   Check(WaveAudio.ToMilliseconds(WaveAudio.TimeMilliseconds,1000)==1000,"MMTIME milliseconds remain milliseconds");
   string hd=Path.Combine(output,"synthetic-256"),legacy=Path.Combine(output,"synthetic-64");Fixture(hd,256,160);Fixture(legacy,64,48);
   using(var m=new Movie(Path.Combine(hd,"MOVIE.WZV"))) {Check(m.Width==256&&m.Height==160&&m.Frame(0)[0]==0&&m.Frame(500)[0]==0x20,"WZV frame addressing and high nibble first");Check(m.Caption(0)=="SYNTHETIC BUDDY TEST"&&m.Caption(1600)=="","caption lookup and clear");var pcm=Synth.Render(m);Check(pcm.Length==48000&&pcm.Take(18000).Any(x=>x!=0),"four voice synthesis");Check(pcm.Skip(18000).Take(6000).All(x=>x==0),"note off silence");Check(pcm.Skip(24000).Take(6000).Any(x=>x!=0),"SPC1 speech playback");Check(pcm.Skip(30000).All(x=>x==0),"speech end silence");Check(pcm.SequenceEqual(Synth.Render(m)),"deterministic retrigger and replay timeline");File.WriteAllBytes(Path.Combine(output,"synthetic-audio.pcm"),pcm.SelectMany(BitConverter.GetBytes).ToArray());}
   using(var m=new Movie(Path.Combine(legacy,"MOVIE.WZV")))Check(m.Width==64&&m.Frame(1999).Length==1536,"legacy 64×48 WZV2");
   Check(Synth.Envelope(6,0,508,0,825,false).Attenuation==15,"bell self expiry");Check(Synth.Envelope(3,0,508,0,495,true).Period==509,"55ms vibrato divider motion");
   string bad=Path.Combine(output,"malformed");Fixture(bad,64,48);string vid=Path.Combine(bad,"MOVIE.WZV");byte[] original=File.ReadAllBytes(vid);File.WriteAllBytes(vid,original[..^1]);Reject(()=>new Movie(vid).Dispose(),"truncated video");File.WriteAllBytes(vid,original.Concat(new byte[]{0}).ToArray());Reject(()=>new Movie(vid).Dispose(),"trailing video data");File.WriteAllBytes(vid,original);
   string wzi=Path.Combine(bad,"MOVIE.WZI");byte[] instrument=File.ReadAllBytes(wzi);instrument[18]=3;File.WriteAllBytes(wzi,instrument);Reject(()=>new Movie(vid).Dispose(),"unknown instrument engine");Fixture(bad,64,48);File.WriteAllBytes(Path.Combine(bad,"MOVIE.WZX"),[1]);Reject(()=>new Movie(vid).Dispose(),"unknown WZ sidecar");File.Delete(Path.Combine(bad,"MOVIE.WZX"));
   byte[] music=File.ReadAllBytes(Path.Combine(bad,"MOVIE.WZM"));music[28]=0;File.WriteAllBytes(Path.Combine(bad,"MOVIE.WZM"),music);Reject(()=>new Movie(vid).Dispose(),"note velocity mismatch");Fixture(bad,64,48);File.WriteAllText(Path.Combine(bad,"MOVIE.LRC"),"100|A\n100|B");Reject(()=>new Movie(vid).Dispose(),"unordered captions");Fixture(bad,64,48);File.WriteAllText(Path.Combine(bad,"INST.REQ"),"WZI1");File.Delete(wzi);Reject(()=>new Movie(vid).Dispose(),"missing required instrument");
   if(audioChecks) {
   using var player=new Player();player.Show();Application.DoEvents();Open(player,Path.Combine(hd,"MOVIE.WZV"));
   using(var image=new Bitmap(player.Width,player.Height)) {player.DrawToBitmap(image,new Rectangle(0,0,image.Width,image.Height));image.Save(Path.Combine(output,"player-ui.png"));}
   player.Toggle();Pump(player,180);Check(player.Playing&&player.Position>0,"actual waveOut clock advances UI");player.Toggle();int paused=player.Position;Pump(player,100);Check(!player.Playing&&player.Position==paused,"pause releases audio and freezes clock");player.SeekTo(1100);Check(player.Position==1100,"paused seek into speech");player.Toggle();Pump(player,100);Check(player.Position>=1100,"seek speech resumes through waveOut");player.SeekTo(100);Pump(player,80);Check(player.Position>=100&&player.Position<500,"backward seek rebuilds waveOut buffer");player.SeekTo(1950);Pump(player,150);Check(!player.Playing&&player.Position==2000,"end stops and releases audio");player.Toggle();Pump(player,100);Check(player.Playing&&player.Position<500,"replay from end");player.Fullscreen();player.Fullscreen();Open(player,Path.Combine(legacy,"MOVIE.WZV"));Check(!player.Playing&&player.Position==0,"multiple opens clean up old audio and video");player.Close();
   using(var f=new FileStream(Path.Combine(hd,"MOVIE.WZV"),FileMode.Open,FileAccess.ReadWrite,FileShare.None))Check(f.Length>0,"video handle released on replacement");
   }
   MoreTests(output);
   Results.Add("PASS: all tests completed");
  }catch(Exception ex) {Results.Add(ex.ToString());Environment.ExitCode=1;}
  File.WriteAllLines(Path.Combine(output,"test-results.txt"),Results);
 }
 static void Open(Player player,string path) {var task=player.OpenAsync(path,false);while(!task.IsCompleted){Application.DoEvents();Thread.Sleep(5);}task.GetAwaiter().GetResult();}
 public static void VerifyFile(string path,string report) {
  try {
   byte[] before=System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path));
   using(var player=new Player()) {player.Show();Application.DoEvents();Open(player,path);player.Toggle();Pump(player,180);Check(player.Playing&&player.Position>0,"private local movie plays through waveOut");player.SeekTo(500);Pump(player,100);Check(player.Position>=500,"private local movie seek");player.Toggle();player.Close();}
   Check(before.SequenceEqual(System.Security.Cryptography.SHA256.HashData(File.ReadAllBytes(path))),"private source movie unchanged");
   using var stream=new FileStream(path,FileMode.Open,FileAccess.Read,FileShare.None);Check(stream.Length>0,"private movie handle released");
  }catch(Exception ex){Results.Add(ex.ToString());Environment.ExitCode=1;}
  File.WriteAllLines(report,Results);
 }
 static void MoreTests(string output) {
  string folder=Path.Combine(output,"extended");Fixture(folder,64,48);string v=Path.Combine(folder,"MOVIE.WZV"),music=Path.Combine(folder,"MOVIE.WZM"),instrument=Path.Combine(folder,"MOVIE.WZI");
  byte[] original=File.ReadAllBytes(music);byte[] b=(byte[])original.Clone();b[12]=1;File.WriteAllBytes(music,b);Reject(()=>new Movie(v).Dispose(),"music duration mismatch");File.WriteAllBytes(music,original[..^1]);Reject(()=>new Movie(v).Dispose(),"truncated music");File.WriteAllBytes(music,original);
  byte[] wi=File.ReadAllBytes(instrument);b=(byte[])wi.Clone();b[16]=2;File.WriteAllBytes(instrument,b);Reject(()=>new Movie(v).Dispose(),"unknown WZI flags");b=(byte[])wi.Clone();b[24]=1;File.WriteAllBytes(instrument,b);Reject(()=>new Movie(v).Dispose(),"unknown program");File.WriteAllBytes(instrument,wi[..^1]);Reject(()=>new Movie(v).Dispose(),"truncated instrument");File.WriteAllBytes(instrument,wi);
  string speech=Path.Combine(folder,"SPEECH.PCM");byte[] sp=File.ReadAllBytes(speech);b=(byte[])sp.Clone();b[20]=0;File.WriteAllBytes(speech,b);Reject(()=>new Movie(v).Dispose(),"invalid speech sample");File.WriteAllBytes(speech,sp[..^1]);Reject(()=>new Movie(v).Dispose(),"truncated speech");File.WriteAllBytes(speech,sp);
  using(var movie=new Movie(v)) {var before=Synth.Render(movie);b=(byte[])wi.Clone();BitConverter.GetBytes(125).CopyTo(b,28);File.WriteAllBytes(instrument,b);using var changed=new Movie(v);var after=Synth.Render(changed);Check(before.Skip(3000).Take(3000).SequenceEqual(after.Skip(3000).Take(3000)),"program changes preserve held attack snapshots");}
  File.WriteAllBytes(instrument,wi);File.Delete(instrument);File.Delete(speech);using(var baseline=new Movie(v))Check(Synth.Render(baseline).Any(x=>x!=0),"legacy WZM baseline without instrument sidecar");
  Fixture(folder,64,48);b=File.ReadAllBytes(music);for(int p=20;p<b.Length;p+=14){b[p+7]=b[p+11]=0;b[p+12]&=7;}File.WriteAllBytes(music,b);wi=File.ReadAllBytes(instrument);wi[32]=96;File.WriteAllBytes(instrument,wi);short[] retrigger;using(var movie=new Movie(v))retrigger=Synth.Render(movie);b[46]=0;File.WriteAllBytes(music,b);using(var held=new Movie(v)){var pcm=Synth.Render(held);Check(retrigger.Skip(6000).Take(1200).Max(x=>Math.Abs((int)x))>pcm.Skip(6000).Take(1200).Max(x=>Math.Abs((int)x)),"equal melodic note retrigger restarts bell envelope");}
  Fixture(folder,64,48);File.WriteAllBytes(Path.Combine(folder,"MOVIE.LRC"),[48,124,255,10]);Reject(()=>new Movie(v).Dispose(),"non ASCII captions");
  string max=Path.Combine(output,"maximum-duration");Fixture(max,4,1,600000);using(var movie=new Movie(Path.Combine(max,"MOVIE.WZV")))Check(Synth.Render(movie).Length==14400000,"maximum 600 second timeline bound");
 }
 static void Pump(Player player,int ms) {var clock=System.Diagnostics.Stopwatch.StartNew();while(clock.ElapsedMilliseconds<ms){Application.DoEvents();Thread.Sleep(5);player.TickPlayback();}}
}
