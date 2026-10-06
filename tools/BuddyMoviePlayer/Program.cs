using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
namespace BuddyMoviePlayer;
static class Program
{
 [STAThread] static void Main(string[] args) {
  ApplicationConfiguration.Initialize();
  if(args.Length==2&&args[0]=="--self-test") {SelfTest.Run(args[1]);return;}
  if(args.Length==2&&args[0]=="--self-test-headless") {SelfTest.Run(args[1],false);return;}
  if(args.Length==3&&args[0]=="--verify-file") {SelfTest.VerifyFile(args[1],args[2]);return;}
  if(args.Length==3&&args[0]=="--pace-test") {PaceTest.Run(args[1],args[2]);return;}
  Application.Run(new Player(args.FirstOrDefault()));
 }
}
public sealed class Screen : Control
{
 public Bitmap? Frame;
 public Screen() {DoubleBuffered=true;BackColor=Color.Black;}
 protected override void OnPaint(PaintEventArgs e) {base.OnPaint(e);if(Frame==null)return;double scale=Math.Min((double)Width/Frame.Width,(double)Height/Frame.Height);int w=(int)(Frame.Width*scale),h=(int)(Frame.Height*scale);e.Graphics.InterpolationMode=InterpolationMode.NearestNeighbor;e.Graphics.PixelOffsetMode=PixelOffsetMode.Half;e.Graphics.DrawImage(Frame,new Rectangle((Width-w)/2,(Height-h)/2,w,h),0,0,Frame.Width,Frame.Height,GraphicsUnit.Pixel);}
 protected override void Dispose(bool disposing) {if(disposing)Frame?.Dispose();base.Dispose(disposing);}
}
public sealed class Player : Form
{
 readonly Screen screen=new(){Dock=DockStyle.Fill};
 readonly Button open=new(){Text="Open…",AutoSize=true},play=new(){Text="Play",AutoSize=true},replay=new(){Text="Replay",AutoSize=true},full=new(){Text="Fullscreen",AutoSize=true};
 readonly TrackBar seek=new(){Dock=DockStyle.Fill,Minimum=0,Maximum=1000,TickStyle=TickStyle.None},volume=new(){Minimum=0,Maximum=100,Value=70,Width=110,TickStyle=TickStyle.None};
 readonly Label status=new(){AutoSize=true,Text="Open a Buddy WZV movie"},caption=new(){Dock=DockStyle.Bottom,Height=42,TextAlign=ContentAlignment.MiddleCenter,Font=new Font("Segoe UI",14,FontStyle.Bold)};
 readonly System.Windows.Forms.Timer timer=new(){Interval=25};readonly WaveAudio audio=new();
 Movie? movie;short[] samples=[];int position,lastFrame=-1;bool playing,updating,fullscreen,loading,closed;Rectangle savedBounds;FormWindowState savedState;
 public int Position=>position;public bool Playing=>playing;
 public (uint Type,uint Value) AudioClock=>audio.ReadClock();
 public Player(string? initial=null) {
  Text="Buddy Movie Player • Windows x64";MinimumSize=new Size(640,440);Size=new Size(980,740);BackColor=Color.FromArgb(22,26,33);ForeColor=Color.White;Font=new Font("Segoe UI",10);KeyPreview=true;
  var controls=new FlowLayoutPanel(){Dock=DockStyle.Bottom,Height=52,Padding=new Padding(12,7,0,0)};
  controls.Controls.AddRange([open,play,replay,full,new Label{Text="Volume",AutoSize=true,Padding=new Padding(10,9,0,0)},volume,status]);
  foreach(var b in new[]{open,play,replay,full}) {b.BackColor=Color.FromArgb(48,58,76);b.ForeColor=Color.White;b.FlatStyle=FlatStyle.Flat;}
  var seekPanel=new Panel{Dock=DockStyle.Bottom,Height=38};seekPanel.Controls.Add(seek);
  Controls.Add(screen);Controls.Add(caption);Controls.Add(seekPanel);Controls.Add(controls);
  open.Click+=async(_,_)=>{using var dialog=new OpenFileDialog{Filter="Buddy movie (*.wzv)|*.wzv",CheckFileExists=true};if(dialog.ShowDialog(this)==DialogResult.OK)await OpenAsync(dialog.FileName);};
  play.Click+=(_,_)=>Toggle();replay.Click+=(_,_)=>{SeekTo(0);if(!playing)Toggle();};full.Click+=(_,_)=>Fullscreen();
  seek.Scroll+=(_,_)=>{if(!updating&&movie!=null)SeekTo((int)((long)seek.Value*movie.Duration/1000));};
  volume.ValueChanged+=(_,_)=>{if(playing){position=audio.Milliseconds;Restart();}};
  timer.Tick+=(_,_)=>TickPlayback();timer.Start();
  KeyDown+=(_,e)=>{if(e.KeyCode==Keys.Space){Toggle();e.Handled=true;}else if(e.KeyCode==Keys.F11){Fullscreen();e.Handled=true;}else if(e.KeyCode==Keys.Escape&&fullscreen)Fullscreen();else if(e.KeyCode==Keys.Left)SeekTo(Math.Max(0,position-5000));else if(e.KeyCode==Keys.Right&&movie!=null)SeekTo(Math.Min(movie.Duration,position+5000));};
  Shown+=async(_,_)=>{if(initial!=null)await OpenAsync(initial);};
 }
 public async Task OpenAsync(string path,bool showErrors=true) {
  if(loading||closed)return; loading=true;playing=false;audio.Stop();play.Text="Play";open.Enabled=play.Enabled=replay.Enabled=seek.Enabled=volume.Enabled=false;status.Text="Loading…";
  Movie? next=null;
  try {next=new Movie(path);short[] pcm=await Task.Run(()=>Synth.Render(next));if(closed){next.Dispose();next=null;return;}movie?.Dispose();movie=next;next=null;samples=pcm;position=0;lastFrame=-1;Text="Buddy Movie Player • "+Path.GetFileName(path);DrawFrame();status.Text=$"{movie.Width}×{movie.Height} • {movie.Fps} fps • ready";}
  catch(Exception ex){next?.Dispose();status.Text="Open failed";if(showErrors)MessageBox.Show(this,ex.Message,"Cannot open Buddy movie",MessageBoxButtons.OK,MessageBoxIcon.Error);else throw;}
  finally{loading=false;if(!closed)open.Enabled=play.Enabled=replay.Enabled=seek.Enabled=volume.Enabled=true;}
 }
 public void Toggle() {if(movie==null||loading||closed)return;if(playing) {position=audio.Milliseconds;audio.Stop();playing=false;play.Text="Play";}else{if(position>=movie.Duration)position=0;Restart();}DrawFrame();}
 void Restart() {try {audio.Start(samples,position,volume.Value/100.0);playing=true;play.Text="Pause";}catch(Exception ex){playing=false;audio.Stop();status.Text=ex.Message;}}
 public void SeekTo(int ms) {if(movie==null||loading||closed)return;bool resume=playing;audio.Stop();playing=false;position=Math.Clamp(ms,0,movie.Duration);if(resume&&position<movie.Duration)Restart();else play.Text="Play";DrawFrame();}
 public void TickPlayback() {if(movie==null||!playing)return;try {position=audio.Completed?movie.Duration:Math.Min(movie.Duration,audio.Milliseconds);if(position>=movie.Duration) {playing=false;audio.Stop();play.Text="Play";}DrawFrame();}catch(Exception ex){audio.Stop();playing=false;play.Text="Play";status.Text=ex.Message;}}
 void DrawFrame() {
  if(movie==null)return;int frame=Math.Min(movie.Frames-1,position*movie.Fps/1000);
  if(frame!=lastFrame) {byte[] raw=movie.Frame(position);Bitmap bitmap=new(movie.Width,movie.Height,PixelFormat.Format24bppRgb);
   int[] palette=[0x000000,0x0000aa,0x00aa00,0x00aaaa,0xaa0000,0xaa00aa,0xaa5500,0xaaaaaa,0x555555,0x5555ff,0x55ff55,0x55ffff,0xff5555,0xff55ff,0xffff55,0xffffff];
   for(int y=0;y<movie.Height;y++)for(int x=0;x<movie.Width;x++){int packed=raw[(y*movie.Width+x)/2],color=palette[(x&1)==0?packed>>4:packed&15];bitmap.SetPixel(x,y,Color.FromArgb(color>>16,(color>>8)&255,color&255));}
   screen.Frame?.Dispose();screen.Frame=bitmap;screen.Invalidate();lastFrame=frame;
  }
  caption.Text=movie.Caption(position);updating=true;seek.Value=(int)((long)position*1000/movie.Duration);updating=false;status.Text=$"{position/1000:0}s / {movie.Duration/1000:0}s • {(playing?"playing":position>=movie.Duration?"ended":"paused")}";
 }
 public void Fullscreen() {if(!fullscreen){savedBounds=Bounds;savedState=WindowState;WindowState=FormWindowState.Normal;FormBorderStyle=FormBorderStyle.None;Bounds=System.Windows.Forms.Screen.FromControl(this).Bounds;fullscreen=true;}else{FormBorderStyle=FormBorderStyle.Sizable;Bounds=savedBounds;WindowState=savedState;fullscreen=false;}}
 protected override void Dispose(bool disposing) {if(disposing){closed=true;timer.Stop();timer.Dispose();audio.Dispose();movie?.Dispose();}base.Dispose(disposing);}
}
