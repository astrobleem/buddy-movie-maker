using System.Text;

namespace BuddyMoviePlayer;

public record Score(int Time, byte[] Notes, byte[] Velocities, byte Retrigger);
public record Instrument(int Time, byte[] Programs);
public record Speech(int Start, int End, byte[] Samples);
public record PitNote(int Time, byte Note, bool Attack);
public record Gain(int Time, byte[] Steps);

public sealed class Movie : IDisposable
{
    public FileStream? Video { get; private set; }
    public bool HasVideo => Video != null;
    public bool RequiresPit { get; private set; }
    public bool RequiresGain { get; private set; }
    public int Width, Height, Fps, Frames, Duration, FrameBytes;
    public readonly List<Score> Scores = [];
    public readonly List<Instrument> Instruments = [];
    public readonly List<Speech> Speeches = [];
    public readonly List<PitNote> PitNotes = [];
    public readonly List<Gain> Gains = [];
    public readonly List<(int Time, string Text)> Captions = [];
    public bool Vibrato;

    static void Require(bool ok, string message)
    {
        if (!ok) throw new InvalidDataException(message);
    }
    static int U16(byte[] b, int p) => BitConverter.ToUInt16(b, p);
    static int I32(byte[] b, int p) => BitConverter.ToInt32(b, p);
    static bool Magic(byte[] b, string s) => b.Length >= 4 && Encoding.ASCII.GetString(b, 0, 4) == s;
    static byte[] Read(string path, int max)
    {
        Require(new FileInfo(path).Length <= max, $"{Path.GetFileName(path)} exceeds format limits.");
        return File.ReadAllBytes(path);
    }

    public Movie(string path, bool pitEnabled = false, bool pitCapability = true, bool audioOnly = false)
    {
        path = Path.GetFullPath(path);
        string folder = Path.GetDirectoryName(path)!;
        string basename = Path.GetFileNameWithoutExtension(path);
        string stem = Path.Combine(folder, basename);
        string Side(string ext) => stem + ext;
        string pitMarker = Path.Combine(folder, "PIT.REQ");
        byte[]? music = null;
        try
        {
            if (audioOnly)
            {
                music = Read(path, 140020);
                Require(music.Length >= 20 && (Magic(music, "WZM1") || Magic(music, "WZM2") || Magic(music,"WZM3")), "Unsupported WZM header.");
                RequiresPit = Magic(music, "WZM2");
                RequiresGain = Magic(music,"WZM3");
                Duration = I32(music, 12);
                Require(Duration > 0 && Duration <= 600000, "Invalid music duration.");
                if (File.Exists(Side(".WZV"))) LoadVideo(Side(".WZV"), true);
            }
            else LoadVideo(path, false);

            string gainMarker=Path.Combine(folder,"GAIN.REQ");
            if(RequiresGain)
            {
                Require(File.Exists(Side(".WZM"))&&File.Exists(Side(".WZI"))&&File.Exists(Side(".WZG")),"Gain family requires matching WZM3, WZI1 and WZG1; video-only fallback is forbidden.");
                Require(File.Exists(gainMarker)&&Read(gainMarker,4).SequenceEqual(Encoding.ASCII.GetBytes("WZG1")),"Gain family requires exact GAIN.REQ=WZG1.");
                Require(File.Exists(Path.Combine(folder,"INST.REQ")),"Gain family requires INST.REQ.");
            }
            else Require(!File.Exists(gainMarker)&&!File.Exists(Side(".WZG")),"Old families cannot contain gain artifacts.");
            if (music != null || File.Exists(Side(".WZM")))
                LoadMusic(music ?? Read(Side(".WZM"), 140020));
            LoadInstruments(Side(".WZI"), Path.Combine(folder, "INST.REQ"));
            if (RequiresPit) {
                Require(File.Exists(pitMarker)&&Read(pitMarker,4).SequenceEqual(Encoding.ASCII.GetBytes("WZP1")),"PIT-required movie needs exact PIT.REQ=WZP1.");
                Require(File.Exists(Side(".WZM"))&&File.Exists(Side(".WZP")),"PIT-required movie needs matching music and WZP1 files.");
                LoadPit(Read(Side(".WZP"), 80016));
            }
            else Require(!File.Exists(pitMarker)&&!File.Exists(Side(".WZP")),"PIT artifacts are present without a required PIT declaration.");
            ValidateDirectory(folder, basename);
            if(RequiresGain)LoadGain(Read(Side(".WZG"),80020));
            if (File.Exists(Side(".CUE")))
            {
                byte[] b = Read(Side(".CUE"), 16);
                Require(b.Length == 16 && Magic(b, "WZC1") && I32(b, 4) == Duration && I32(b, 8) >= 0 && I32(b, 8) < I32(b, 12) && I32(b, 12) <= Duration, "Invalid CUE sidecar.");
            }
            if (File.Exists(Side(".LRC"))) LoadCaptions(Read(Side(".LRC"), 20000));
            string speech = Path.Combine(folder, "SPEECH.PCM");
            if (File.Exists(speech)) LoadSpeech(Read(speech, 360200));
            ValidateSpeechGuards();
            Require(!RequiresPit || pitEnabled, "This bundle requires PIT voice. Enable PIT voice before opening it.");
            Require(!RequiresPit || pitCapability, "PIT playback capability is unavailable; required voice cannot be omitted.");
        }
        catch { Video?.Dispose(); throw; }
    }

