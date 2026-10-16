using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Globalization;
using Microsoft.VisualBasic.FileIO;

namespace BuddyMovieMaker;

public record MidiCueAnnotation(string Cue,int Channel,int Note,int Velocity,long StartTick,long EndTick,
    int FilmStartMs,int FilmEndMs,int? Track=null);
public record OwnedMidiNote(string Cue,int Track,int Channel,int Note,int Velocity,long StartTick,long EndTick,int StartMs,int EndMs);
public sealed class VerifiedOwnedMidi
{
    public IReadOnlyList<OwnedMidiNote> Notes { get; }
    public string SourceSha256 { get; }
    public int IgnoredMessages { get; }
    internal VerifiedOwnedMidi(OwnedMidiNote[] notes,string sha256,int ignored)
    {Notes=Array.AsReadOnly(notes);SourceSha256=sha256;IgnoredMessages=ignored;}
}
public record OwnedGainReport(string MasterSha256,int VerifiedSourceNotes,int SelectedNotes,int ClippedHeldSeeds,
    int ToneReductionStates,int DrumReductionStates,int DiscardedInstances,int DurationMs,int FilmOriginMs);
public record OwnedGainArrangement(byte[] Music,byte[] Instruments,byte[] Gain,OwnedGainReport Report);

public static partial class MidiScore
{
    public static VerifiedOwnedMidi VerifyOwnersCsv(string midi,string annotations)
    {
        MovieEngine.RequireLocal(annotations);
        if(new FileInfo(annotations).Length>4*1024*1024)throw new InvalidDataException("Ownership CSV exceeds4MiB.");
        using var reader=new TextFieldParser(annotations,Encoding.UTF8){TextFieldType=FieldType.Delimited,HasFieldsEnclosedInQuotes=true,TrimWhiteSpace=false};
        reader.SetDelimiters(",");
        var header=reader.ReadFields()??[];
        string[] required=["midi_channel","midi_note","velocity","start_tick","end_tick","film_start_s","film_end_s","source_cue"];
        if(header.Distinct(StringComparer.Ordinal).Count()!=header.Length||required.Any(n=>!header.Contains(n,StringComparer.Ordinal)))throw new InvalidDataException("Ownership CSV needs explicit source cue, channel, pitch, velocity, on/off ticks and film times.");
        var fields=header.Select((n,i)=>(n,i)).ToDictionary(p=>p.n,p=>p.i,StringComparer.Ordinal);var rows=new List<MidiCueAnnotation>();
        while(!reader.EndOfData)
        {
            string[] row;try{row=reader.ReadFields()??[];}catch(MalformedLineException e){throw new InvalidDataException("Malformed ownership CSV row.",e);}
            if(row.Length!=header.Length||rows.Count>=100000)throw new InvalidDataException("Ownership CSV row/count invalid.");
            string Get(string n)=>row[fields[n]];
            long Integer(string n){if(!long.TryParse(Get(n),NumberStyles.None,CultureInfo.InvariantCulture,out long value))throw new InvalidDataException("Invalid ownership integer: "+n);return value;}
            int Time(string n){if(!decimal.TryParse(Get(n),NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out decimal value)||value<0||value>86400)throw new InvalidDataException("Invalid ownership film time.");return (int)decimal.Round(value*1000,0,MidpointRounding.AwayFromZero);}
            long channel=Integer("midi_channel"),note=Integer("midi_note"),velocity=Integer("velocity");
            if(channel is <1 or >16||note is <0 or >127||velocity is <1 or >127)throw new InvalidDataException("Ownership MIDI channel/pitch/velocity range invalid.");
            int? track=null;if(fields.ContainsKey("track")){long t=Integer("track");if(t is <0 or >63)throw new InvalidDataException("Source track out of range.");track=(int)t;}
            rows.Add(new(Get("source_cue"),(int)channel-1,(int)note,(int)velocity,Integer("start_tick"),Integer("end_tick"),Time("film_start_s"),Time("film_end_s"),track));
        }
        return VerifyOwners(midi,rows);
    }
    public static VerifiedOwnedMidi VerifyOwners(string path,IReadOnlyList<MidiCueAnnotation> annotations)
    {
        if(annotations.Count is <1 or >100000)throw new InvalidDataException("Ownership annotations need 1..100,000 note instances.");
        var (events,division,ignored)=Parse(path);
        if(events.Any(e=>e.Channel>=0&&e.Note<0))throw new InvalidDataException("Owned gain input needs explicit held note gates; sustain/all-notes-off controllers are unsupported.");
        var queues=new Dictionary<(int,int,int),Queue<Event>>();
        var pairs=new List<(Event On,Event Off)>();
        foreach(var e in events.OrderBy(e=>e.Tick).ThenBy(e=>e.Order))
        {
            if(e.Channel<0)continue;
            var key=(e.Track,e.Channel,e.Note);
            if(e.Velocity>0){if(!queues.TryGetValue(key,out var q))queues[key]=q=new();q.Enqueue(e);}
            else {if(!queues.TryGetValue(key,out var q)||q.Count==0)throw new InvalidDataException("Unmatched MIDI note-off in owned input.");var on=q.Dequeue();if(e.Tick<=on.Tick)throw new InvalidDataException("Owned MIDI note gate must be positive.");pairs.Add((on,e));}
        }
        if(queues.Values.Any(q=>q.Count!=0)||pairs.Count!=annotations.Count)throw new InvalidDataException("Ownership must cover every paired source note exactly once.");
        var times=new Dictionary<long,int>();long tick=0;double us=0;int tempo=500000;
        foreach(var e in events.OrderBy(e=>e.Tick).ThenBy(e=>e.Order))
        {
            us+=(e.Tick-tick)*(double)tempo/division;tick=e.Tick;
            if(!double.IsFinite(us)||us/1000>86400000)throw new InvalidDataException("Owned MIDI timeline exceeds one day.");
            times[tick]=(int)Math.Round(us/1000,MidpointRounding.AwayFromZero);
            if(e.Tempo>0)tempo=e.Tempo;
        }
        var available=pairs.GroupBy(p=>(p.On.Channel,p.On.Note,p.On.Velocity,p.On.Tick,p.Off.Tick))
            .ToDictionary(g=>g.Key,g=>g.ToList());var result=new List<OwnedMidiNote>();
        foreach(var a in annotations)
        {
            if(string.IsNullOrWhiteSpace(a.Cue)||a.Cue.Length>32||a.Cue.Any(c=>!char.IsAsciiLetterOrDigit(c)&&c!='_'&&c!='-'))throw new InvalidDataException("Explicit cue identifier required.");
            var key=(a.Channel,a.Note,a.Velocity,a.StartTick,a.EndTick);
            if(!available.TryGetValue(key,out var matches))throw new InvalidDataException("Annotation does not match source note ticks/velocity/channel/pitch.");
            var matching=matches.Where(p=>a.Track==null||p.On.Track==a.Track).ToArray();
            if(matching.Length!=1)throw new InvalidDataException("Ambiguous or duplicate ownership; supply matching source track identity.");
            var p=matching[0];matches.Remove(p);
            int start=times[p.On.Tick],end=times[p.Off.Tick];
            if(Math.Abs((long)a.FilmStartMs-start)>1||Math.Abs((long)a.FilmEndMs-end)>1||end<=start)
                throw new InvalidDataException("Ownership film times do not match the source MIDI tempo map.");
            if(p.On.Channel==9?(p.On.Note<35||p.On.Note>81):(p.On.Note<45||p.On.Note>96))throw new InvalidDataException("Owned MIDI note outside supported tone/drum range.");
            result.Add(new(a.Cue,p.On.Track,p.On.Channel,p.On.Note,p.On.Velocity,p.On.Tick,p.Off.Tick,start,end));
        }
        using var file=File.OpenRead(path);
        return new(result.OrderBy(n=>n.StartMs).ThenBy(n=>n.Track).ThenBy(n=>n.StartTick).ToArray(),System.Convert.ToHexString(SHA256.HashData(file)),ignored);
    }

