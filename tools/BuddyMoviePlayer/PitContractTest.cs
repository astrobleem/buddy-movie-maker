using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
namespace BuddyMoviePlayer;
static class PitContractTest
{
 static readonly List<string> Results=[];
 static void Check(bool ok,string name){if(!ok)throw new Exception("FAIL: "+name);Results.Add("PASS: "+name);}
 static bool Accept(string path,bool audio,bool enabled=true,bool capable=true){try{using var m=new Movie(path,enabled,capable,audio);return true;}catch(InvalidDataException){return false;}catch(EndOfStreamException){return false;}catch(FileNotFoundException){return false;}}
 static string Hash(string path)=>Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));
 public static void Run(string corpus,string output,bool audioChecks=true)
 {
  Directory.CreateDirectory(output);
  try {
   Check(Hash(Path.Combine(corpus,"MANIFEST.json"))=="6BCE0C757CF890154AF27B55B866CE42A0B97791F6DE1F74FFED8D26601A4861","frozen manifest hash");
   using var manifest=JsonDocument.Parse(File.ReadAllText(Path.Combine(corpus,"MANIFEST.json")));
   Check(Hash(Path.Combine(corpus,"..","MML3.md"))==manifest.RootElement.GetProperty("spec_sha256").GetString(),"frozen specification hash");
   int files=0;foreach(var f in manifest.RootElement.GetProperty("files").EnumerateArray()){string path=Path.Combine(corpus,f.GetProperty("path").GetString()!);Check(new FileInfo(path).Length==f.GetProperty("size").GetInt64()&&Hash(path)==f.GetProperty("sha256").GetString(),"fixture integrity "+f.GetProperty("path").GetString());files++;}Check(files==362,"362 manifest entries verified");
   int decisions=0;
   foreach(var c in manifest.RootElement.GetProperty("cases").EnumerateArray()){
    string name=c.GetProperty("name").GetString()!,folder=Path.Combine(corpus,name);bool video=c.GetProperty("movie_accept").GetBoolean(),audio=c.GetProperty("audio_accept").GetBoolean();
    Check(Accept(Path.Combine(folder,"MOVIE.WZV"),false)==video,name+" movie acceptance");
    Check(Accept(Path.Combine(folder,"MOVIE.WZM"),true)==audio,name+" audio acceptance");decisions+=2;
    if(c.TryGetProperty("pit_required",out var required)&&required.GetBoolean()&&(video||audio)){
     string path=Path.Combine(folder,video?"MOVIE.WZV":"MOVIE.WZM");
     Check(!Accept(path,!video,false)&&!Accept(path,!video,true,false),name+" required PIT disabled/unavailable rejected");
     using var movie=new Movie(path,true,true,!video);short[] actual=Synth.Render(movie,false,true,false);Check(actual.SequenceEqual(ReferencePit(movie)),name+" PIT phase/hold/attack/off reference");
    }
   }
   Check(decisions==112,"112 movie/audio decisions match frozen corpus");
   using var pitches=JsonDocument.Parse(File.ReadAllText(Path.Combine(corpus,"PITCH.json")));int count=0;
   foreach(var p in pitches.RootElement.EnumerateArray()){int note=p.GetProperty("note").GetInt32();Check(PitOscillator.Hertz[note-45]==p.GetProperty("hz").GetInt32()&&PitOscillator.Divisor(note)==p.GetProperty("divisor").GetInt32(),"canonical PIT pitch "+note);count++;}Check(count==52,"all 52 divisors");
   using(var mixed=new Movie(Path.Combine(corpus,"MIXED","MOVIE.WZV"),true)){
    var psg=Synth.Render(mixed,true,false,false);var pit=Synth.Render(mixed,false,true,false);var five=Synth.Render(mixed,true,true,false);
    Check(psg.Any(x=>x!=0)&&pit.Any(x=>x!=0),"independent PSG and PIT output");Check(five.Zip(psg.Zip(pit)).All(x=>Math.Abs(x.First-(x.Second.First+x.Second.Second))<=1),"five voices mix without dropped stream or clipping");
    Wav(Path.Combine(output,"five-voice-mixed.wav"),five);Wav(Path.Combine(output,"pit-only.wav"),pit);Wav(Path.Combine(output,"psg-only.wav"),psg);
   }
   using(var guard=new Movie(Path.Combine(corpus,"GUARDOK","MOVIE.WZV"),true)){
    var pit=Synth.Render(guard,false,true,false);var full=Synth.Render(guard);foreach(var s in guard.Speeches){int lower=Math.Max(0,s.Start-150),upper=Math.Min(guard.Duration,s.End+150);Check(pit.Skip(lower*24).Take((upper-lower)*24).All(x=>x==0),"half-open speech PIT guard silence");Check(full.Skip(s.Start*24).Take((s.End-s.Start)*24).Any(x=>x!=0),"speech PWM remains audible");}Wav(Path.Combine(output,"speech-guard.wav"),full);
   }
   string fiveFolder=Path.Combine(output,"five-generators");PaceTest.CreateFixture(fiveFolder,true);
   using(var five=new Movie(Path.Combine(fiveFolder,"MOVIE.WZV"),true)){
    Score[] original=five.Scores.ToArray();short[] all=Synth.Render(five);int[] sum=new int[48000];
    for(int channel=0;channel<4;channel++){five.Scores.Clear();foreach(var s in original){byte[] n=new byte[4],v=new byte[4];n[channel]=s.Notes[channel];v[channel]=s.Velocities[channel];five.Scores.Add(new(s.Time,n,v,(byte)(s.Retrigger&(1<<channel))));}var component=Synth.Render(five,true,false,false).Take(48000).ToArray();Check(component.Any(x=>x!=0),"independent PSG generator "+channel);for(int i=0;i<sum.Length;i++)sum[i]+=component[i];Wav(Path.Combine(output,"generator-"+channel+".wav"),component);}
    var fifth=Synth.Render(five,false,true,false).Take(48000).ToArray();Check(fifth.Any(x=>x!=0),"independent fifth PIT generator");for(int i=0;i<sum.Length;i++)sum[i]+=fifth[i];Check(all.Take(sum.Length).Select((x,i)=>Math.Abs(x-sum[i])<=2).All(x=>x),"all five independent generators retained in mix");Wav(Path.Combine(output,"five-generators.wav"),all.Take(48000).ToArray());
   }
   if(audioChecks)Ui(corpus,output);
   Results.Add("PASS: PIT contract qualification completed; MML authoring is outside player scope.");
  }catch(Exception ex){Results.Add(ex.ToString());Environment.ExitCode=1;}
  File.WriteAllLines(Path.Combine(output,"pit-results.txt"),Results);
 }
 // Independent closed-form phase oracle: hold preserves the original attack sample.
 static short[] ReferencePit(Movie m){var data=new short[m.Duration*24];int next=0,note=0,origin=0,divisor=0;
  for(int sample=0;sample<data.Length;sample++){while(next<m.PitNotes.Count&&m.PitNotes[next].Time*24<=sample){var p=m.PitNotes[next++];if(p.Note==0){note=0;origin=sample;}else if(p.Note!=note||p.Attack){note=p.Note;origin=sample;int hz=PitOscillator.Hertz[note-45];divisor=(1193182+hz/2)/hz;}}
   if(note!=0){long phase=(sample-(long)origin)*1193182%(divisor*24000L);data[sample]=(short)Math.Round((phase<((divisor+1)/2)*24000L?1:-1)*.19*32767);}}
  return data;
 }
 static void Open(Player p,string path){var t=p.OpenAsync(path,false);while(!t.IsCompleted){Application.DoEvents();Thread.Sleep(5);}t.GetAwaiter().GetResult();}
 static void Pump(Player p,int ms){var w=System.Diagnostics.Stopwatch.StartNew();while(w.ElapsedMilliseconds<ms){Application.DoEvents();p.TickPlayback();Thread.Sleep(5);}}
 static void Ui(string corpus,string output){string basic=Path.Combine(corpus,"BASIC","MOVIE.WZV");using var p=new Player();p.Show();Application.DoEvents();Check(!p.PitEnabled,"runtime PIT defaults off");try{Open(p,basic);throw new Exception("disabled UI accepted PIT");}catch(InvalidDataException){}Check(!p.Playing&&!p.AudioActive,"default-off open rejected before waveOut");p.PitEnabled=true;Open(p,basic);
  using(var image=new System.Drawing.Bitmap(p.Width,p.Height)){p.DrawToBitmap(image,new System.Drawing.Rectangle(0,0,image.Width,image.Height));image.Save(Path.Combine(output,"pit-ui.png"));}
  p.Toggle();Pump(p,180);Check(p.Playing&&p.Position>0,"PIT bundle actual waveOut clock");p.PitEnabled=false;Check(!p.Playing&&!p.AudioActive,"disable PIT releases owned output");int paused=p.Position;p.Toggle();Pump(p,100);Check(!p.Playing&&p.Position==paused,"disabled required voice cannot resume");p.PitEnabled=true;p.Toggle();Pump(p,100);Check(p.Playing,"explicit enable resumes required voice");p.SeekTo(300);Pump(p,100);Check(p.Position>=300&&p.Playing,"seek into held PIT state");p.SeekTo(0);Pump(p,100);Check(p.Position<400,"backward seek reconstructs phase");p.StopOwnedAudio();Check(!p.Playing&&!p.AudioActive,"ownership stop releases audio");p.SeekTo(950);p.Toggle();Pump(p,250);Check(!p.Playing&&p.Position==1000,"PIT end stops output");p.Toggle();Pump(p,100);Check(p.Playing&&p.Position<500,"PIT replay from end");
  typeof(Form).GetMethod("OnDeactivate",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic)!.Invoke(p,[EventArgs.Empty]);Check(!p.Playing&&!p.AudioActive,"internal deactivation event stops PIT output");
  p.Toggle();typeof(Form).GetMethod("OnKeyDown",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic)!.Invoke(p,[new KeyEventArgs(Keys.Escape)]);Check(!p.Playing&&!p.AudioActive,"internal Escape event stops PIT output");
  p.Toggle();typeof(Player).GetMethod("SessionChanged",System.Reflection.BindingFlags.Instance|System.Reflection.BindingFlags.NonPublic)!.Invoke(p,[p,new Microsoft.Win32.SessionSwitchEventArgs(Microsoft.Win32.SessionSwitchReason.SessionLock)]);Check(!p.Playing&&!p.AudioActive,"internal session loss event stops PIT output");
  Open(p,Path.Combine(corpus,"AUDIO","MOVIE.WZM"));p.Toggle();Pump(p,250);Check(p.Playing&&p.Position>0,"audio-only WZM2 waveOut playback; position="+p.Position+" playing="+p.Playing);
  try{Open(p,Path.Combine(corpus,"TRUNC","MOVIE.WZV"));throw new Exception("truncated UI accepted");}catch(InvalidDataException){}catch(EndOfStreamException){}Check(!p.Playing&&!p.AudioActive,"failed open stops prior owned output");
  Open(p,basic);p.Close();using var f=new FileStream(basic,FileMode.Open,FileAccess.ReadWrite,FileShare.None);Check(f.Length>0,"PIT close releases video handle");
 }
 static void Wav(string path,short[] pcm){using var w=new BinaryWriter(File.Create(path));w.Write(Encoding.ASCII.GetBytes("RIFF"));w.Write(36+pcm.Length*2);w.Write(Encoding.ASCII.GetBytes("WAVEfmt "));w.Write(16);w.Write((ushort)1);w.Write((ushort)1);w.Write(Synth.Rate);w.Write(Synth.Rate*2);w.Write((ushort)2);w.Write((ushort)16);w.Write(Encoding.ASCII.GetBytes("data"));w.Write(pcm.Length*2);foreach(short s in pcm)w.Write(s);}
}