    void LoadVideo(string path, bool matchMusic)
    {
        Video = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        byte[] h = new byte[24];
        Video.ReadExactly(h);
        bool videoPit = Magic(h, "WZV3");
        bool videoGain=Magic(h,"WZV4");
        Require(Magic(h, "WZV2") || videoPit || videoGain, "Unsupported WZV header. Expected WZV2, WZV3 or gain-required WZV4.");
        Require(!matchMusic || (videoPit == RequiresPit && videoGain==RequiresGain && I32(h, 16) == Duration), "Video/music versions or durations do not match.");
        RequiresPit = videoPit;
        RequiresGain = videoGain;
        Width = U16(h, 4); Height = U16(h, 6); Fps = U16(h, 8);
        Frames = I32(h, 12); Duration = I32(h, 16); FrameBytes = Width * Height / 2;
        Require(U16(h, 10) == 24 && Width >= 4 && Width <= 320 && Width % 4 == 0 && Height >= 1 && Height <= 200 && Fps is 2 or 4 or 8 && I32(h, 20) == FrameBytes, "Invalid WZV video header.");
        Require(Frames > 0 && Frames <= 4800 && Duration > 0 && Duration <= 600000 && Duration <= Frames * (1000 / Fps) && Duration > (Frames - 1) * (1000 / Fps), "Invalid frame count or duration.");
        Require(Video.Length == checked(24L + (long)Frames * FrameBytes), "Truncated video or unexpected trailing bytes.");
    }

    void ValidateDirectory(string folder, string basename)
    {
        string[] files = Directory.GetFiles(folder);
        if (RequiresPit || RequiresGain)
        {
            Require(!files.GroupBy(Path.GetFileName, StringComparer.OrdinalIgnoreCase).Any(g => g.Count() > 1), "Duplicate case-insensitive bundle files.");
            foreach (string file in files.Where(f => Path.GetExtension(f).Equals(".REQ", StringComparison.OrdinalIgnoreCase)))
                Require(Path.GetFileName(file).Equals("PIT.REQ", StringComparison.OrdinalIgnoreCase) || Path.GetFileName(file).Equals("INST.REQ", StringComparison.OrdinalIgnoreCase) || (RequiresGain&&Path.GetFileName(file).Equals("GAIN.REQ",StringComparison.OrdinalIgnoreCase)), "Unknown required marker: " + Path.GetFileName(file));
        }
        foreach (string file in files)
        {
            string ext = Path.GetExtension(file).ToUpperInvariant();
            if (!ext.StartsWith(".WZ")) continue;
            bool matching = Path.GetFileNameWithoutExtension(file).Equals(basename, StringComparison.OrdinalIgnoreCase);
            if (RequiresPit || RequiresGain) Require(matching, "Required-feature directory must contain one matching bundle basename.");
            if (matching) Require(ext is ".WZV" or ".WZM" or ".WZI" || (RequiresPit && ext == ".WZP") || (RequiresGain&&ext==".WZG"), "Unsupported sidecar: " + Path.GetFileName(file));
        }
    }

