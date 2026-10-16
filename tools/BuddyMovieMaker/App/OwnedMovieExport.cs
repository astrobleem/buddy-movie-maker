using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace BuddyMovieMaker;

// Explicit owned-score workflow. The ordinary MIDI/export path is unchanged.
// No implicit cue inference, automatic soundtrack transcription or PIT gain.
public static class OwnedMovieExport
{
    public static Task Export(string video,VerifiedOwnedMidi score,CueVolumePlan automation,
        string destination,CancellationToken ct,int? filmOriginMs=null,string? captions=null,decimal startSeconds=0,decimal? endSeconds=null,
        IProgress<double>? progress=null,IEnumerable<SpeechRequest>? speech=null)
        => ExportCore(video,score,automation,destination,ct,filmOriginMs,captions,startSeconds,endSeconds,progress,speech,null);

    // Audited test harness only: stage candidate bundles for native qualification.
    // No fabricated capability receipt; every candidate manifest says unqualified.
    internal static Task ExportForQualification(string video,VerifiedOwnedMidi score,CueVolumePlan automation,
        string destination,CancellationToken ct,string runtime,int? filmOriginMs=null,string? captions=null,
        decimal startSeconds=0,decimal? endSeconds=null,IProgress<double>? progress=null,IEnumerable<SpeechRequest>? speech=null)
        => ExportCore(video,score,automation,destination,ct,filmOriginMs,captions,startSeconds,endSeconds,progress,speech,runtime);

