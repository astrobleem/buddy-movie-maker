using System.Globalization;
using System.IO;
using System.Text;
using System.Text.Json;

namespace BuddyMovieMaker;
public sealed class SpeechRequest(string path,int startMs)
{
    public string Path {get;}=path;
    public string FileName=>System.IO.Path.GetFileName(Path);
    public int StartMs {get;set;}=startMs;
}
public record SpeechClip(int StartMs,int EndMs,byte[] Samples);
public static class SpeechAudio
{
    public const int MaxClips=16,MaxClipMs=8000,MaxSamples=360000,GuardMs=150;
    public static async Task<List<SpeechClip>> Prepare(IEnumerable<SpeechRequest>? requests,int movieMs,byte[]? music,CancellationToken ct,byte[]? pit=null)
    {
        var inputs=requests?.OrderBy(r=>r.StartMs).ToArray()??[];
        if(inputs.Length>MaxClips)throw new InvalidDataException("Maximum 16 speech clips.");
        var clips=new List<SpeechClip>();int total=0;
        foreach(var request in inputs)
        {
            MovieEngine.RequireLocal(request.Path);
            if(new FileInfo(request.Path).Length>64*1024*1024)throw new InvalidDataException("Speech input exceeds 64 MiB.");
            using var probe=MovieEngine.Start(MovieEngine.Dependency("ffprobe.exe"),["-v","error","-protocol_whitelist","file,pipe","-show_streams","-show_format","-of","json",request.Path]);
            using var registration=ct.Register(()=>Kill(probe));
            var json=probe.StandardOutput.ReadToEndAsync(ct);var errors=probe.StandardError.ReadToEndAsync(ct);
            await probe.WaitForExitAsync(ct);
            if(probe.ExitCode!=0)throw new InvalidDataException("Could not read speech clip: "+await errors);
            using var metadata=JsonDocument.Parse(await json);
            var audio=metadata.RootElement.GetProperty("streams").EnumerateArray().FirstOrDefault(s=>s.GetProperty("codec_type").GetString()=="audio");
            if(audio.ValueKind==JsonValueKind.Undefined)throw new InvalidDataException("Speech clip has no audio stream.");
            string? seconds=audio.TryGetProperty("duration",out var d)?d.GetString():null;
            if(seconds==null && metadata.RootElement.TryGetProperty("format",out var format)&&format.TryGetProperty("duration",out d))seconds=d.GetString();
            if(!double.TryParse(seconds,NumberStyles.Float,CultureInfo.InvariantCulture,out double length)||!double.IsFinite(length)||length<=0||length>8.25)
                throw new InvalidDataException("Each speech clip needs a known duration greater than zero and at most 8 seconds. Trim longer audio first.");
            int start=request.StartMs;
            using var decoder=MovieEngine.Start(MovieEngine.Dependency("ffmpeg.exe"),["-nostdin","-v","error","-protocol_whitelist","file,pipe","-i",request.Path,"-map","0:a:0","-vn","-ac","1","-ar","6000","-af","highpass=f=150,lowpass=f=2700,aresample=6000","-f","u8","pipe:1"]);
            using var cancel=ct.Register(()=>Kill(decoder));var error=decoder.StandardError.ReadToEndAsync(ct);
            using var raw=new MemoryStream();byte[] buffer=new byte[4096];
            try
            {
                while(true){int n=await decoder.StandardOutput.BaseStream.ReadAsync(buffer,ct);if(n==0)break;raw.Write(buffer,0,n);if(raw.Length>MaxClipMs*6)throw new InvalidDataException("Decoded speech exceeds 8 seconds.");}
                await decoder.WaitForExitAsync(ct);
                if(decoder.ExitCode!=0)throw new InvalidDataException("Speech decoding failed: "+await error);
                if(raw.Length==0||Math.Abs(raw.Length-length*6000)>1500)throw new InvalidDataException("Speech samples disagree with declared duration by more than 250 ms.");
                int duration=(int)Math.Round(raw.Length/6.0,MidpointRounding.AwayFromZero);
                if(duration<1||start<0||start>movieMs-duration)throw new InvalidDataException("Speech clip must fit entirely inside the movie.");
                if(clips.Count>0 && start<clips[^1].EndMs+GuardMs)throw new InvalidDataException("Speech clips need a 150 ms gap and cannot overlap.");
                total+=duration*6;if(total>MaxSamples)throw new InvalidDataException("Total speech exceeds 60 seconds / 360,000 samples.");
                ValidateMusicWindow(music,start,start+duration,movieMs);
                ValidatePitWindow(pit,start,start+duration,movieMs);
                byte[] decoded=raw.ToArray(),pwm=new byte[duration*6];
                for(int i=0;i<pwm.Length;i++)pwm[i]=(byte)(1+Math.Round((i<decoded.Length?decoded[i]:128)*71.0/255,MidpointRounding.ToEven));
                clips.Add(new(start,start+duration,pwm));
            }
            finally{Kill(decoder);}
        }
        return clips;
    }
    public static void ValidateMusicWindow(byte[]? music,int start,int end,int duration)
    {
        if(music==null)return;
        if(music.Length<20 || (music.Length-20)%14!=0)throw new InvalidDataException("Invalid music score for speech scheduling.");
        int low=Math.Max(0,start-GuardMs),high=Math.Min(duration,end+GuardMs);
        byte[] state=new byte[4];
        for(int p=20;p<music.Length;p+=14)
        {
            int time=BitConverter.ToInt32(music,p);
            if(time<=low)Array.Copy(music,p+4,state,0,4);
            else if(time<high && music.AsSpan(p+4,4).IndexOfAnyExcept((byte)0)>=0)
                throw new InvalidDataException("Speech needs a PSG rest from 150 ms before to 150 ms after the clip. Insert a rest in the MIDI/MML score or move the clip.");
        }
        if(state.Any(n=>n!=0))throw new InvalidDataException("Speech starts during an active PSG note. Insert a rest or move the clip (150 ms guard).");
    }
    public static void ValidatePitWindow(byte[]? pit,int start,int end,int duration)
    {
        if(pit==null)return;
        if(pit.Length<32||Encoding.ASCII.GetString(pit,0,4)!="WZP1"||BitConverter.ToUInt16(pit,4)!=1||BitConverter.ToUInt16(pit,6)!=0||BitConverter.ToInt32(pit,8)!=duration||BitConverter.ToUInt16(pit,14)!=0||pit.Length!=16+8*BitConverter.ToUInt16(pit,12))throw new InvalidDataException("Invalid PIT score for speech scheduling.");
        int low=Math.Max(0,start-GuardMs),high=Math.Min(duration,end+GuardMs);byte held=0;
        for(int p=16;p<pit.Length;p+=8)
        {
            int time=BitConverter.ToInt32(pit,p);
            if(time<=low)held=pit[p+4];
            else if(time<high&&pit[p+4]!=0)throw new InvalidDataException("Speech needs a PIT rest from 150 ms before to 150 ms after the clip. Insert a rest in [P] or move the clip.");
        }
        if(held!=0)throw new InvalidDataException("Speech guard overlaps an active PIT note. Insert a rest in [P] or move the clip.");
    }
    public static void Write(string destination,IReadOnlyList<SpeechClip> clips)
    {
        if(clips.Count==0)return;
        using var writer=new BinaryWriter(new FileStream(destination,FileMode.CreateNew));
        writer.Write(Encoding.ASCII.GetBytes("SPC1"));writer.Write((ushort)clips.Count);writer.Write((ushort)0);
        foreach(var clip in clips){writer.Write(clip.StartMs);writer.Write(clip.EndMs);writer.Write((ushort)clip.Samples.Length);writer.Write((ushort)0);writer.Write(clip.Samples);}
    }
    static void Kill(System.Diagnostics.Process process){try{if(!process.HasExited)process.Kill(true);}catch(InvalidOperationException){}}
}