    void LoadMusic(byte[] b)
    {
        Require(b.Length >= 20 && Magic(b, RequiresGain?"WZM3":RequiresPit ? "WZM2" : "WZM1") && U16(b, 4) == 20 && U16(b, 6) == 14 && I32(b, 12) == Duration && I32(b, 16) == 0, "Invalid, mixed-version or mismatched WZM header.");
        int n = I32(b, 8);
        Require(n >= (RequiresPit || RequiresGain ? 2 : 1) && n <= 10000 && b.Length == checked(20 + n * 14), "Invalid WZM length/count.");
        int previous = -1;
        for (int p = 20; p < b.Length; p += 14)
        {
            int time = I32(b, p);
            Require(time > previous && time <= Duration && (!(RequiresPit||RequiresGain) || p != 20 || time == 0) && (b[p + 12] & 240) == 0 && b[p + 13] == 0, "Invalid WZM time or flags.");
            byte[] notes = b[(p + 4)..(p + 8)], velocities = b[(p + 8)..(p + 12)];
            for (int i = 0; i < 4; i++)
                Require(velocities[i] <= 127 && ((notes[i] == 0 && velocities[i] == 0) || (velocities[i] > 0 && notes[i] >= (i == 3 ? 35 : 45) && notes[i] <= (i == 3 ? 81 : 96))), "Invalid WZM note/velocity.");
            Scores.Add(new(time, notes, velocities, b[p + 12])); previous = time;
        }
        Require(!(RequiresPit||RequiresGain) || (previous == Duration && b.AsSpan(b.Length - 10).IndexOfAnyExcept((byte)0) < 0), "Required-feature music must end at duration with an all-zero final state.");
    }

    void LoadInstruments(string path, string marker)
    {
        if (File.Exists(marker)) Require(Read(marker, 4).SequenceEqual(Encoding.ASCII.GetBytes("WZI1")) && File.Exists(path), "INST.REQ requires a valid WZI1 sidecar.");
        if (!File.Exists(path)) return;
        Require(Scores.Count > 0, "WZI requires WZM music."); byte[] b = Read(path, 80020);
        Require(b.Length >= 20 && Magic(b, "WZI1") && U16(b, 4) == 20 && U16(b, 6) == 8 && I32(b, 12) == Duration && (U16(b, 16) & (RequiresGain?65528:65534)) == 0 && U16(b, 18) == 0x102, "Unsupported WZI version, flags or duration.");
        if(RequiresGain){Require((U16(b,16)&2)!=0,"Gain family requires WZI gain flag 0x0002.");RequiresPit=(U16(b,16)&4)!=0;}
        int n = I32(b, 8);
        Require(n > 0 && n <= 10000 && b.Length == checked(20 + n * 8), "Invalid WZI length.");
        Vibrato = (U16(b, 16) & 1) != 0; int previous = -1;
        for (int p = 20; p < b.Length; p += 8)
        {
            int time = I32(b, p);
            Require(time > previous && time <= Duration && (p != 20 || time == 0) && b[p + 7] == 0, "Invalid WZI event.");
            byte[] programs = b[(p + 4)..(p + 7)];
            Require(programs.All(x => x <= 112 && x % 16 == 0), "Unsupported WZI program.");
            Instruments.Add(new(time, programs)); previous = time;
        }
    }

    void LoadPit(byte[] b)
    {
        Require(b.Length >= 16 && Magic(b, "WZP1") && U16(b, 4) == 1 && U16(b, 6) == 0 && I32(b, 8) == Duration && U16(b, 14) == 0, "Invalid WZP1 header/version/duration.");
        int count = U16(b, 12);
        Require(count >= 2 && count <= 10000 && b.Length == checked(16 + count * 8), "Invalid WZP1 count or length.");
        int previous = -1;
        for (int p = 16; p < b.Length; p += 8)
        {
            int time = I32(b, p); byte note = b[p + 4], flags = b[p + 5];
            Require(time > previous && time <= Duration && (p != 16 || time == 0) && (note == 0 || note is >= 45 and <= 96) && flags <= 1 && (note != 0 || flags == 0) && U16(b, p + 6) == 0, "Invalid WZP1 state/time/note/flags.");
            PitNotes.Add(new(time, note, flags == 1)); previous = time;
        }
        Require(previous == Duration && PitNotes[^1].Note == 0 && !PitNotes[^1].Attack, "WZP1 requires final off at duration.");
    }

