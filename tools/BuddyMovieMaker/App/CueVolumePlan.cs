using System.Globalization;
using System.IO;

namespace BuddyMovieMaker;

// Source model; OwnedMidi emits the separately frozen WZG1 extension.
// Extra chip attenuation is independent of note-on velocity/preset/envelope age.
public record CueGainEvent(string Cue, int FilmMs, int ExtraSteps, bool EndCue);
public record CueGainDecision(bool CueActive, int ExtraSteps, bool CueEnded);
public sealed class CueVolumePlan
{
    readonly Dictionary<string,CueGainEvent[]> cues;
    public CueGainEvent[] Events { get; }
    public CueVolumePlan(IEnumerable<CueGainEvent> source)
    {
        Events=source.OrderBy(e=>e.FilmMs).ThenBy(e=>e.Cue,StringComparer.Ordinal).ToArray();
        if(Events.Length is <1 or >10000)throw new InvalidDataException("Cue automation needs 1..10,000 events.");
        cues=new(StringComparer.Ordinal);
        foreach(var group in Events.GroupBy(e=>e.Cue))
        {
            if(string.IsNullOrWhiteSpace(group.Key)||group.Key.Length>32||group.Key.Any(c=>!char.IsAsciiLetterOrDigit(c)&&c!='_'&&c!='-'))throw new InvalidDataException("Cue owner must be a named identifier, never global/all voices.");
            var list=group.ToArray();
            if(list[0].EndCue||list[0].ExtraSteps!=0)throw new InvalidDataException("Each cue must start with zero extra attenuation.");
            bool ended=false;int previous=-1;
            foreach(var e in list)
            {
                if(e.FilmMs<0||e.FilmMs>86400000||e.FilmMs<=previous||ended||e.ExtraSteps<0||e.ExtraSteps>(e.EndCue?15:14)||e.EndCue&&e.ExtraSteps!=15)throw new InvalidDataException("Invalid, ambiguous or post-end cue attenuation event.");
                previous=e.FilmMs;ended=e.EndCue;
            }
            cues[group.Key]=list;
        }
    }
    public CueGainDecision Evaluate(string owner,int filmMs)
    {
        if(filmMs<0||!cues.TryGetValue(owner,out var list))throw new InvalidDataException("A valid explicit cue owner and film time are required.");
        var e=list.LastOrDefault(e=>e.FilmMs<=filmMs);
        return e==null?new(false,0,false):new(!e.EndCue,e.ExtraSteps,e.EndCue);
    }
    public static CueVolumePlan FromCsv(string path)
    {
        MovieEngine.RequireLocal(path);
        if(new FileInfo(path).Length>128*1024)throw new InvalidDataException("Cue automation CSV exceeds 128 KiB.");
        var lines=File.ReadAllLines(path);
        if(lines.Length<2||lines[0]!="cue,film_s,action,chip_steps,attenuation_db,scope")throw new InvalidDataException("Expected the explicit cue-scoped attenuation CSV schema.");
        var result=new List<CueGainEvent>();
        foreach(var line in lines.Skip(1))
        {
            var row=line.Split(',');
            if(row.Length!=6||!decimal.TryParse(row[1],NumberStyles.AllowDecimalPoint,CultureInfo.InvariantCulture,out var seconds)||seconds<0||seconds>86400||!int.TryParse(row[3],NumberStyles.None,CultureInfo.InvariantCulture,out var steps)||!row[5].StartsWith("notes belonging to this cue only",StringComparison.Ordinal))throw new InvalidDataException("Invalid cue-scoped attenuation CSV row.");
            bool end=row[2]=="cue_notes_off";
            if(!end&&row[2]!="set_extra_attenuation"||end&&row[4]!="silence"||!end&&row[4]!=(steps*2).ToString(CultureInfo.InvariantCulture))throw new InvalidDataException("Unknown automation action or inconsistent 2 dB chip steps.");
            result.Add(new(row[0],(int)decimal.Round(seconds*1000,0,MidpointRounding.AwayFromZero),steps,end));
        }
        return new(result);
    }
}