    static async Task ExportCore(string video,VerifiedOwnedMidi score,CueVolumePlan automation,
        string destination,CancellationToken ct,int? filmOriginMs,string? captions,decimal startSeconds,decimal? endSeconds,
        IProgress<double>? progress,IEnumerable<SpeechRequest>? speech,string? qualificationRuntime)
    {
        destination=Path.GetFullPath(destination);if(destination.StartsWith(@"\\"))throw new ArgumentException("Choose a local output folder.");
        if(Directory.Exists(destination)||File.Exists(destination))throw new IOException("Choose a new folder. Existing destinations are never overwritten.");
        ct.ThrowIfCancellationRequested();
        var movie=MovieEngine.Select(await MovieEngine.ProbeSource(video,ct),startSeconds,endSeconds);
        if(startSeconds*1000!=decimal.Truncate(startSeconds*1000))throw new InvalidDataException("Owned score origin must be an exact millisecond.");
        var arranged=MidiScore.ArrangeOwned(score,automation,filmOriginMs??checked((int)(startSeconds*1000)),movie.DurationMs);
        var cues=MovieEngine.Captions(captions,movie.DurationMs);
        var clips=await SpeechAudio.Prepare(speech,movie.DurationMs,arranged.Music,ct);
        string directory=Path.Combine(AppContext.BaseDirectory,"runtime-gain"),runtime=Path.Combine(directory,"MOVPLAY.EXE");
        string capability=Path.Combine(directory,"GAIN.CAP"),receipt=Path.Combine(directory,"QUALIFIED.json");
        if(qualificationRuntime!=null){MovieEngine.RequireLocal(qualificationRuntime);runtime=qualificationRuntime;}
        else
        {
        if(!File.Exists(runtime)||!File.Exists(capability)||!File.ReadAllBytes(capability).SequenceEqual(Encoding.ASCII.GetBytes("WZG1"))||!File.Exists(receipt))
            throw new IOException("Owned gain export requires a separately qualified WZG1 runtime package.");
        using(var qualification=JsonDocument.Parse(File.ReadAllText(receipt)))
        {
            var q=qualification.RootElement;
            string hash=System.Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(runtime)));
            if(q.GetProperty("contract").GetString()!="WZG1-v1"||q.GetProperty("runtime_sha256").GetString()!=hash||
               q.GetProperty("spec_sha256").GetString()!="5B7797BB161C4D1BD4005F03FD617DFF096BBBF9EE2A16E6E700831B569612BB"||
               !q.GetProperty("native_pass").GetBoolean()||!q.GetProperty("speech_pass").GetBoolean())
                throw new IOException("Gain qualification receipt does not match this runtime and contract.");
        }
        }
        string parent=Path.GetDirectoryName(destination)??throw new IOException("Destination parent required.");
        Directory.CreateDirectory(parent);string staging=Path.Combine(parent,".buddy-gain-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(staging);
        try
        {
            await MovieEngine.Convert(video,Path.Combine(staging,"MOVIE.WZV"),movie,ct,progress);
            // Identical RGBI frames; only the directly consumed family magic changes.
            using(var frameFile=new FileStream(Path.Combine(staging,"MOVIE.WZV"),FileMode.Open,FileAccess.Write))frameFile.Write(Encoding.ASCII.GetBytes("WZV4"));
            File.Copy(runtime,Path.Combine(staging,"MOVPLAY.EXE"));
            File.WriteAllBytes(Path.Combine(staging,"MOVIE.WZM"),arranged.Music);File.WriteAllBytes(Path.Combine(staging,"MOVIE.WZI"),arranged.Instruments);File.WriteAllBytes(Path.Combine(staging,"MOVIE.WZG"),arranged.Gain);
            File.WriteAllBytes(Path.Combine(staging,"INST.REQ"),Encoding.ASCII.GetBytes("WZI1"));File.WriteAllBytes(Path.Combine(staging,"GAIN.REQ"),Encoding.ASCII.GetBytes("WZG1"));
            File.WriteAllLines(Path.Combine(staging,"MOVIE.LRC"),cues.Select(c=>$"{c.Time}|{c.Text}"),Encoding.ASCII);
            SpeechAudio.Write(Path.Combine(staging,"SPEECH.PCM"),clips);
            File.WriteAllText(Path.Combine(staging,"PLAY.BAT"),"@echo off\r\nMOVPLAY\r\n",Encoding.ASCII);
            File.WriteAllText(Path.Combine(staging,"README.TXT"),"Owned MIDI gain export: copy the whole folder; exit Windows and run PLAY on Tandy DOS3+.\r\nKeep WZV4/WZM3/WZI1/WZG1 plus INST.REQ/GAIN.REQ together. No legacy fallback.\r\nThree constant Organ tones and one original fixed-noise drum voice; no soundtrack transcription.\r\nAttack velocity is preserved; verified cue-scoped gain is extra chip attenuation.\r\nAnnotations cover every master note. Discarded instances never resurrect.\r\nSame-channel/pitch collisions choose strongest attack, then latest onset; same-velocity handover retriggers.\r\nCropped held seeds begin a new attack at output zero; prior envelope age/phase is not encoded.\r\nCaptions and supplied speech use output-relative time zero.\r\nUse a controlled foreground DOS session without other sound/timer writers. Escape/Space stops.\r\n",Encoding.ASCII);
            if(qualificationRuntime!=null)File.AppendAllText(Path.Combine(staging,"README.TXT"),"UNQUALIFIED CANDIDATE: native integration test only; not a released player.\r\n",Encoding.ASCII);
            File.WriteAllText(Path.Combine(staging,"OWNERSHIP-REPORT.JSON"),JsonSerializer.Serialize(arranged.Report,new JsonSerializerOptions{WriteIndented=true}));
            var hashes=Directory.GetFiles(staging).ToDictionary(p=>Path.GetFileName(p)!,p=>System.Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p))));
            File.WriteAllText(Path.Combine(staging,"MANIFEST.JSON"),JsonSerializer.Serialize(new{contract="WZG1-v1",qualified=qualificationRuntime==null,duration_ms=movie.DurationMs,frames=movie.Frames,
                film_origin_ms=arranged.Report.FilmOriginMs,master_sha256=score.SourceSha256,gain_required=true,pit_required=false,speech_clips=clips.Count,caption_cues=cues.Count,files=hashes},new JsonSerializerOptions{WriteIndented=true}));
            ct.ThrowIfCancellationRequested();Directory.Move(staging,destination);
        }
        finally{if(Directory.Exists(staging))Directory.Delete(staging,true);}
    }
}