    void LoadGain(byte[] b)
    {
        Require(b.Length>=20&&Magic(b,"WZG1")&&U16(b,4)==20&&U16(b,6)==8&&I32(b,12)==Duration&&I32(b,16)==0,"Invalid WZG1 header/duration/reserved field.");
        int count=I32(b,8);Require(count>=2&&count<=10000&&b.Length==checked(20+count*8),"Invalid WZG1 count/length.");
        int previous=-1;
        for(int p=20;p<b.Length;p+=8){int time=I32(b,p);byte[] steps=b[(p+4)..(p+8)];Require(time>previous&&time<=Duration&&(p!=20||time==0)&&steps.All(x=>x<=15),"Invalid WZG1 time or attenuation.");Gains.Add(new(time,steps));previous=time;}
        Require(previous==Duration&&Gains[^1].Steps.All(x=>x==15),"WZG1 must end at duration with all lanes muted.");
    }

    void LoadCaptions(byte[] b)
    {
        Require(b.All(x => x <= 127), "Captions must be ASCII."); int previous = -1;
        foreach (string raw in Encoding.ASCII.GetString(b).Split('\n'))
        {
            string line = raw.TrimEnd('\r'); if (line.Length == 0 || line.StartsWith('#')) continue;
            int p = line.IndexOf('|'); Require(p > 0 && int.TryParse(line[..p], out _), "Invalid caption time.");
            int time = int.Parse(line[..p]); string text = line[(p + 1)..];
            Require(time > previous && time <= Duration && text.Length <= 52 && text.All(c => c >= 32 && c <= 126) && Captions.Count < 256, "Invalid caption cue.");
            Captions.Add((time, new string(text.ToUpperInvariant().Select(c => c > 90 ? '?' : c).ToArray()))); previous = time;
        }
    }

    void LoadSpeech(byte[] b)
    {
        Require(b.Length >= 8 && Magic(b, "SPC1") && U16(b, 6) == 0 && U16(b, 4) > 0 && U16(b, 4) <= 16, "Unsupported speech header.");
        int p = 8, previous = -150, total = 0;
        for (int i = 0; i < U16(b, 4); i++)
        {
            Require(p + 12 <= b.Length, "Truncated speech.");
            int start = I32(b, p), end = I32(b, p + 4), length = U16(b, p + 8);
            Require(U16(b, p + 10) == 0 && start >= previous + 150 && start < end && end <= Duration && length > 0 && length <= 48000 && (long)(end - start) * 6 == length && p + 12 + length <= b.Length, "Invalid speech window.");
            p += 12; byte[] samples = b[p..(p + length)];
            Require(samples.All(x => x >= 1 && x <= 72), "Invalid speech PWM sample.");
            Speeches.Add(new(start, end, samples)); p += length; total += length; previous = end;
        }
        Require(p == b.Length && total <= 360000, "Speech trailing data or oversized stream.");
    }

    void ValidateSpeechGuards()
    {
        foreach (Speech speech in Speeches)
        {
            Score? state = Scores.LastOrDefault(x => x.Time <= speech.Start);
            Require(state == null || state.Notes.All(x => x == 0), "Speech overlaps active music; unsupported combination.");
            Require(!Scores.Any(x => x.Time > speech.Start && x.Time < speech.End + 80 && x.Notes.Any(n => n != 0)), "Speech overlaps imminent music; unsupported combination.");
            int lower = Math.Max(0, speech.Start - 150), upper = Math.Min(Duration, speech.End + 150);
            for (int i = 0; i + 1 < PitNotes.Count; i++)
                Require(PitNotes[i].Note == 0 || PitNotes[i].Time >= upper || PitNotes[i + 1].Time <= lower, "PIT note overlaps the 150 ms speech guard.");
        }
    }

    public byte[] Frame(int ms)
    {
        if (Video == null) throw new InvalidOperationException("Audio-only score has no video frames.");
        var data = new byte[FrameBytes];
        Video.Position = 24L + Math.Min(Frames - 1, ms * Fps / 1000) * (long)FrameBytes;
        Video.ReadExactly(data); return data;
    }
    public string Caption(int ms) => Captions.LastOrDefault(x => x.Time <= ms).Text ?? "";
    public void Dispose() => Video?.Dispose();
}
