param([Parameter(Mandatory=$true)][string]$Capture,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a new audio report file.'}
Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Collections.Generic;
public static class Mml3AudioInspect {
    class Track { public string Name="unknown";public int Channels,Rate,Bits,Format;public MemoryStream Data=new MemoryStream(); }
    struct Chunk { public string Tag;public int Start,End; }
    static string Tag(byte[] b,int p){return Encoding.ASCII.GetString(b,p,4);}
    static IEnumerable<Chunk> Chunks(byte[] b,int start,int end){
        while(start+8<=end){uint size=BitConverter.ToUInt32(b,start+4);long next=(long)start+8+size;
            if(next>end)throw new InvalidDataException("Truncated RIFF chunk.");
            yield return new Chunk{Tag=Tag(b,start),Start=start+8,End=(int)next};start=(int)next+(int)(size&1);
        }
    }
    static void Data(byte[] b,int start,int end,List<Track> tracks){
        foreach(var c in Chunks(b,start,end)){
            if(c.Tag=="LIST")Data(b,c.Start+4,c.End,tracks);
            else if(c.Tag.Substring(2)=="wb"){
                int index;if(!int.TryParse(c.Tag.Substring(0,2),out index)||index>=tracks.Count)throw new InvalidDataException("Bad audio stream.");
                tracks[index].Data.Write(b,c.Start,c.End-c.Start);
            }
        }
    }
    public static Dictionary<string,object> Inspect(string path){
        if(new FileInfo(path).Length>64*1024*1024)throw new InvalidDataException("Capture too large.");
        byte[] b=File.ReadAllBytes(path);if(b.Length<12||Tag(b,0)!="RIFF"||Tag(b,8)!="AVI ")throw new InvalidDataException("Expected AVI capture.");
        var tracks=new List<Track>();
        foreach(var c in Chunks(b,12,b.Length))if(c.Tag=="LIST"&&Tag(b,c.Start)=="hdrl"){
            foreach(var list in Chunks(b,c.Start+4,c.End))if(list.Tag=="LIST"&&Tag(b,list.Start)=="strl"){
                var t=new Track();foreach(var v in Chunks(b,list.Start+4,list.End)){
                    if(v.Tag=="strn")t.Name=Encoding.ASCII.GetString(b,v.Start,v.End-v.Start).TrimEnd('\0');
                    if(v.Tag=="strf"){t.Format=BitConverter.ToUInt16(b,v.Start);t.Channels=BitConverter.ToUInt16(b,v.Start+2);t.Rate=BitConverter.ToInt32(b,v.Start+4);t.Bits=BitConverter.ToUInt16(b,v.Start+14);}
                }tracks.Add(t);
            }
        }
        Data(b,12,b.Length,tracks);var result=new Dictionary<string,object>();var masks=new Dictionary<string,bool[]>();
        foreach(var t in tracks){
            if(t.Format!=1||t.Bits!=16||t.Channels<1||t.Rate<1)throw new InvalidDataException("Expected PCM16 audio tracks.");
            byte[] raw=t.Data.ToArray();int frames=raw.Length/(2*t.Channels),first=-1,last=-1,active=0;double peak=0;var mask=new bool[frames];
            for(int i=0;i<frames;i++){
                double sample=0;for(int j=0;j<t.Channels;j++)sample+=BitConverter.ToInt16(raw,2*(i*t.Channels+j));sample=Math.Abs(sample/t.Channels);peak=Math.Max(peak,sample);
                if(sample>5){if(first<0)first=i;last=i;mask[i]=true;active++;}
            }
            masks[t.Name]=mask;result[t.Name]=new{sample_rate=t.Rate,frames=frames,peak=peak,active_frames=active,first_active_s=first<0?(double?)null:(double)first/t.Rate,last_active_s=last<0?(double?)null:(double)last/t.Rate};
        }
        if(!masks.ContainsKey("SPKR")||!masks.ContainsKey("TANDY"))throw new InvalidDataException("Missing independent speaker/Tandy tracks.");
        int simultaneous=0;for(int i=0;i<Math.Min(masks["SPKR"].Length,masks["TANDY"].Length);i++)if(masks["SPKR"][i]&&masks["TANDY"][i])simultaneous++;
        result["simultaneous_nonzero_frames"]=simultaneous;return result;
    }
}
'@
$report=[Mml3AudioInspect]::Inspect((Resolve-Path -LiteralPath $Capture).Path)
if($report.SPKR.peak-le0||$report.TANDY.peak-le0||$report.simultaneous_nonzero_frames-le0){throw 'No independently captured simultaneous PIT/PSG output.'}
$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $Output
Write-Output ('PASS: captured SPKR/PSG activity and '+$report.simultaneous_nonzero_frames+' simultaneous frames. '+$Output)