    public static OwnedGainArrangement ArrangeOwned(VerifiedOwnedMidi source,CueVolumePlan plan,int filmOriginMs,int duration)
    {
        if(filmOriginMs<0||duration is <1 or >600000||(long)filmOriginMs+duration>86400000)throw new InvalidDataException("Owned gain selection needs valid origin and 1..600,000 ms duration.");
        foreach(var n in source.Notes)if(!plan.Evaluate(n.Cue,n.StartMs).CueActive)throw new InvalidDataException("Note begins outside its explicitly owned cue automation.");
        int finish=checked(filmOriginMs+duration);
        var selected=source.Notes.Where(n=>n.StartMs<finish&&n.EndMs>filmOriginMs).ToArray();
        var starts=selected.Select((n,id)=>(n,id)).GroupBy(x=>Math.Max(filmOriginMs,x.n.StartMs)).ToDictionary(g=>g.Key,g=>g.ToArray());
        var ends=selected.Select((n,id)=>(n,id)).GroupBy(x=>Math.Min(finish,x.n.EndMs)).ToDictionary(g=>g.Key,g=>g.ToArray());
        var boundaries=new SortedSet<int>(starts.Keys.Concat(ends.Keys).Concat(plan.Events.Where(e=>e.FilmMs>=filmOriginMs&&e.FilmMs<=finish).Select(e=>e.FilmMs))){filmOriginMs,finish};
        var active=new Dictionary<int,OwnedMidiNote>();int?[] lanes=new int?[4];
        var music=new SortedDictionary<int,byte[]>();var gains=new SortedDictionary<int,byte[]>();
        byte[] previous=new byte[10],extra=new byte[4];int toneReductions=0,drumReductions=0,discarded=0;
        foreach(int time in boundaries)
        {
            if(ends.TryGetValue(time,out var offs))foreach(var off in offs)active.Remove(off.id);
            foreach(var id in active.Keys.ToArray())if(!plan.Evaluate(active[id].Cue,time).CueActive)active.Remove(id);
            if(time<finish&&starts.TryGetValue(time,out var ons))foreach(var on in ons)if(plan.Evaluate(on.n.Cue,time).CueActive)active.Add(on.id,on.n);
            // One selected attack per shared MIDI channel/pitch. Equal-velocity
            // overlap hands over to the latest authored instance, with retrigger.
            // This is an explicit reported reduction, never a global cue-off.
            int toneCount=active.Count(k=>k.Value.Channel!=9);
            var tones=active.Where(k=>k.Value.Channel!=9).GroupBy(k=>(k.Value.Channel,k.Value.Note))
                .Select(g=>g.OrderByDescending(k=>k.Value.Velocity).ThenByDescending(k=>k.Value.StartMs).ThenBy(k=>k.Value.Track).ThenBy(k=>k.Key).First())
                .OrderByDescending(k=>k.Value.Velocity).ThenBy(k=>k.Value.Channel).ThenBy(k=>k.Value.Note).ThenBy(k=>k.Value.Track).ThenBy(k=>k.Key).ToArray();
            var drums=active.Where(k=>k.Value.Channel==9).OrderByDescending(k=>k.Value.Velocity).ThenBy(k=>DrumPriority(k.Value.Note)).ThenByDescending(k=>k.Value.StartMs).ThenBy(k=>k.Value.Track).ThenBy(k=>k.Value.Note).ThenBy(k=>k.Key).ToArray();
            if(toneCount>Math.Min(3,tones.Length))toneReductions++;if(drums.Length>1)drumReductions++;
            var chosen=tones.Take(3).Select(k=>k.Key).Concat(drums.Take(1).Select(k=>k.Key)).ToHashSet();
            foreach(var id in active.Keys.Where(id=>!chosen.Contains(id)).ToArray()){active.Remove(id);discarded++;}
            var old=(int?[])lanes.Clone();
            for(int i=0;i<4;i++)if(lanes[i] is int id&&!chosen.Contains(id)){if(plan.Evaluate(selected[id].Cue,time).CueEnded)extra[i]=15;lanes[i]=null;}
            foreach(var id in tones.Take(3).Select(k=>k.Key).OrderBy(id=>selected[id].Channel).ThenBy(id=>selected[id].Note).ThenBy(id=>selected[id].Track))
                if(!lanes.Take(3).Contains(id))lanes[Array.FindIndex(lanes,0,3,v=>v==null)]=id;
            lanes[3]=drums.Length>0?drums[0].Key:null;
            byte[] state=new byte[10];
            for(int i=0;i<4;i++)if(lanes[i] is int id){var n=selected[id];state[i]=(byte)n.Note;state[i+4]=(byte)n.Velocity;if(old[i]!=id)state[8]|=(byte)(1<<i);extra[i]=(byte)plan.Evaluate(n.Cue,time).ExtraSteps;}
            int output=time-filmOriginMs;
            if(time==finish){state=new byte[10];extra=new byte[]{15,15,15,15};}
            if(output==0||time==finish||state[8]!=0||!state.AsSpan(0,8).SequenceEqual(previous.AsSpan(0,8)))music[output]=state;
            previous=state;
            if(output==0||time==finish||!extra.SequenceEqual(gains.Last().Value))gains[output]=(byte[])extra.Clone();
        }
        if(music.Count>10000||gains.Count>10000)throw new InvalidDataException("Owned gain output exceeds a separate 10,000-record stream limit.");
        byte[] Write(string magic,int record,SortedDictionary<int,byte[]> states){using var s=new MemoryStream();using var w=new BinaryWriter(s);w.Write(Encoding.ASCII.GetBytes(magic));w.Write((ushort)20);w.Write((ushort)record);w.Write(states.Count);w.Write(duration);w.Write(0);foreach(var (t,b) in states){w.Write(t);w.Write(b);}return s.ToArray();}
        using var inst=new MemoryStream();using(var w=new BinaryWriter(inst,Encoding.ASCII,true)){w.Write(Encoding.ASCII.GetBytes("WZI1"));w.Write((ushort)20);w.Write((ushort)8);w.Write(1);w.Write(duration);w.Write((ushort)2);w.Write((ushort)0x0102);w.Write(0);w.Write(new byte[]{16,16,16,0});}
        return new(Write("WZM3",14,music),inst.ToArray(),Write("WZG1",8,gains),new(source.SourceSha256,source.Notes.Count,selected.Length,selected.Count(n=>n.StartMs<filmOriginMs),toneReductions,drumReductions,discarded,duration,filmOriginMs));
    }
}
