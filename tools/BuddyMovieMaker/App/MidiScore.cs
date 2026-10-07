using System.IO;
using System.Text;

namespace BuddyMovieMaker;

public record MidiDrumReduction(int Note, int Hits, string Control, string Envelope);
public record MidiReductionReport(int ToneAttacks, int DrumAttacks, int ToneReductionStates,
    int DrumReductionStates, int SuppressedOrMergedDrumAttacks, int MaxTones, int MaxDrums, int IgnoredMessages, MidiDrumReduction[] Drums)
{
    public string Summary => $"MIDI: {ToneAttacks} tone / {DrumAttacks} drum attacks; {SuppressedOrMergedDrumAttacks} suppressed/merged hits, {ToneReductionStates} tone and {DrumReductionStates} noise arbitration states. See MIDI-REPORT.JSON.";
}
public record MidiArrangement(byte[] Music, byte[]? Instruments, MidiReductionReport Report);

// Standard MIDI format 0/1, PPQN. Deterministic bounded three-tone/one-noise arrangement.
// Voices keep assignments while sounding; highest velocities win excess polyphony.
public static partial class MidiScore
{
    record Event(long Tick, int Order, int Channel, int Note, int Velocity, int Tempo = 0, int Track = 0);
    public static byte[] Convert(string path, int duration) => Arrange(path,duration).Music;
    public static MidiArrangement Arrange(string path, int duration)
    {
        if(duration<1 || duration>600000)throw new InvalidDataException("MIDI output duration must be 1..600,000 ms.");
        var (events,division,ignored)=Parse(path);
        var unsupported=events.Where(e=>e.Channel==9&&e.Note>=0&&e.Velocity>0&&(e.Note<35||e.Note>81)).Select(e=>e.Note).Distinct().Order().ToArray();
        if(unsupported.Length!=0)throw new InvalidDataException("Unsupported GM percussion notes: "+string.Join(", ",unsupported)+". Supported keys are 35..81; no unknown drum is silently omitted.");
        events=events.OrderBy(e=>e.Tick).ThenBy(e=>e.Order).ToList();
        long lastTick=0;double microseconds=0;int currentTempo=500000;
        var timed=new SortedDictionary<int,List<Event>>();
        foreach(var ev in events)
        {
            microseconds+=(ev.Tick-lastTick)*(double)currentTempo/division;lastTick=ev.Tick;
            if(!double.IsFinite(microseconds) || microseconds/1000>duration+250) throw new InvalidDataException("MIDI timeline is longer than the video (250 ms tolerance). Trim it or choose a matching score.");
            int ms=Math.Min(duration,(int)Math.Round(microseconds/1000));
            if(ms>=duration&&ev.Channel>=0&&ev.Note>=0&&ev.Velocity>0)throw new InvalidDataException("A quantized MIDI note attack falls at or after movie end. Choose a matching score/selection; attacks are never silently discarded at the boundary.");
            if(ev.Tempo>0)currentTempo=ev.Tempo;
            else {if(!timed.TryGetValue(ms,out var list))timed[ms]=list=new();list.Add(ev);}
        }
        var active=new Dictionary<(int Track,int Channel,int Note),int>();
        var held=new HashSet<(int Track,int Channel,int Note)>();bool[] sustain=new bool[16];
        var voices=new (int Track,int Channel,int Note)?[3];
        int toneAttacks=0,drumAttacks=0,toneReductions=0,drumReductions=0,suppressedDrums=0,maxTones=0,maxDrums=0;
        var drumHits=new SortedDictionary<int,int>();
        var states=new SortedDictionary<int,byte[]>();states[0]=new byte[10];
        foreach(var (time,list) in timed)
        {
            foreach(var ev in list)
            {
                if(ev.Channel<0)continue;
                var key=(ev.Track,ev.Channel,ev.Note);
                if(ev.Note==-64)
                {
                    if(ev.Channel==9){ignored++;continue;}
                    sustain[ev.Channel]=ev.Velocity>=64;
                    if(!sustain[ev.Channel])foreach(var h in held.Where(h=>h.Channel==ev.Channel).ToArray()){active.Remove(h);held.Remove(h);}
                }
                else if(ev.Note is -120 or -123)
                {foreach(var h in active.Keys.Where(h=>h.Channel==ev.Channel).ToArray()){active.Remove(h);held.Remove(h);}}
                else if(ev.Velocity>0)
                {
                    if(ev.Channel!=9&&(ev.Note<45 || ev.Note>96))throw new InvalidDataException($"MIDI melodic note {ev.Note} is outside the supported PSG range 45..96. Transpose the score.");
                    if(ev.Channel==9){drumAttacks++;drumHits[ev.Note]=drumHits.GetValueOrDefault(ev.Note)+1;}else toneAttacks++;
                    active[key]=ev.Velocity;held.Remove(key);
                }
                else if(sustain[ev.Channel])held.Add(key);
                else {active.Remove(key);held.Remove(key);}
            }
            int tones=active.Count(k=>k.Key.Channel!=9),drums=active.Count(k=>k.Key.Channel==9);
            maxTones=Math.Max(maxTones,tones);maxDrums=Math.Max(maxDrums,drums);
            if(tones>3)toneReductions++;if(drums>1)drumReductions++;
            var selected=active.Where(k=>k.Key.Channel!=9).OrderByDescending(k=>k.Value).ThenBy(k=>k.Key.Channel).ThenBy(k=>k.Key.Note).ThenBy(k=>k.Key.Track).Take(3).Select(k=>k.Key).ToHashSet();
            for(int v=0;v<3;v++)if(voices[v] is {} key && !selected.Contains(key))voices[v]=null;
            foreach(var key in selected.OrderBy(k=>k.Channel).ThenBy(k=>k.Note).ThenBy(k=>k.Track))if(!voices.Contains(key))voices[Array.FindIndex(voices,v=>v==null)]=key;
            byte[] state=new byte[10];
            for(int v=0;v<3;v++)if(voices[v] is {} key){state[v]=(byte)key.Note;state[v+4]=(byte)active[key];}
            // Retrigger bit is set for a note-on on a currently selected voice.
            for(int v=0;v<3;v++)if(voices[v] is {} key && list.Any(e=>e.Track==key.Track && e.Channel==key.Channel && e.Note==key.Note && e.Velocity>0))state[8]|=(byte)(1<<v);
            var drum=active.Where(k=>k.Key.Channel==9).OrderByDescending(k=>k.Value).ThenBy(k=>DrumPriority(k.Key.Note)).ThenBy(k=>k.Key.Track).ThenBy(k=>k.Key.Note).Select(k=>((int Track,int Channel,int Note)?)k.Key).FirstOrDefault();
            if(drum is {} hit){state[3]=(byte)hit.Note;state[7]=(byte)active[hit];if(list.Any(e=>e.Track==hit.Track&&e.Channel==9&&e.Note==hit.Note&&e.Velocity>0))state[8]|=8;}
            suppressedDrums+=list.Count(e=>e.Channel==9&&e.Note>=0&&e.Velocity>0)-((state[8]&8)!=0?1:0);
            // One hardware noise voice. Suppressed hits are discarded, never queued
            // and resurrected as new rhythmic attacks after the winner ends.
            foreach(var lost in active.Keys.Where(k=>k.Channel==9&&(!drum.HasValue||k!=drum.Value)).ToArray())active.Remove(lost);
            states[time]=state;
        }
        states[duration]=new byte[10];
        if(states.Count>10000)throw new InvalidDataException("MIDI needs more than 10,000 PSG states.");
        using var output=new MemoryStream();using var writer=new BinaryWriter(output);
        writer.Write(Encoding.ASCII.GetBytes("WZM1"));writer.Write((ushort)20);writer.Write((ushort)14);writer.Write(states.Count);writer.Write(duration);writer.Write(0);
        foreach(var (time,state) in states){writer.Write(time);writer.Write(state);}
        byte[]? instruments=null;
        if(drumAttacks>0)
        {
            // Existing WZI1 engine: Organ keeps MIDI tones constant; original fixed-noise
            // Kick/Snare/Hat envelopes run on voice 3. No new formats or PIT lane.
            using var stream=new MemoryStream();using var w=new BinaryWriter(stream);
            w.Write(Encoding.ASCII.GetBytes("WZI1"));w.Write((ushort)20);w.Write((ushort)8);w.Write(1);w.Write(duration);w.Write((ushort)0);w.Write((ushort)0x0102);w.Write(0);w.Write(new byte[]{16,16,16,0});instruments=stream.ToArray();
        }
        var reductions=drumHits.Select(d=>new MidiDrumReduction(d.Key,d.Value,DrumControl(d.Key),DrumEnvelope(d.Key))).ToArray();
        return new(output.ToArray(),instruments,new(toneAttacks,drumAttacks,toneReductions,drumReductions,suppressedDrums,maxTones,maxDrums,ignored,reductions));
    }
    static (List<Event> Events,int Division,int Ignored) Parse(string path)
    {
        MovieEngine.RequireLocal(path);
        if (new FileInfo(path).Length > 4 * 1024 * 1024) throw new InvalidDataException("MIDI exceeds 4 MiB.");
        using var reader = new BinaryReader(File.OpenRead(path));
        int Byte() { if (reader.BaseStream.Position >= reader.BaseStream.Length) throw new InvalidDataException("Truncated MIDI."); return reader.ReadByte(); }
        int U16() => (Byte()<<8)|Byte();
        int U32() { long n = ((long)U16()<<16)|(uint)U16(); if(n > int.MaxValue) throw new InvalidDataException("Oversized MIDI chunk."); return (int)n; }
        string Tag() => Encoding.ASCII.GetString(reader.ReadBytes(4));
        if(Tag() != "MThd" || U32() != 6) throw new InvalidDataException("Invalid MIDI header.");
        int format=U16(), tracks=U16(), division=U16();
        if(format>1 || tracks<1 || tracks>64 || (format==0 && tracks!=1) || division==0 || (division&0x8000)!=0)
            throw new InvalidDataException("Supported MIDI: format 0 or 1, PPQN time division, up to 64 tracks.");
        var events = new List<Event>(); int order=0,ignored=0;
        for(int track=0;track<tracks;track++)
        {
            if(Tag() != "MTrk") throw new InvalidDataException("Missing MIDI track.");
            int length=U32(); long end=reader.BaseStream.Position+length, tick=0; int running=0;
            if(end>reader.BaseStream.Length) throw new InvalidDataException("Truncated MIDI track.");
            int TrackByte() { if(reader.BaseStream.Position>=end) throw new InvalidDataException("Truncated MIDI event."); return Byte(); }
            int Vlq() { int n=0; for(int i=0;i<4;i++){int b=TrackByte();n=(n<<7)|(b&127);if((b&128)==0)return n;} throw new InvalidDataException("Invalid MIDI variable integer."); }
            int Data() {int n=TrackByte();if(n>127)throw new InvalidDataException("Invalid MIDI data byte.");return n;}
            bool ended=false;
            while(reader.BaseStream.Position<end)
            {
                if(ended) throw new InvalidDataException("Data after MIDI end-of-track.");
                tick=checked(tick+Vlq()); int status=TrackByte(), first=-1;
                if(status<128) { first=status; status=running; if(status<128)throw new InvalidDataException("Missing MIDI running status."); }
                if(status==255)
                {
                    running=0; int type=TrackByte(), n=Vlq();
                    if(n>end-reader.BaseStream.Position)throw new InvalidDataException("Truncated MIDI metadata.");
                    if(type==81) {if(n!=3)throw new InvalidDataException("Invalid MIDI tempo.");int tempo=(TrackByte()<<16)|(TrackByte()<<8)|TrackByte();if(tempo==0)throw new InvalidDataException("Zero MIDI tempo.");events.Add(new(tick,order++,-1,0,0,tempo));}
                    else {if(type==47){if(n!=0)throw new InvalidDataException("Invalid end-of-track.");ended=true;events.Add(new(tick,order++,-2,0,0));}reader.BaseStream.Seek(n,SeekOrigin.Current);}
                }
                else if(status==240 || status==247)
                {running=0;int n=Vlq();if(n>end-reader.BaseStream.Position)throw new InvalidDataException("Truncated MIDI SysEx.");reader.BaseStream.Seek(n,SeekOrigin.Current);}
                else if(status>=128 && status<240)
                {
                    running=status;int a=first>=0?first:Data(), kind=status&240, b=(kind==192||kind==208)?0:Data();
                    if(kind==128 || kind==144) events.Add(new(tick,order++,status&15,a,kind==128?0:b,Track:track));
                    else if(kind==176 && a is 64 or 120 or 123) events.Add(new(tick,order++,status&15,-a,b,Track:track));
                    else ignored++;
                    // Program changes, pitch bends and expression are intentionally not synthesized.
                }
                else throw new InvalidDataException("Unsupported MIDI system status.");
                if(events.Count>100000)throw new InvalidDataException("Too many MIDI events.");
            }
            if(!ended)throw new InvalidDataException("MIDI track has no end-of-track.");
        }
        if(reader.BaseStream.Position!=reader.BaseStream.Length)throw new InvalidDataException("Unexpected trailing MIDI data.");
        return (events,division,ignored);
    }
    static int DrumPriority(int n)=>n is 35 or 36?0:n is 38 or 40?1:n is 42 or 44 or 46?2:3;
    static string DrumControl(int n)=>n is 35 or 36?"E2 periodic fixed2":n is 38 or 40?"E5 white fixed1":n is 42 or 44 or 46?"E4 white fixed0":"E6 white fixed2 (GM timbre reduction)";
    static string DrumEnvelope(int n)=>n is 35 or 36?"Kick":n is 42 or 44 or 46?"Hat":"Snare";
}
