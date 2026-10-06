using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Microsoft.Win32;
namespace BuddyMovieMaker;
public partial class MainWindow : Window
{
    CancellationTokenSource? cancellation;
    string? preview, previewFolder;
    MovieInfo? movie;
    SourceInfo? sourceInfo;
    List<Cue> cues = new();
    readonly System.Collections.ObjectModel.ObservableCollection<SpeechRequest> speech=new();
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(250) };
    readonly DecoderSettings settings;
    public MainWindow():this(new DecoderSettings()){}
    internal MainWindow(DecoderSettings settings,bool restore=true)
    {
        this.settings=settings;
        InitializeComponent();
        SpeechGrid.ItemsSource=speech;
        timer.Tick += (_, _) => { if(Timeline.Value>=Timeline.Maximum){timer.Stop();Timeline.Value=0;}else Timeline.Value++; };
        Closing += (_, e) => { if(cancellation!=null){e.Cancel=true;cancellation.Cancel();Status.Text="Cancelling safely. Close again when finished.";} };
        Closed += (_, _) => {timer.Stop();DeletePreview();};
        if(restore)Loaded += async (_,_)=>await Run(RestoreDecoder);
    }
    internal async Task RestoreDecoder(CancellationToken ct)
    {
        var saved=settings.Read();
        if(saved.Directory==null){if(saved.Warning!=null){DecoderLabel.Text=saved.Warning;Status.Text=saved.Warning;}return;}
        Status.Text="Checking saved FFmpeg folder...";
        try
        {
            await MovieEngine.CheckDecoder(saved.Directory,ct);
            DecoderLabel.Text="Remembered FFmpeg: "+saved.Directory;
            Status.Text="Saved FFmpeg folder verified. Choose a video to begin.";
        }
        catch(OperationCanceledException) when(ct.IsCancellationRequested){throw;}
        catch(Exception error) when(error is IOException or InvalidDataException or ArgumentException or InvalidOperationException or System.ComponentModel.Win32Exception)
        {DecoderLabel.Text="Saved FFmpeg folder unavailable. Choose existing FFmpeg to select it again.";Status.Text=DecoderLabel.Text;}
    }
    internal async Task SelectAndRememberDecoder(string directory,CancellationToken ct)
    {
        string description=await MovieEngine.CheckDecoder(directory,ct);
        ct.ThrowIfCancellationRequested();
        string? warning=settings.SaveValidated(MovieEngine.DecoderDirectory!);
        DecoderLabel.Text="Decoder selected: "+MovieEngine.DecoderDirectory;
        Status.Text=warning??("FFmpeg location remembered. "+description);
    }
    string? Browse(string filter)
    {var dialog=new OpenFileDialog{Filter=filter,CheckFileExists=true};return dialog.ShowDialog(this)==true?dialog.FileName:null;}
    async void VideoBrowse(object sender,RoutedEventArgs e)
    {
        var path=Browse("Video files|*.mp4;*.avi;*.mov;*.mkv;*.webm;*.wmv;*.mpeg;*.mpg|All files|*.*");
        if(path==null)return;VideoPath.Text=path;sourceInfo=null;InvalidatePreview();TrimStart.Text="0";TrimEnd.Text="";SourceLabel.Text="Reading source duration...";
        await Run(async ct=>{sourceInfo=await MovieEngine.ProbeSource(path,ct);SourceLabel.Text=$"Source: {sourceInfo.DurationSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture)} seconds";UpdateSelection();Status.Text="Set the source start/end, then build a preview or export.";});
    }
    void InvalidatePreview(){DeletePreview();movie=null;Timeline.IsEnabled=PlayButton.IsEnabled=false;PreviewImage.Source=null;Placeholder.Visibility=Visibility.Visible;FrameLabel.Text="Build preview for the selected section";CaptionLabel.Text="";}
    void RangeChanged(object sender,TextChangedEventArgs e)
    {if(SelectionLabel==null || Timeline==null)return;InvalidatePreview();UpdateSelection();}
    (decimal start,decimal? end) RangeInputs()=> (MovieEngine.ParseTime(TrimStart.Text)!.Value,MovieEngine.ParseTime(TrimEnd.Text,true));
    internal void UpdateSelection()
    {
        if(sourceInfo==null){SelectionLabel.Text="Choose a video to set the range.";return;}
        try{var range=RangeInputs();var selected=MovieEngine.Select(sourceInfo,range.start,range.end);SelectionLabel.Text=$"Selected: {selected.DurationMs/1000.0:0.###} seconds · {selected.Frames} frames (output starts at 0)";}
        catch(Exception error){SelectionLabel.Text=error.Message;}
    }
    internal void SetSourceForTest(SourceInfo info){sourceInfo=info;SourceLabel.Text=$"Source: {info.DurationSeconds} seconds";UpdateSelection();}
    void MidiBrowse(object sender,RoutedEventArgs e){var path=Browse("MIDI files|*.mid;*.midi");if(path!=null){MidiPath.Text=path;MmlPath.Text="";}}
    void CaptionBrowse(object sender,RoutedEventArgs e){var path=Browse("Caption files|*.txt;*.lrc");if(path!=null)CaptionPath.Text=path;}
    void MmlBrowse(object sender,RoutedEventArgs e){var path=Browse("MML scores|*.mml");if(path!=null){MmlPath.Text=path;MidiPath.Text="";}}
    void SpeechAdd(object sender,RoutedEventArgs e)
    {
        if(!int.TryParse(SpeechStart.Text,out int time)||time<0){Status.Text="Speech start must be a nonnegative movie time in milliseconds.";return;}
        if(speech.Count>=16){Status.Text="Maximum 16 speech clips.";return;}
        var path=Browse("Audio clips|*.wav;*.mp3;*.flac;*.ogg;*.m4a;*.aac|All files|*.*");
        if(path!=null)speech.Add(new(path,time));
    }
    void SpeechRemove(object sender,RoutedEventArgs e){if(SpeechGrid.SelectedItem is SpeechRequest selected)speech.Remove(selected);}
    SpeechRequest[] SpeechInputs()
    {
        if(!SpeechGrid.CommitEdit(DataGridEditingUnit.Cell,true)||!SpeechGrid.CommitEdit(DataGridEditingUnit.Row,true))throw new ArgumentException("Finish editing speech start times (whole nonnegative milliseconds).");
        return speech.Select(s=>new SpeechRequest(s.Path,s.StartMs)).ToArray();
    }
    async void DecoderBrowse(object sender,RoutedEventArgs e)
    {
        var path=Browse("Existing FFmpeg executable|ffmpeg.exe");if(path==null)return;
        await Run(async ct=>
        {
            await SelectAndRememberDecoder(Path.GetDirectoryName(path)!,ct);
        });
    }
    void Busy(bool busy)
    {Inputs.IsEnabled=ExportButton.IsEnabled=DecoderButton.IsEnabled=!busy;CancelButton.IsEnabled=busy;Progress.Value=0;timer.Stop();}
    async Task Run(Func<CancellationToken,Task> work)
    {
        if(cancellation!=null)return;
        cancellation=new();Busy(true);
        try{await work(cancellation.Token);}
        catch(OperationCanceledException){Status.Text="Cancelled. No export was published. You can retry.";}
        catch(Exception error){Status.Text=error.Message;MessageBox.Show(this,error.Message,"Buddy Movie Maker",MessageBoxButton.OK,MessageBoxImage.Warning);}
        finally{cancellation.Dispose();cancellation=null;Busy(false);}
    }
    async void PreviewClick(object sender,RoutedEventArgs e)
    {
        string source=VideoPath.Text, midi=MidiPath.Text, captions=CaptionPath.Text,mml=MmlPath.Text;
        int initialProgram=PresetBox.SelectedIndex*16;bool vibrato=VibratoBox.IsChecked==true;
        await Run(async ct=>
        {
            Status.Text="Building exact Tandy frames…";
            var range=RangeInputs();sourceInfo=await MovieEngine.ProbeSource(source,ct);UpdateSelection();var info=MovieEngine.Select(sourceInfo,range.start,range.end);
            var validated=MovieEngine.Captions(captions,info.DurationMs);
            if(!string.IsNullOrWhiteSpace(midi)&&!string.IsNullOrWhiteSpace(mml))throw new ArgumentException("Choose MIDI or MML, not both.");
            var expressive=!string.IsNullOrWhiteSpace(mml)?MmlScore.FromFile(mml,info.DurationMs,initialProgram,vibrato):null;
            byte[]? music=expressive?.Music??(string.IsNullOrWhiteSpace(midi)?null:MidiScore.Convert(midi,info.DurationMs));
            await SpeechAudio.Prepare(SpeechInputs(),info.DurationMs,music,ct,expressive?.Pit);
            string folder=Path.Combine(Path.GetTempPath(),"BuddyMaker-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(folder);
            bool accepted=false;
            try
            {
                var progress=new Progress<double>(v=>Progress.Value=v);
                await Task.Run(()=>MovieEngine.Convert(source,Path.Combine(folder,"MOVIE.WZV"),info,ct,progress,expressive?.Pit!=null),ct);
                ct.ThrowIfCancellationRequested();DeletePreview();previewFolder=folder;preview=Path.Combine(folder,"MOVIE.WZV");movie=info;cues=validated;accepted=true;
                Timeline.Maximum=info.Frames-1;Timeline.Value=0;Timeline.IsEnabled=PlayButton.IsEnabled=true;Placeholder.Visibility=Visibility.Collapsed;ShowFrame(0);
                Status.Text=$"Ready: {info.DurationMs/1000.0:0.00}s, {info.Frames} frames. "+(info.HasAudio?"Video soundtrack omitted. ":"")+"Export uses the same conversion. "+(expressive?.Pit!=null?"Required [P] voice: silent preview; enable its checkbox for export.":"");
            }
            finally{if(!accepted)Directory.Delete(folder,true);}
        });
    }
    async void ExportClick(object sender,RoutedEventArgs e)
    {
        var dialog=new SaveFileDialog{Title="Choose a NEW movie folder name",FileName="MyTandyMovie",Filter="Movie folder name|*",AddExtension=false,OverwritePrompt=true};
        if(dialog.ShowDialog(this)!=true)return;
        string source=VideoPath.Text,midi=MidiPath.Text,captions=CaptionPath.Text,destination=dialog.FileName,mml=MmlPath.Text;
        int initialProgram=PresetBox.SelectedIndex*16;bool vibrato=VibratoBox.IsChecked==true;
        bool pitEnabled=PitBox.IsChecked==true;
        await Run(async ct=>
        {
            Status.Text="Converting and assembling your movie folder…";
            var progress=new Progress<double>(v=>Progress.Value=v);
            var clips=SpeechInputs();
            var range=RangeInputs();sourceInfo=await MovieEngine.ProbeSource(source,ct);UpdateSelection();MovieEngine.Select(sourceInfo,range.start,range.end);
            await Task.Run(()=>MovieEngine.Export(source,midi,captions,destination,ct,progress,clips,mml,initialProgram,vibrato,range.start,range.end,pitEnabled),ct);
            Status.Text="Export complete: "+destination+". Copy the whole folder and run PLAY on your Tandy.";
        });
    }
    void CancelClick(object sender,RoutedEventArgs e){cancellation?.Cancel();}
    void PlayClick(object sender,RoutedEventArgs e){if(timer.IsEnabled)timer.Stop();else if(preview!=null)timer.Start();}
    void Seek(object sender,RoutedPropertyChangedEventArgs<double> e){if(preview!=null)ShowFrame((int)e.NewValue);}
    void ShowFrame(int frame)
    {
        if(preview==null || movie==null)return;
        using var file=File.OpenRead(preview);file.Position=24+(long)frame*MovieEngine.FrameBytes;
        byte[] packed=new byte[MovieEngine.FrameBytes];file.ReadExactly(packed);
        var bitmap=BitmapSource.Create(256,160,96,96,PixelFormats.Rgb24,null,MovieEngine.Unpack(packed),256*3);bitmap.Freeze();PreviewImage.Source=bitmap;
        FrameLabel.Text=$"{frame/4.0:0.00}s / {movie.DurationMs/1000.0:0.00}s  ·  Frame {frame+1}/{movie.Frames}";
        CaptionLabel.Text=cues.LastOrDefault(c=>c.Time<=frame*250)?.Text??"";
    }
    void DeletePreview(){timer.Stop();preview=null;if(previewFolder!=null && Directory.Exists(previewFolder))Directory.Delete(previewFolder,true);previewFolder=null;}
}
