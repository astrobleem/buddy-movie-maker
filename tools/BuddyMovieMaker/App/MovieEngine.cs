using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace BuddyMovieMaker;

public record SourceInfo(decimal DurationSeconds, bool HasAudio);
public record MovieInfo(int DurationMs, int Frames, bool HasAudio, decimal StartSeconds=0, decimal EndSeconds=0);
public record Cue(int Time, string Text);
public static class MovieEngine
{
    public const int Width = 256, Height = 160, Fps = 4, FrameBytes = Width * Height / 2;
    public static readonly byte[] Palette = [0,0,0, 0,0,170, 0,170,0, 0,170,170,
        170,0,0, 170,0,170, 170,85,0, 170,170,170, 85,85,85, 85,85,255,
        85,255,85, 85,255,255, 255,85,85, 255,85,255, 255,255,85, 255,255,255];
    public static string? DecoderDirectory { get; private set; }
    public static void SelectDecoder(string directory)
    {
        directory = Path.GetFullPath(directory);
        if (directory.StartsWith(@"\\") || !File.Exists(Path.Combine(directory,"ffmpeg.exe")) || !File.Exists(Path.Combine(directory,"ffprobe.exe")))
            throw new ArgumentException("Choose a local folder containing both ffmpeg.exe and ffprobe.exe.");
        DecoderDirectory = directory;
    }
    public static string Dependency(string file) => DecoderDirectory == null
        ? throw new InvalidOperationException("Choose an existing FFmpeg folder before converting. FFmpeg is supplied separately.")
        : Path.Combine(DecoderDirectory, file);
    public static async Task<string> CheckDecoder(string directory, CancellationToken ct)
    {
        string? previous=DecoderDirectory;
        SelectDecoder(directory);
        try
        {
        var lines = new List<string>();
        foreach (string file in new[] {"ffmpeg.exe", "ffprobe.exe"})
        {
            using var proc = Start(Dependency(file), ["-version"]);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeout.CancelAfter(TimeSpan.FromSeconds(10));
            using var registration = timeout.Token.Register(() => Kill(proc));
            var output = proc.StandardOutput.ReadToEndAsync(timeout.Token);
            var error = proc.StandardError.ReadToEndAsync(timeout.Token);
            await proc.WaitForExitAsync(timeout.Token);
            string text = await output;
            if (proc.ExitCode != 0 || !text.StartsWith(Path.GetFileNameWithoutExtension(file)+" version "))
                throw new InvalidDataException("Selected decoder could not identify itself as FFmpeg/ffprobe.");
            lines.Add(text.Split('\n')[0].Trim()); await error;
        }
        return string.Join("; ",lines);
        }
        catch(OperationCanceledException) when (!ct.IsCancellationRequested)
        { DecoderDirectory=previous; throw new InvalidDataException("Decoder verification timed out after 10 seconds."); }
        catch { DecoderDirectory=previous; throw; }
    }
    public static Process Start(string executable, IEnumerable<string> args)
    {
        if (!File.Exists(executable)) throw new InvalidOperationException($"Selected decoder is missing: {Path.GetFileName(executable)}");
        var info = new ProcessStartInfo(executable) { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var arg in args) info.ArgumentList.Add(arg);
        return Process.Start(info) ?? throw new IOException("Could not start media decoder.");
    }
    public static void RequireLocal(string source)
    {
        if (string.IsNullOrWhiteSpace(source) || !Path.IsPathFullyQualified(source) || !File.Exists(source))
            throw new ArgumentException("Choose an existing local file.");
        if (source.StartsWith(@"\\")) throw new ArgumentException("Copy network media to a local folder first.");
    }
    public static async Task<MovieInfo> Probe(string source, CancellationToken ct)
        => Select(await ProbeSource(source,ct));
    public static async Task<SourceInfo> ProbeSource(string source, CancellationToken ct)
    {
        RequireLocal(source);
        using var proc = Start(Dependency("ffprobe.exe"), ["-v", "error", "-protocol_whitelist", "file,pipe", "-show_streams", "-show_format", "-of", "json", source]);
        using var registration = ct.Register(() => Kill(proc));
        var stdout = proc.StandardOutput.ReadToEndAsync(ct); var stderr = proc.StandardError.ReadToEndAsync(ct);
        await proc.WaitForExitAsync(ct);
        var error = await stderr;
        if (proc.ExitCode != 0) throw new InvalidDataException("Media could not be opened: " + Limit(error));
        return ParseSource(await stdout);
    }
    internal static MovieInfo ParseProbe(string metadata)
        => Select(ParseSource(metadata));
    internal static SourceInfo ParseSource(string metadata)
    {
        using var data = JsonDocument.Parse(metadata);
        var streams = data.RootElement.GetProperty("streams").EnumerateArray().ToArray();
        var video = streams.FirstOrDefault(s => s.GetProperty("codec_type").GetString() == "video");
        if (video.ValueKind == JsonValueKind.Undefined) throw new InvalidDataException("This file has no video stream.");
        // Use the selected video stream, not a longer soundtrack/container duration.
        string? seconds = video.TryGetProperty("duration", out var d) ? d.GetString() : null;
        if (seconds == null && data.RootElement.TryGetProperty("format", out var f) && f.TryGetProperty("duration", out d)) seconds = d.GetString();
        if (!decimal.TryParse(seconds, NumberStyles.Float, CultureInfo.InvariantCulture, out var value))
            throw new InvalidDataException("Video duration is unknown or invalid in the media metadata. Choose a local video with a readable, finite duration.");
        if (value <= 0)
            throw new InvalidDataException($"Video duration must be greater than zero; the media metadata reports {value.ToString(CultureInfo.InvariantCulture)} seconds.");
        return new(value,streams.Any(s => s.GetProperty("codec_type").GetString() == "audio"));
    }
    public static decimal? ParseTime(string text, bool optional=false)
    {
        if(optional && string.IsNullOrWhiteSpace(text))return null;
        if(!decimal.TryParse(text.Trim(),NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out var value) || value<0)
            throw new ArgumentException("Start/end must be nonnegative seconds using a decimal point, for example 12.5. Leave end blank for the end of the video.");
        return value;
    }
    public static MovieInfo Select(SourceInfo source, decimal start=0, decimal? end=null)
    {
        decimal stop=end??source.DurationSeconds;
        if(start<0 || stop>source.DurationSeconds || start>=source.DurationSeconds || stop<=start)
            throw new InvalidDataException($"Choose 0 <= start < end <= source duration ({source.DurationSeconds.ToString(CultureInfo.InvariantCulture)} seconds).");
        decimal value=stop-start;
        if (value > 600)
        {
            string exact=value.ToString(CultureInfo.InvariantCulture), measured=exact+" seconds";
            if(value<86400){int totalMs=(int)Math.Round(value*1000,MidpointRounding.AwayFromZero);measured=string.Format(CultureInfo.InvariantCulture,"{0:00}:{1:00.000}",totalMs/60000,(totalMs%60000)/1000.0);}
            throw new InvalidDataException($"Video selection duration is {measured} ({exact} seconds). Maker's maximum is 10:00.000 (600 seconds). Choose a shorter start/end selection.");
        }
        int ms = checked((int)Math.Round(value * 1000));
        if (ms <= 0) throw new InvalidDataException("Video is too short.");
        return new(ms, (ms + 249) / 250, source.HasAudio,start,stop);
    }
    public static byte[] Quantize(ReadOnlySpan<byte> rgb)
    {
        if (rgb.Length != Width * Height * 3) throw new InvalidDataException("Incomplete decoded frame.");
        var packed = new byte[FrameBytes];
        for (int pixel = 0; pixel < Width * Height; pixel++)
        {
            int best = 0, distance = int.MaxValue, p = pixel * 3;
            for (int c = 0; c < 16; c++)
            {
                int r = rgb[p] - Palette[c*3], g = rgb[p+1] - Palette[c*3+1], b = rgb[p+2] - Palette[c*3+2];
                int candidate = r*r + g*g + b*b;
                if (candidate < distance) { best = c; distance = candidate; }
            }
            packed[pixel / 2] |= (byte)(best << ((pixel % 2 == 0) ? 4 : 0));
        }
        return packed;
    }
    public static byte[] Unpack(byte[] packed)
    {
        if (packed.Length != FrameBytes) throw new InvalidDataException("Invalid preview frame.");
        var rgb = new byte[Width * Height * 3];
        for (int i = 0; i < Width * Height; i++)
        {
            int c = ((i % 2 == 0) ? packed[i/2] >> 4 : packed[i/2] & 15) * 3;
            Array.Copy(Palette, c, rgb, i*3, 3);
        }
        return rgb;
    }
    public static List<Cue> Captions(string? path, int duration)
    {
        var cues = new List<Cue>();
        if (string.IsNullOrWhiteSpace(path)) return cues;
        RequireLocal(path);
        if (new FileInfo(path).Length > 24000) throw new InvalidDataException("Caption file is too large (maximum 256 cues).");
        int lineNumber = 0;
        foreach (string line in File.ReadLines(path, Encoding.UTF8))
        {
            lineNumber++;
            if (line.Length == 0 || line.StartsWith('#')) continue;
            int separator = line.IndexOf('|');
            if (separator < 1 || !int.TryParse(line.AsSpan(0, separator), NumberStyles.None, CultureInfo.InvariantCulture, out int time))
                throw new InvalidDataException($"Caption line {lineNumber}: use milliseconds|text.");
            string text = line[(separator + 1)..].ToUpperInvariant();
            if (time < 0 || time > duration || (cues.Count > 0 && time <= cues[^1].Time) || cues.Count >= 256 || text.Length > 52 || text.Any(c => c < 32 || c > 90))
                throw new InvalidDataException($"Caption line {lineNumber}: times must increase and fit the video; maximum 52 characters, ASCII space through Z (lowercase accepted).");
            cues.Add(new(time, text));
        }
        return cues;
    }
    public static async Task Convert(string source, string destination, MovieInfo movie, CancellationToken ct, IProgress<double>? progress = null)
    {
        if(movie.DurationMs<=0 || movie.DurationMs>600000 || movie.Frames!=(movie.DurationMs+249)/250 || movie.StartSeconds<0 || (movie.EndSeconds==0 && movie.StartSeconds!=0) || (movie.EndSeconds!=0 && (movie.EndSeconds<=movie.StartSeconds || movie.EndSeconds-movie.StartSeconds>600 || Math.Round((movie.EndSeconds-movie.StartSeconds)*1000)!=movie.DurationMs)))throw new InvalidDataException("Invalid bounded movie profile.");
        var args=new List<string>{"-nostdin", "-hide_banner", "-loglevel", "error", "-protocol_whitelist", "file,pipe"};
        bool trimmed=movie.StartSeconds!=0;
        if(trimmed)args.AddRange(["-ss",movie.StartSeconds.ToString(CultureInfo.InvariantCulture)]);
        args.AddRange(["-i",source]);
        if(movie.EndSeconds>0)args.AddRange(["-t",(movie.EndSeconds-movie.StartSeconds).ToString(CultureInfo.InvariantCulture)]);
        args.AddRange(["-map", "0:v:0", "-vf", (trimmed?"setpts=PTS-STARTPTS,":"")+"fps=4,scale=256:160:flags=area", "-an", "-sn", "-dn", "-pix_fmt", "rgb24", "-f", "rawvideo", "pipe:1"]);
        using var decoder = Start(Dependency("ffmpeg.exe"), args);
        using var registration = ct.Register(() => Kill(decoder));
        var errors = decoder.StandardError.ReadToEndAsync(ct);
        using var file = new FileStream(destination, FileMode.CreateNew, FileAccess.Write);
        using var writer = new BinaryWriter(file);
        writer.Write(Encoding.ASCII.GetBytes("WZV2")); writer.Write((ushort)Width); writer.Write((ushort)Height); writer.Write((ushort)Fps);
        writer.Write((ushort)24); writer.Write(movie.Frames); writer.Write(movie.DurationMs); writer.Write(FrameBytes);
        byte[] raw = new byte[Width * Height * 3]; byte[]? last = null; int count = 0;
        try
        {
            while (true)
            {
                int got = 0;
                while (got < raw.Length)
                {
                    int n = await decoder.StandardOutput.BaseStream.ReadAsync(raw.AsMemory(got), ct);
                    if (n == 0) break;
                    got += n;
                }
                if (got == 0) break;
                if (got != raw.Length) throw new InvalidDataException("Decoder returned an incomplete frame.");
                if (count > movie.Frames + 2) throw new InvalidDataException("Decoded video does not match its stated duration.");
                if (count < movie.Frames) { last = Quantize(raw); writer.Write(last); }
                count++; progress?.Report(Math.Min(1, (double)count/movie.Frames)); ct.ThrowIfCancellationRequested();
            }
            await decoder.WaitForExitAsync(ct);
            if (decoder.ExitCode != 0) throw new InvalidDataException("Video decoding failed: " + Limit(await errors));
            if (last == null || count < movie.Frames - 2 || count > movie.Frames + 2) throw new InvalidDataException("Decoded video does not match its stated duration.");
            while (count++ < movie.Frames) writer.Write(last);
        }
        finally { Kill(decoder); }
    }
    public static async Task Export(string video, string? midi, string? captions, string destination, CancellationToken ct, IProgress<double>? progress = null, IEnumerable<SpeechRequest>? speech = null, string? mml=null,int initialProgram=0,bool vibrato=true,decimal startSeconds=0,decimal? endSeconds=null)
    {
        destination = Path.GetFullPath(destination);
        if (Directory.Exists(destination) || File.Exists(destination)) throw new IOException("Choose a new folder. Existing destinations are never overwritten.");
        var info = Select(await ProbeSource(video, ct),startSeconds,endSeconds);
        var cues = Captions(captions, info.DurationMs);
        if(!string.IsNullOrWhiteSpace(midi)&&!string.IsNullOrWhiteSpace(mml))throw new InvalidDataException("Choose MIDI or MML as the music source, not both.");
        var expressive=string.IsNullOrWhiteSpace(mml)?null:MmlScore.FromFile(mml,info.DurationMs,initialProgram,vibrato);
        byte[]? music = expressive?.Music??(string.IsNullOrWhiteSpace(midi) ? null : MidiScore.Convert(midi, info.DurationMs));
        var clips=await SpeechAudio.Prepare(speech,info.DurationMs,music,ct);
        string runtime = Path.Combine(AppContext.BaseDirectory, "runtime", "MOVPLAY.EXE");
        if (!File.Exists(runtime)) throw new IOException("Packaged DOS player is missing.");
        string parent = Path.GetDirectoryName(destination) ?? throw new IOException("Choose a destination folder.");
        Directory.CreateDirectory(parent);
        string staging = Path.Combine(parent, ".buddy-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(staging);
        try
        {
            await Convert(video, Path.Combine(staging, "MOVIE.WZV"), info, ct, progress);
            File.Copy(runtime, Path.Combine(staging, "MOVPLAY.EXE"));
            if (music != null) File.WriteAllBytes(Path.Combine(staging, "MOVIE.WZM"), music);
            if(expressive!=null){File.WriteAllBytes(Path.Combine(staging,"MOVIE.WZI"),expressive.Instruments);File.WriteAllBytes(Path.Combine(staging,"INST.REQ"),Encoding.ASCII.GetBytes("WZI1"));}
            SpeechAudio.Write(Path.Combine(staging,"SPEECH.PCM"),clips);
            File.WriteAllLines(Path.Combine(staging, "MOVIE.LRC"), cues.Select(c => $"{c.Time}|{c.Text}"), Encoding.ASCII);
            using (var writer = new BinaryWriter(File.Create(Path.Combine(staging, "MOVIE.CUE"))))
            { writer.Write(Encoding.ASCII.GetBytes("WZC1")); writer.Write(info.DurationMs); writer.Write(0); writer.Write(info.DurationMs); }
            File.WriteAllText(Path.Combine(staging, "PLAY.BAT"), "@echo off\r\nMOVPLAY\r\n", Encoding.ASCII);
            File.WriteAllText(Path.Combine(staging, "README.TXT"), "Buddy Movie Maker export\r\nCopy this entire folder to a Tandy 1000 running DOS 3+; exit Windows and run PLAY.\r\nEscape or Space stops; run PLAY again to restart.\r\n256x160, 4 fps, standard RGBI. Movie soundtrack is not exported.\r\n" + (expressive != null ? "MML"+expressive.Version+" score: WININST12 tones and fixed noise; keep MOVIE.WZI and INST.REQ beside the player.\r\n" : music != null ? "MIDI arrangement: three melodic PSG voices; percussion omitted.\r\n" : "No PSG music.\r\n") + (clips.Count > 0 ? "Timed PC-speaker speech: video holds and catches up; PSG rests during clips.\r\n" : "No digital speech.\r\n"), Encoding.ASCII);
            File.AppendAllText(Path.Combine(staging,"README.TXT"),$"Source selection: {info.StartSeconds.ToString(CultureInfo.InvariantCulture)} to {info.EndSeconds.ToString(CultureInfo.InvariantCulture)} seconds.\r\nAll music, captions and speech use output movie-relative time zero. Separate tracks are not shifted or cropped from source time.\r\n",Encoding.ASCII);
            var hashes = Directory.GetFiles(staging).ToDictionary(p => Path.GetFileName(p)!, p => System.Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p))));
            File.WriteAllText(Path.Combine(staging, "MANIFEST.JSON"), JsonSerializer.Serialize(new { version = 1, profile = "256x160@4", duration_ms = info.DurationMs,
                source_start_seconds=info.StartSeconds,source_end_seconds=info.EndSeconds,sidecar_time_origin="output movie zero; no source-time shifting",
                frames = info.Frames, palette = "IBM/Tandy RGBI", quantizer = "nearest squared RGB; first index wins ties; no dithering", soundtrack = "omitted",
                music_source=expressive!=null?"MML"+expressive.Version+" WININST12 expressive":music!=null?"MIDI legacy":"none", speech_clips=clips.Count,speech_samples=clips.Sum(c=>c.Samples.Length),speech_policy="PSG rests with 150ms guards; video holds/catches up; movie clock continues", caption_cues = cues.Count, files = hashes }, new JsonSerializerOptions { WriteIndented = true }));
            ct.ThrowIfCancellationRequested();
            Directory.Move(staging, destination); // Atomic publication on same volume; refuses destination races.
        }
        finally { if (Directory.Exists(staging)) Directory.Delete(staging, true); }
    }
    static string Limit(string text) => text.Length > 1600 ? text[..1600] : text;
    static void Kill(Process process) { try { if (!process.HasExited) process.Kill(true); } catch (InvalidOperationException) { } }
}
