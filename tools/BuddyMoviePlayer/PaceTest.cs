using System.Diagnostics;
using System.Text;
using System.Text.Json;
namespace BuddyMoviePlayer;
static class PaceTest
{
 public static void Run(string input,string output)
 {
  Directory.CreateDirectory(output);var events=new List<string>();
  try {
   string moviePath=input;
   bool pit=input=="synthetic-pit";
   if(input is "synthetic" or "synthetic-pit") {string folder=Path.Combine(output,"synthetic-72-seconds");CreateFixture(folder,pit);moviePath=Path.Combine(folder,"MOVIE.WZV");}
   using var movie=new Movie(moviePath,pit);int duration=movie.Duration;
   using var player=new Player(){PitEnabled=pit};player.Show();Application.DoEvents();var loading=Stopwatch.StartNew();var open=player.OpenAsync(moviePath,false);while(!open.IsCompleted){Application.DoEvents();Thread.Sleep(5);}open.GetAwaiter().GetResult();loading.Stop();
   events.Add($"duration_ms={duration}; sample_rate={Synth.Rate}; samples={duration*(Synth.Rate/1000)}; bytes={duration*(Synth.Rate/1000)*2}; format=mono PCM16; render_and_open_wall_ms={loading.ElapsedMilliseconds}");
   if(duration<30500)throw new InvalidDataException("Timing qualification needs a movie at least 30.5 seconds long.");
   player.Toggle();var main=Measure(player,Math.Min(60000,duration-500),Path.Combine(output,"main.csv"));
   events.Add(JsonSerializer.Serialize(new{segment="main",main.Wall,main.Advance,main.Ratio,main.Monotonic,main.MaxDrift,main.Type,main.RawAdvance,raw_samples_per_second=main.Type==2?main.RawAdvance/(main.Wall/1000.0):0}));
   player.Toggle();int paused=player.Position;Pump(player,500);bool pauseFrozen=player.Position==paused;events.Add($"pause_frozen={pauseFrozen}; pause_ms=500");
   player.SeekTo(Math.Min(30000,duration/2));int target=player.Position;player.Toggle();var seek=Measure(player,Math.Min(5000,duration-target-200),Path.Combine(output,"seek.csv"));events.Add(JsonSerializer.Serialize(new{segment="seek",target,seek.Wall,seek.Advance,seek.Ratio,seek.Monotonic}));
   player.SeekTo(Math.Min(5000,duration/4));var backward=Measure(player,Math.Min(5000,duration-player.Position-200),Path.Combine(output,"backward.csv"));events.Add(JsonSerializer.Serialize(new{segment="backward",backward.Wall,backward.Advance,backward.Ratio,backward.Monotonic}));
   player.SeekTo(duration-1000);var end=Stopwatch.StartNew();while(player.Playing&&end.ElapsedMilliseconds<3000){Pump(player,5);}end.Stop();bool stopped=!player.Playing;events.Add($"end_wall_ms={end.ElapsedMilliseconds}; end_position={player.Position}; stopped={stopped}");
   player.Toggle();var replay=Measure(player,5000,Path.Combine(output,"replay.csv"));events.Add(JsonSerializer.Serialize(new{segment="replay",replay.Wall,replay.Advance,replay.Ratio,replay.Monotonic}));player.Toggle();player.Close();
   bool pass=main.Wall>=29000&&Math.Abs(main.Ratio-1)<0.03&&main.Monotonic&&main.MaxDrift<250&&pauseFrozen&&Math.Abs(seek.Ratio-1)<0.08&&seek.Monotonic&&Math.Abs(backward.Ratio-1)<0.08&&backward.Monotonic&&Math.Abs(replay.Ratio-1)<0.08&&replay.Monotonic&&stopped&&end.ElapsedMilliseconds>=850&&end.ElapsedMilliseconds<1600;
   events.Add(pass?"PASS: real-time pacing and lifecycle":"FAIL: real-time pacing and lifecycle");if(!pass)Environment.ExitCode=1;
  }catch(Exception ex){events.Add(ex.ToString());Environment.ExitCode=1;}
  File.WriteAllLines(Path.Combine(output,"pace-results.txt"),events);
 }
 record Measurement(long Wall,int Advance,double Ratio,bool Monotonic,long MaxDrift,uint Type,long RawAdvance);
 static Measurement Measure(Player player,int milliseconds,string csv)
 {
  int first=player.Position,last=first;var rawFirst=player.AudioClock;uint rawLast=rawFirst.Value,type=rawFirst.Type;var wall=Stopwatch.StartNew();bool monotonic=true;long next=0,maxDrift=0;
  using var writer=new StreamWriter(csv);writer.WriteLine("wall_ms,position_ms,clock_type,clock_value");
  while(wall.ElapsedMilliseconds<milliseconds&&player.Playing) {Application.DoEvents();player.TickPlayback();int current=player.Position;if(current<last)monotonic=false;last=current;maxDrift=Math.Max(maxDrift,Math.Abs((current-first)-wall.ElapsedMilliseconds));
   if(wall.ElapsedMilliseconds>=next){var raw=player.AudioClock;type=raw.Type;rawLast=raw.Value;writer.WriteLine($"{wall.ElapsedMilliseconds},{current},{raw.Type},{raw.Value}");writer.Flush();next+=250;}Thread.Sleep(5);
  }
  Application.DoEvents();player.TickPlayback();var final=player.AudioClock;rawLast=final.Value;type=final.Type;return new(wall.ElapsedMilliseconds,player.Position-first,(player.Position-first)/(double)wall.ElapsedMilliseconds,monotonic,maxDrift,type,(long)rawLast-rawFirst.Value);
 }
 static void Pump(Player player,int ms){var watch=Stopwatch.StartNew();while(watch.ElapsedMilliseconds<ms){Application.DoEvents();player.TickPlayback();Thread.Sleep(5);}}
 internal static void CreateFixture(string folder,bool pit=false)
 {
  Directory.CreateDirectory(folder);const int duration=72000,width=256,height=160,frames=288;
  using(var w=new BinaryWriter(File.Create(Path.Combine(folder,"MOVIE.WZV")))){w.Write(Encoding.ASCII.GetBytes("WZV2"));w.Write((ushort)width);w.Write((ushort)height);w.Write((ushort)4);w.Write((ushort)24);w.Write(frames);w.Write(duration);w.Write(width*height/2);for(int f=0;f<frames;f++)for(int i=0;i<width*height/2;i++)w.Write((byte)(((f%16)<<4)|(i%16)));}
  using(var w=new BinaryWriter(File.Create(Path.Combine(folder,"MOVIE.WZM")))){w.Write(Encoding.ASCII.GetBytes("WZM1"));w.Write((ushort)20);w.Write((ushort)14);w.Write(2);w.Write(duration);w.Write(0);w.Write(0);w.Write(new byte[]{60,64,67,38});w.Write(new byte[]{88,88,88,64});w.Write((byte)15);w.Write((byte)0);w.Write(duration);w.Write(new byte[10]);}
  if(pit){foreach(var item in new[]{("MOVIE.WZV","WZV3"),("MOVIE.WZM","WZM2")}){using var f=new FileStream(Path.Combine(folder,item.Item1),FileMode.Open,FileAccess.Write);f.Write(Encoding.ASCII.GetBytes(item.Item2));}
   File.WriteAllText(Path.Combine(folder,"PIT.REQ"),"WZP1");using var w=new BinaryWriter(File.Create(Path.Combine(folder,"MOVIE.WZP")));w.Write(Encoding.ASCII.GetBytes("WZP1"));w.Write((ushort)1);w.Write((ushort)0);w.Write(duration);w.Write((ushort)4);w.Write((ushort)0);foreach(var p in new[]{new PitNote(0,69,true),new PitNote(30000,69,true),new PitNote(45000,76,false),new PitNote(duration,0,false)}){w.Write(p.Time);w.Write(p.Note);w.Write((byte)(p.Attack?1:0));w.Write((ushort)0);}}
 }
}
