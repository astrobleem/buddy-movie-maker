using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace BuddyMovieMaker;
public static class SelfTest
{
    public static void Run(string output)
    {
        Directory.CreateDirectory(output);
        var results=new List<object>();
        void Test(string name,Action action){action();results.Add(new{name,pass=true});}
        void Check(bool ok,string message){if(!ok)throw new Exception(message);}
        void Reject(Action action){try{action();}catch(ArgumentException){return;}catch(InvalidDataException){return;}catch(IOException){return;}throw new Exception("Expected rejection.");}
        string video=Path.Combine(output,"GENERATED.AVI"), midi=Path.Combine(output,"GENERATED.MID"), captions=Path.Combine(output,"CAPTIONS.TXT");
        using(var ff=MovieEngine.Start(MovieEngine.Dependency("ffmpeg.exe"),["-nostdin","-v","error","-y","-f","lavfi","-i","testsrc2=size=320x200:rate=12:duration=2","-c:v","rawvideo",video]))
        {var err=ff.StandardError.ReadToEndAsync();var stdout=ff.StandardOutput.ReadToEndAsync();ff.WaitForExit();Check(ff.ExitCode==0,err.Result);}
        File.WriteAllText(captions,"0|HELLO TANDY\n1000|SECOND CUE\n1500|\n");
        // MIDI format 0: note A4 for one second, end at one second (480 PPQN).
        File.WriteAllBytes(midi,[77,84,104,100,0,0,0,6,0,0,0,1,1,224,77,84,114,107,0,0,0,13,0,144,69,100,135,64,128,69,0,0,255,47,0]);
        var none=CancellationToken.None;
        Test("decoder settings close relaunch alternate and invalid fallback",()=>
        {
            string settings=Path.Combine(output,"SETTINGS","settings.json"),selected=MovieEngine.DecoderDirectory!;
            JsonDocument Launch(string mode,string report,string decoder)
            {
                using var proc=new System.Diagnostics.Process{StartInfo=new(Environment.ProcessPath!){UseShellExecute=false,CreateNoWindow=true}};
                foreach(string arg in new[]{"--self-test-decoder-settings",mode,settings,report,decoder})proc.StartInfo.ArgumentList.Add(arg);
                proc.Start();if(!proc.WaitForExit(30000)){proc.Kill(true);throw new Exception("Settings relaunch timed out.");}
                Check(proc.ExitCode==0,File.ReadAllText(report));return JsonDocument.Parse(File.ReadAllText(report));
            }
            using(var saved=Launch("save",Path.Combine(output,"SETTINGS-SAVE.json"),selected))Check(saved.RootElement.GetProperty("status").GetString()!.Contains("remembered"),"Selection not saved.");
            using(var restored=Launch("restore",Path.Combine(output,"SETTINGS-RESTORE.json"),selected))Check(restored.RootElement.GetProperty("decoder").GetString()==selected&&restored.RootElement.GetProperty("status").GetString()!.Contains("verified"),"Actual relaunch did not restore.");
            string alternate=Path.Combine(output,"ALTERNATE-DECODER");Directory.CreateDirectory(alternate);
            File.Copy(Path.Combine(selected,"ffmpeg.exe"),Path.Combine(alternate,"ffmpeg.exe"));File.Copy(Path.Combine(selected,"ffprobe.exe"),Path.Combine(alternate,"ffprobe.exe"));
            using(var changed=Launch("save",Path.Combine(output,"SETTINGS-ALTERNATE.json"),alternate))Check(changed.RootElement.GetProperty("decoder").GetString()==alternate,"Alternate not selected.");
            using(var restored=Launch("restore",Path.Combine(output,"SETTINGS-ALTERNATE-RESTORE.json"),selected))Check(restored.RootElement.GetProperty("decoder").GetString()==alternate,"Alternate not remembered.");
            string before=File.ReadAllText(settings);File.Delete(Path.Combine(alternate,"ffprobe.exe"));
            using(var missing=Launch("restore",Path.Combine(output,"SETTINGS-MISSING.json"),selected))Check(missing.RootElement.GetProperty("decoder").ValueKind==JsonValueKind.Null&&missing.RootElement.GetProperty("status").GetString()!.Contains("unavailable"),"Missing pair did not fall back.");
            Check(File.ReadAllText(settings)==before,"Failed restore overwrote saved selection.");
            using(var recovery=Launch("save",Path.Combine(output,"SETTINGS-RECOVERY.json"),selected))Check(recovery.RootElement.GetProperty("decoder").GetString()==selected,"Reselection failed.");
            File.WriteAllText(settings,"not json");
            using(var corrupt=Launch("restore",Path.Combine(output,"SETTINGS-CORRUPT.json"),selected))Check(corrupt.RootElement.GetProperty("status").GetString()!.Contains("could not be read"),"Corrupt settings crashed or silently selected.");
            using(var repaired=Launch("save",Path.Combine(output,"SETTINGS-REPAIRED.json"),selected))Check(repaired.RootElement.GetProperty("decoder").GetString()==selected,"Corrupt settings not repairable by valid selection.");
        });
        Test("settings missing version unwritable and failed selection preserve session",()=>
        {
            string path=Path.Combine(output,"SETTINGS-EDGE.json");var settings=new DecoderSettings(path);
            Check(settings.Read()==(null,null),"First-run settings not empty.");
            File.WriteAllText(path,"{\"Version\":99,\"DecoderDirectory\":\"invalid\"}");Check(settings.Read().Warning!=null,"Future version not rejected.");
            string blocked=Path.Combine(output,"SETTINGS-BLOCKED");File.WriteAllText(blocked,"file instead of directory");Check(new DecoderSettings(Path.Combine(blocked,"settings.json")).SaveValidated(MovieEngine.DecoderDirectory!)!=null,"Unwritable settings unexpectedly saved.");
            string selected=MovieEngine.DecoderDirectory!;
            Reject(()=>MovieEngine.CheckDecoder(output,none).GetAwaiter().GetResult());Check(MovieEngine.DecoderDirectory==selected,"Bad selection changed current decoder.");
        });
        Test("duration diagnostics distinguish measured over-limit and invalid metadata",()=>
        {
            string Metadata(string? video,string? container=null)=>JsonSerializer.Serialize(new{streams=new[]{new{codec_type="video",duration=video}},format=new{duration=container}});
            string Message(string metadata){try{MovieEngine.ParseProbe(metadata);throw new Exception("Expected duration rejection.");}catch(InvalidDataException e){return e.Message;}}
            var limit=MovieEngine.ParseProbe(Metadata("600"));Check(limit.DurationMs==600000&&limit.Frames==2400,"Exact maximum rejected.");
            var shortVideo=MovieEngine.ParseProbe(Metadata("599.9994","634.566667"));Check(shortVideo.DurationMs==599999,"Container overrode selected video stream.");
            Check(Message(Metadata("634.566667")).Contains("10:34.567 (634.566667 seconds)"),"Measured duration omitted.");
            Check(Message(Metadata("600.0001")).Contains("600.0001 seconds"),"Sub-millisecond over-limit rounded into acceptance.");
            Check(Message(Metadata(null)).Contains("unknown or invalid"),"Missing duration indistinguishable.");
            foreach(string invalid in new[]{"N/A","NaN","Infinity"})Check(Message(Metadata(invalid)).Contains("unknown or invalid"),"Invalid duration indistinguishable.");
            foreach(string zero in new[]{"0","-1"})Check(Message(Metadata(zero)).Contains("greater than zero"),"Nonpositive duration indistinguishable.");
            Check(MovieEngine.ParseProbe(Metadata(null,"2.125")).DurationMs==2125,"Supported container fallback changed.");
            var culture=System.Globalization.CultureInfo.CurrentCulture;
            try{System.Globalization.CultureInfo.CurrentCulture=System.Globalization.CultureInfo.GetCultureInfo("fr-FR");Check(Message(Metadata("634.566667")).Contains("10:34.567"),"Duration diagnostic depends on locale.");}
            finally{System.Globalization.CultureInfo.CurrentCulture=culture;}
        });
        Test("external decoder prerequisite validation",()=>
        {
            string selected=MovieEngine.DecoderDirectory!;
            Reject(()=>MovieEngine.SelectDecoder(output));
            Check(MovieEngine.DecoderDirectory==selected,"Invalid selection changed decoder.");
            string description=MovieEngine.CheckDecoder(selected,none).GetAwaiter().GetResult();
            Check(description.Contains("ffmpeg version") && description.Contains("ffprobe version"),"Decoder identity missing.");
        });
        Test("video probe uses selected stream",()=>{var p=MovieEngine.Probe(video,none).GetAwaiter().GetResult();Check(p.DurationMs==2000 && p.Frames==8,"Wrong fixture timing.");});
        Test("MIDI structure and timeline",()=>{var b=MidiScore.Convert(midi,2000);Check(Encoding.ASCII.GetString(b,0,4)=="WZM1" && BitConverter.ToInt32(b,12)==2000,"Wrong score.");Reject(()=>MidiScore.Convert(midi,500));});
        Test("captions boundaries and empty optional track",()=>{Check(MovieEngine.Captions(null,2000).Count==0,"Optional captions.");Check(MovieEngine.Captions(captions,2000).Count==3,"Cues.");File.WriteAllText(Path.Combine(output,"BADCAP.TXT"),"2001|LATE\n");Reject(()=>MovieEngine.Captions(Path.Combine(output,"BADCAP.TXT"),2000));});
        Test("malformed MIDI",()=>{File.WriteAllBytes(Path.Combine(output,"BAD.MID"),[77,84,104]);Reject(()=>MidiScore.Convert(Path.Combine(output,"BAD.MID"),2000));});
        Test("malformed media and remote input rejection",()=>{File.WriteAllText(Path.Combine(output,"BAD.AVI"),"not media");Reject(()=>MovieEngine.Probe(Path.Combine(output,"BAD.AVI"),none).GetAwaiter().GetResult());Reject(()=>MovieEngine.Probe("https://example.org/movie",none).GetAwaiter().GetResult());});
        Test("audio-only input rejection",()=>
        {
            string wav=Path.Combine(output,"AUDIO.WAV");
            using var ff=MovieEngine.Start(MovieEngine.Dependency("ffmpeg.exe"),["-nostdin","-v","error","-f","lavfi","-i","sine=frequency=440:duration=1",wav]);
            var err=ff.StandardError.ReadToEndAsync();ff.WaitForExit();Check(ff.ExitCode==0,err.Result);
            Reject(()=>MovieEngine.Probe(wav,none).GetAwaiter().GetResult());
        });
        string silent=Path.Combine(output,"SILENT"), scored=Path.Combine(output,"SCORED");
        Test("source and selection exact fractional bounds",()=>
        {
            var source=MovieEngine.ParseSource("{\"streams\":[{\"codec_type\":\"video\",\"duration\":\"634.566667\"}]}");
            Check(source.DurationSeconds==634.566667m,"Long source duration rejected or rounded.");
            var max=MovieEngine.Select(source,34.566667m);Check(max.DurationMs==600000&&max.Frames==2400,"Exact600 selection rejected.");
            Reject(()=>MovieEngine.Select(source,34.566666m));
            foreach(var pair in new[]{(-1m,2m),(2m,1m),(2m,2m),(0m,0m),(0m,634.566668m),(634.566667m,634.566667m)})Reject(()=>MovieEngine.Select(source,pair.Item1,pair.Item2));
            Check(MovieEngine.Select(new(2,false),1.123m).DurationMs==877,"Fractional EOF bound.");
            Reject(()=>MovieEngine.Select(new(2,false),1.9999m));
            Check(MovieEngine.ParseTime("12.5")==12.5m&&MovieEngine.ParseTime("",true)==null,"Time controls.");
            foreach(string invalid in new[]{"", "NaN","Infinity","-1","1,5","1e3","00:01","1.2.3"})Reject(()=>MovieEngine.ParseTime(invalid));
        });
        Test("video-only export",()=>{MovieEngine.Export(video,null,null,silent,none).GetAwaiter().GetResult();Check(!File.Exists(Path.Combine(silent,"MOVIE.WZM")),"Unexpected music.");Check(new FileInfo(Path.Combine(silent,"MOVIE.WZV")).Length==24+8*MovieEngine.FrameBytes,"WZV length.");});
        Test("nonzero selection preview export identity and source frame fidelity",()=>
        {
            string destination=Path.Combine(output,"TRIMMED");
            MovieEngine.Export(video,null,null,destination,none,startSeconds:1,endSeconds:2).GetAwaiter().GetResult();
            var info=MovieEngine.Select(MovieEngine.ProbeSource(video,none).GetAwaiter().GetResult(),1,2);
            string preview=Path.Combine(output,"TRIM-PREVIEW.WZV");MovieEngine.Convert(video,preview,info,none).GetAwaiter().GetResult();
            var selected=File.ReadAllBytes(preview);Check(selected.SequenceEqual(File.ReadAllBytes(Path.Combine(destination,"MOVIE.WZV"))),"Selected preview differs from export.");
            var full=File.ReadAllBytes(Path.Combine(silent,"MOVIE.WZV"));Check(selected.AsSpan(24).SequenceEqual(full.AsSpan(24+4*MovieEngine.FrameBytes)),"Selected frames differ from expected source segment.");
            Check(BitConverter.ToInt32(selected,12)==4&&BitConverter.ToInt32(selected,16)==1000,"Selection header wrong.");
            using var manifest=JsonDocument.Parse(File.ReadAllText(Path.Combine(destination,"MANIFEST.JSON")));Check(manifest.RootElement.GetProperty("source_start_seconds").GetDecimal()==1&&manifest.RootElement.GetProperty("source_end_seconds").GetDecimal()==2,"Source range omitted.");
            string fraction=Path.Combine(output,"FRACTION");MovieEngine.Export(video,null,null,fraction,none,startSeconds:1.123m).GetAwaiter().GetResult();Check(new FileInfo(Path.Combine(fraction,"MOVIE.WZV")).Length==24+4*MovieEngine.FrameBytes,"Fractional EOF frame count.");
            string zero=Path.Combine(output,"ZEROEND");MovieEngine.Export(video,null,null,zero,none,endSeconds:1).GetAwaiter().GetResult();Check(File.ReadAllBytes(Path.Combine(zero,"MOVIE.WZV")).AsSpan(24).SequenceEqual(full.AsSpan(24,4*MovieEngine.FrameBytes)),"Zero-start selected frames changed.");
        });
        Test("selection cancellation retry and no overwrite",()=>
        {
            string path=Path.Combine(output,"TRIMRETRY");using var ct=new CancellationTokenSource();
            try{MovieEngine.Export(video,null,null,path,ct.Token,new InlineProgress(()=>ct.Cancel()),startSeconds:1).GetAwaiter().GetResult();throw new Exception("Expected cancellation.");}catch(OperationCanceledException){}
            Check(!Directory.Exists(path)&&Directory.GetDirectories(output,".buddy-*").Length==0,"Selection cancellation left staging.");
            MovieEngine.Export(video,null,null,path,none,startSeconds:1).GetAwaiter().GetResult();
            var before=File.ReadAllBytes(Path.Combine(path,"MOVIE.WZV"));Reject(()=>MovieEngine.Export(video,null,null,path,none,startSeconds:0,endSeconds:1).GetAwaiter().GetResult());Check(before.SequenceEqual(File.ReadAllBytes(Path.Combine(path,"MOVIE.WZV"))),"Selection overwrite changed output.");
            Reject(()=>MovieEngine.Export(video,null,null,Path.Combine(output,"BADRANGE"),none,startSeconds:2,endSeconds:1).GetAwaiter().GetResult());Check(!Directory.Exists(Path.Combine(output,"BADRANGE")),"Invalid range published.");
        });
        Test("MIDI and captions export",()=>{MovieEngine.Export(video,midi,captions,scored,none).GetAwaiter().GetResult();Check(File.Exists(Path.Combine(scored,"MOVIE.WZM")),"Music missing.");});
        Test("preview/export pixel identity",()=>{var a=File.ReadAllBytes(Path.Combine(silent,"MOVIE.WZV"));var b=File.ReadAllBytes(Path.Combine(scored,"MOVIE.WZV"));Check(a.SequenceEqual(b),"Conversion nondeterministic.");var frame=a.AsSpan(24,MovieEngine.FrameBytes).ToArray();var rgb=MovieEngine.Unpack(frame);Check(MovieEngine.Quantize(rgb).SequenceEqual(frame),"Preview loses palette indices.");var bmp=BitmapSource.Create(256,160,96,96,PixelFormats.Rgb24,null,rgb,768);var encoder=new PngBitmapEncoder();encoder.Frames.Add(BitmapFrame.Create(bmp));using var stream=File.Create(Path.Combine(output,"TANDY-PREVIEW.png"));encoder.Save(stream);});
        Test("no-overwrite preserves existing export",()=>{var before=File.ReadAllBytes(Path.Combine(silent,"MOVIE.WZV"));Reject(()=>MovieEngine.Export(video,null,null,silent,none).GetAwaiter().GetResult());Check(before.SequenceEqual(File.ReadAllBytes(Path.Combine(silent,"MOVIE.WZV"))),"Existing data changed.");});
        Test("cancellation and same-path retry",()=>
        {
            string cancelled=Path.Combine(output,"RETRY");using var ct=new CancellationTokenSource();
            var progress=new InlineProgress(()=>ct.Cancel());
            try{MovieEngine.Export(video,null,null,cancelled,ct.Token,progress).GetAwaiter().GetResult();throw new Exception("Expected cancellation.");}catch(OperationCanceledException){}
            Check(!Directory.Exists(cancelled) && Directory.GetDirectories(output,".buddy-*").Length==0,"Cancellation left output.");
            MovieEngine.Export(video,null,null,cancelled,none).GetAwaiter().GetResult();
        });
        Test("failed conversion cleans staging",()=>
        {
            string destination=Path.Combine(output,"FAILED");string bad=Path.Combine(output,"HEADERONLY.AVI");
            var bytes=File.ReadAllBytes(video);File.WriteAllBytes(bad,bytes[..Math.Min(bytes.Length,8192)]);
            Reject(()=>MovieEngine.Export(bad,null,null,destination,none).GetAwaiter().GetResult());
            Check(!Directory.Exists(destination) && Directory.GetDirectories(output,".buddy-*").Length==0,"Failure left output.");
        });
        string speechFile=Path.Combine(output,"VOICE.WAV");
        using(var ff=MovieEngine.Start(MovieEngine.Dependency("ffmpeg.exe"),["-nostdin","-v","error","-f","lavfi","-i","sine=frequency=440:duration=0.4","-ar","6000",speechFile]))
        {var err=ff.StandardError.ReadToEndAsync();ff.WaitForExit();Check(ff.ExitCode==0,err.Result);}
        Test("speech samples and scheduling",()=>
        {
            var clip=SpeechAudio.Prepare([new(speechFile,300)],2000,null,none).GetAwaiter().GetResult().Single();
            Check(clip.EndMs==700&&clip.Samples.Length==2400&&clip.Samples.All(b=>b>=1&&b<=72),"PCM profile.");
            Reject(()=>SpeechAudio.Prepare([new(speechFile,300),new(speechFile,500)],2000,null,none).GetAwaiter().GetResult());
            Reject(()=>SpeechAudio.Prepare([new(speechFile,1800)],2000,null,none).GetAwaiter().GetResult());
            Reject(()=>SpeechAudio.Prepare([new(speechFile,300)],2000,MidiScore.Convert(midi,2000),none).GetAwaiter().GetResult());
            Reject(()=>SpeechAudio.Prepare(Enumerable.Range(0,17).Select(i=>new SpeechRequest(speechFile,i*550)),10000,null,none).GetAwaiter().GetResult());
        });
        Test("video-only timed speech export",()=>MovieEngine.Export(video,null,captions,Path.Combine(output,"SPEECH"),none,speech:[new(speechFile,300)]).GetAwaiter().GetResult());
        Test("trim sidecars use output zero and selected duration",()=>
        {
            string cap=Path.Combine(output,"TRIMCAP.TXT");File.WriteAllText(cap,"0|OUTPUT ZERO\n750|\n");
            string path=Path.Combine(output,"TRIMTRACKS");MovieEngine.Export(video,midi,cap,path,none,startSeconds:1).GetAwaiter().GetResult();
            Check(File.ReadAllText(Path.Combine(path,"MOVIE.LRC")).StartsWith("0|OUTPUT ZERO"),"Caption shifted into source time.");
            Check(File.ReadAllBytes(Path.Combine(path,"MOVIE.WZM")).SequenceEqual(MidiScore.Convert(midi,1000)),"Music shifted into source time.");
            string voice=Path.Combine(output,"TRIMVOICE");MovieEngine.Export(video,null,cap,voice,none,speech:[new(speechFile,300)],startSeconds:1).GetAwaiter().GetResult();
            Check(BitConverter.ToInt32(File.ReadAllBytes(Path.Combine(voice,"SPEECH.PCM")),8)==300,"Speech shifted into source time.");
            Reject(()=>MovieEngine.Export(video,null,captions,Path.Combine(output,"TRIMBADCAP"),none,startSeconds:1).GetAwaiter().GetResult());
            Reject(()=>MovieEngine.Export(video,midi,null,Path.Combine(output,"TRIMBADMIDI"),none,startSeconds:1.6m).GetAwaiter().GetResult());
            Reject(()=>MovieEngine.Export(video,null,null,Path.Combine(output,"TRIMBADVOICE"),none,speech:[new(speechFile,700)],startSeconds:1).GetAwaiter().GetResult());
            string shortMml=Path.Combine(output,"TRIMSCORE.MML");File.WriteAllText(shortMml,"[A]\nT120 C4 D4\n");
            MovieEngine.Export(video,null,cap,Path.Combine(output,"TRIMMML"),none,mml:shortMml,startSeconds:1).GetAwaiter().GetResult();
        });
        Test("MIDI with speech in rest",()=>MovieEngine.Export(video,midi,captions,Path.Combine(output,"SPEECHM"),none,speech:[new(speechFile,1200)]).GetAwaiter().GetResult());
        Test("MML grammar timing and presets",()=>
        {
            var first=MmlScore.Compile("[A]\nT120 O4 L4 V12 @KEYS C D");
            Check(first.ScoreMs==1000&&BitConverter.ToInt32(first.Music,34)==500&&first.Music[24]==60&&first.Music[28]==100,"Conformance1.");
            Check(MmlScore.Compile("[A]\nT120 O4 C4. R8 > C8").ScoreMs==1250,"Dots/octaves.");
            Check(MmlScore.Compile("[A]\nT121 O4 [C64 R64]8").ScoreMs==496,"Carried remainder.");
            var v=MmlScore.Compile("[A]\nV0 C4 V15 @ORGAN C4");
            Check(v.Music[38]==60&&v.Music[42]==127&&v.Instruments[32]==16,"V0/preset at500.");
            foreach(string bad in new[]{"[A]\nO1 C","[A]\nT0 C","[A]\nL3 C","[A]\n@PLUCK C","[A]\n[C]9","[A]\n[[[C]2]2]2","[A]\nC\n[A]\nD","C D","[A]\nO2 C","[A]\n[C1]8"})Reject(()=>MmlScore.Compile(bad,2000));
            Reject(()=>MmlScore.Compile("[A]\n"+new string('C',8192)));
            var clipped=MmlScore.Compile("[A]\nT120 C4 D4",900);Check(BitConverter.ToInt32(clipped.Music,12)==900,"Trailing trim.");
            Reject(()=>MmlScore.Compile("[A]\nT120 C4 D4",400));
        });
        string mml=Path.Combine(output,"PRESETS.MML");File.WriteAllText(mml,"[A]\nT120 @PAD O3 C4 @ORGAN D4 @BELL E4 @HIT F4\n[B]\nT120 @LEAD O3 G2 R2\n");
        Test("expressive MML export",()=>MovieEngine.Export(video,null,captions,Path.Combine(output,"MML"),none,mml:mml).GetAwaiter().GetResult());
        string rest=Path.Combine(output,"SPEECH.MML");File.WriteAllText(rest,"[A]\nT120 R2 @REED O3 C2\n");
        Test("expressive MML and speech rest",()=>MovieEngine.Export(video,null,captions,Path.Combine(output,"MMLSPEAK"),none,speech:[new(speechFile,300)],mml:rest).GetAwaiter().GetResult());
        Test("MIDI MML mutually exclusive",()=>Reject(()=>MovieEngine.Export(video,midi,null,Path.Combine(output,"BADBOTH"),none,mml:mml).GetAwaiter().GetResult()));
        string contract=Path.Combine(AppContext.BaseDirectory,"test-contract");
        Test("MML2 shared six binary fixtures",()=>
        {
            foreach(string source in Directory.GetFiles(contract,"*.MML"))
            {
                var compiled=MmlScore.Compile(File.ReadAllText(source),vibrato:false);
                Check(compiled.Version==2,"MML2 version lost.");
                Check(compiled.Music.SequenceEqual(File.ReadAllBytes(Path.ChangeExtension(source,"WZM"))),"WZM fixture mismatch: "+Path.GetFileName(source));
                Check(compiled.Instruments.SequenceEqual(File.ReadAllBytes(Path.ChangeExtension(source,"WZI"))),"WZI fixture mismatch: "+Path.GetFileName(source));
            }
            Check(Directory.GetFiles(contract,"*.MML").Length==6,"Contract fixture count.");
        });
        Test("MML2 shared thirteen invalid fixtures",()=>
        {
            foreach(string source in Directory.GetFiles(contract,"*.BAD"))Reject(()=>MmlScore.Compile(File.ReadAllText(source)));
            Check(Directory.GetFiles(contract,"*.BAD").Length==13,"Invalid fixture count.");
        });
        Test("MML2 limits version and movie bounds",()=>
        {
            Reject(()=>MmlScore.Compile("MML3\n[N]\nN35"));Reject(()=>MmlScore.Compile("[N]\nN35"));
            Reject(()=>MmlScore.Compile("MML2\n[N]\n"+new string(' ',8192)));
            Reject(()=>MmlScore.Compile("MML2\n[N]\nT240 [["+string.Concat(Enumerable.Repeat("R64 ",65))+"]8]8"));
            Reject(()=>MmlScore.Compile("MML2\n[N]\nT40 [[N35/1 N35/1]8]8"));
            Reject(()=>MmlScore.Compile("MML2\n[N]\nT120 N35/4 N38/4",400));
            var clipped=MmlScore.Compile("MML2\n[N]\nT120 N35/4 N38/4",900);
            Check(BitConverter.ToInt32(clipped.Music,12)==900,"Noise trailing trim.");
            var zero=MmlScore.Compile("MML2\n[N]\nV0 N42/4");Check(zero.Music.AsSpan(24,4).IndexOfAnyExcept((byte)0)<0,"V0 is not a rest.");
        });
        string noise=Path.Combine(output,"NOISE.MML");File.Copy(Path.Combine(contract,"REPEAT.MML"),noise);
        Test("MML2 noise-only export",()=>MovieEngine.Export(video,null,null,Path.Combine(output,"NOISE"),none,mml:noise).GetAwaiter().GetResult());
        Test("MML2 mixed three tones and noise export",()=>MovieEngine.Export(video,null,captions,Path.Combine(output,"DRUMS"),none,mml:Path.Combine(contract,"BEAT120.MML")).GetAwaiter().GetResult());
        string noiseRest=Path.Combine(output,"NOISERST.MML");File.WriteAllText(noiseRest,"MML2\n[A]\nT120 R2 @REED O3 C2\n[N]\nT120 N42/64 R4 R8 R16 R32 R64 N38/2\n");
        Test("MML2 noise speech conflict and guarded rest",()=>
        {
            var active=MmlScore.Compile("MML2\n[N]\nN35/1",2000);
            Reject(()=>SpeechAudio.Prepare([new(speechFile,300)],2000,active.Music,none).GetAwaiter().GetResult());
            Reject(()=>MovieEngine.Export(video,null,null,Path.Combine(output,"NOISEBAD"),none,mml:noise,speech:[new(speechFile,300)]).GetAwaiter().GetResult());
            Check(!Directory.Exists(Path.Combine(output,"NOISEBAD")),"Conflict published an export.");
            MovieEngine.Export(video,null,captions,Path.Combine(output,"NOISESP"),none,mml:noiseRest,speech:[new(speechFile,300)]).GetAwaiter().GetResult();
        });
        string fixtures=Path.Combine(output,"MML-CONFORMANCE");Directory.CreateDirectory(fixtures);
        foreach(var fixture in new[]{("BASIC","[A]\nT120 O4 L4 V12 @KEYS C D\n"),("DOTTED","[A]\nT120 O4 C4. R8 > C8\n"),("CARRIED","[A]\nT121 O4 [C64 R64]8\n"),("PRESETS","[A]\n@PAD O3 C1\n[B]\n@BELL O4 G1\n")})
        {var compiled=MmlScore.Compile(fixture.Item2);File.WriteAllText(Path.Combine(fixtures,fixture.Item1+".MML"),fixture.Item2);File.WriteAllBytes(Path.Combine(fixtures,fixture.Item1+".WZM"),compiled.Music);File.WriteAllBytes(Path.Combine(fixtures,fixture.Item1+".WZI"),compiled.Instruments);}
        // Capture the native WPF layout with generated media, without any private input.
        Application.Current.Dispatcher.Invoke(()=>
        {
        var window=new MainWindow(new DecoderSettings(Path.Combine(output,"UI-SETTINGS.json")),false);window.Show();
        Test("native range controls update duration and invalidate stale preview",()=>
        {
            window.SetSourceForTest(new(634.566667m,true));window.TrimStart.Text="20";window.TrimEnd.Text="22";
            Check(window.SelectionLabel.Text.Contains("2 seconds")&&window.SelectionLabel.Text.Contains("8 frames"),"Selected duration not visible.");
            window.Timeline.IsEnabled=window.PlayButton.IsEnabled=true;window.TrimEnd.Text="21";
            Check(!window.Timeline.IsEnabled&&!window.PlayButton.IsEnabled&&window.PreviewImage.Source==null,"Stale preview stayed enabled.");
            window.TrimEnd.Text="19";Check(window.SelectionLabel.Text.Contains("start < end"),"Invalid range summary missing.");
            window.TrimStart.Text="0";window.TrimEnd.Text="";window.SetSourceForTest(new(2,false));
        });
        window.DecoderLabel.Text="External decoder selected (not bundled in this package)";
        window.VideoPath.Text=video;window.MmlPath.Text=Path.Combine(contract,"BEAT120.MML");window.CaptionPath.Text=captions;
        window.SetSourceForTest(new(2,false));
        var image=new BitmapImage(new Uri(Path.Combine(output,"TANDY-PREVIEW.png")));window.PreviewImage.Source=image;window.Placeholder.Visibility=Visibility.Collapsed;
        window.FrameLabel.Text="0.00s / 2.00s  ·  Frame 1/8";window.CaptionLabel.Text="HELLO TANDY";window.Status.Text="Generated fixture • video + MML2 drums + captions • export verified";
        window.UpdateLayout();
        var screenshot=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);screenshot.Render(window);
        var png=new PngBitmapEncoder();png.Frames.Add(BitmapFrame.Create(screenshot));using(var file=File.Create(Path.Combine(output,"MAKER-UI.png")))png.Save(file);
                window.MidiPath.Text="";window.MmlPath.Text=noiseRest;window.SpeechGrid.ItemsSource=new[]{new SpeechRequest(speechFile,300)};window.InputsScroll.ScrollToBottom();window.UpdateLayout();
        var audioShot=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32);audioShot.Render(window);
        var audioPng=new PngBitmapEncoder();audioPng.Frames.Add(BitmapFrame.Create(audioShot));using(var file=File.Create(Path.Combine(output,"MAKER-AUDIO-UI.png")))audioPng.Save(file);
        window.Close();
        });
        File.WriteAllText(Path.Combine(output,"RESULTS.json"),JsonSerializer.Serialize(new{tests=results,count=results.Count,fixture="generated FFmpeg testsrc2, authored MIDI and captions",claims="host conversion and transactional export; emulator tests separate"},new JsonSerializerOptions{WriteIndented=true}));
    }
    sealed class InlineProgress(Action callback):IProgress<double>{public void Report(double value)=>callback();}
    internal static async Task DecoderSettingsProcess(string mode,string settingsFile,string report,string directory)
    {
        var window=new MainWindow(new DecoderSettings(settingsFile),false){ShowInTaskbar=false,ShowActivated=false,Opacity=0};window.Show();
        try
        {
            if(mode=="save")await window.SelectAndRememberDecoder(directory,CancellationToken.None);
            else if(mode=="restore")await window.RestoreDecoder(CancellationToken.None);
            else throw new ArgumentException("Unknown settings test mode.");
            File.WriteAllText(report,JsonSerializer.Serialize(new{decoder=MovieEngine.DecoderDirectory,status=window.Status.Text,label=window.DecoderLabel.Text}));
        }
        finally{window.Close();}
    }
}
