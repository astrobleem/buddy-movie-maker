using System.IO;
using System.Text;
using System.Text.RegularExpressions;

namespace BuddyMovieMaker;
public record MmlResult(byte[] Music,byte[] Instruments,int ScoreMs,int Version=1);
public static class MmlScore
{
    public static readonly string[] Presets=["KEYS","ORGAN","BASS","PAD","REED","LEAD","BELL","HIT"];
    record Token(char Command,int Number,string Word,bool Dotted,int Source,int Drum=0);
    record Event(int Time,int Part,int Note,int Velocity,bool Attack);
    record Program(int Time,int Part,int Value);
    static int RoundMs(long whole,long remainder)=>(int)whole+(remainder>=48000?1:0);
    public static MmlResult FromFile(string path,int movieMs,int initialProgram=0,bool vibrato=true)
    {MovieEngine.RequireLocal(path);return Compile(Encoding.ASCII.GetString(ReadSource(path)),movieMs,initialProgram,vibrato);}
    static byte[] ReadSource(string path)
    {if(new FileInfo(path).Length>8192)throw new InvalidDataException("MML exceeds 8 KiB (line 1, column 1).");var bytes=File.ReadAllBytes(path);if(bytes.Length>8192||bytes.Any(b=>b>127||b<32&&b is not 9 and not 10 and not 13))throw new InvalidDataException("MML must be ASCII text, no BOM, maximum 8 KiB (line 1, column 1).");return bytes;}
    public static MmlResult Compile(string source,int? movieMs=null,int initialProgram=0,bool vibrato=true)
    {
        if(source.Length>8192||source.Any(c=>c>127||c<32&&c is not '\t' and not '\r' and not '\n'))throw new InvalidDataException("MML must be ASCII text, no BOM, maximum 8 KiB (line 1, column 1).");
        if(initialProgram<0||initialProgram>112||initialProgram%16!=0)throw new ArgumentException("Unknown initial MML preset.");
        void Error(int offset,string message){int line=1,column=1;for(int i=0;i<Math.Min(offset,source.Length);i++){if(source[i]=='\n'){line++;column=1;}else column++;}throw new InvalidDataException($"MML line {line}, column {column}: {message}");}
        var bodies=new StringBuilder[]{new(),new(),new(),new()};var positions=new List<int>[]{new(),new(),new(),new()};bool[] present=new bool[4];int part=-1,absolute=0,version=1;bool meaningful=false;
        foreach(string line in source.Split('\n'))
        {
            string text=line.Split(';',2)[0];
            if(text.Trim().Equals("MML2",StringComparison.OrdinalIgnoreCase))
            {if(meaningful)Error(absolute,"MML2 must be the first nonblank, noncomment line.");version=2;meaningful=true;absolute+=line.Length+1;continue;}
            var header=Regex.Match(text,@"^\s*\[([ABCN])\]\s*$",RegexOptions.IgnoreCase);
            if(header.Success){char section=char.ToUpperInvariant(header.Groups[1].Value[0]);part=section=='N'?3:section-'A';if(part==3&&version!=2)Error(absolute,"Noise section [N] requires the first-line MML2 declaration.");if(present[part])Error(absolute,"Duplicate section.");present[part]=true;}
            else if(!string.IsNullOrWhiteSpace(text))
            {if(part<0)Error(absolute,"Content before section [A], [B] or [C].");for(int i=0;i<text.Length;i++){bodies[part].Append(text[i]);positions[part].Add(absolute+i);}bodies[part].Append(' ');positions[part].Add(absolute+line.Length);}
            if(!string.IsNullOrWhiteSpace(text))meaningful=true;absolute+=line.Length+1;
        }
        int budget=0,totalDuration=0;var events=new List<Event>();var programs=new List<Program>();
        for(int channel=0;channel<4;channel++)
        {
            string body=bodies[channel].ToString();var offsets=positions[channel];
            void Fail(int i,string message)=>Error(i<offsets.Count?offsets[i]:source.Length,message);
            void White(ref int i,int end){while(i<end&&char.IsWhiteSpace(body[i]))i++;}
            int Number(ref int i,int end,bool required)
            {White(ref i,end);int start=i,n=0;while(i<end&&char.IsDigit(body[i])){n=checked(n*10+body[i++]-'0');if(n>100000){Fail(start,"Number too large.");}}if(required&&i==start)Fail(start,"Expected a number.");return i==start?-1:n;}
            IEnumerable<Token> Scan(int start,int end,int depth)
            {
                int i=start;
                while(i<end)
                {
                    White(ref i,end);if(i>=end)yield break;int tokenStart=i;char c=char.ToUpperInvariant(body[i++]);
                    if(c=='[')
                    {
                        if(depth>=2)Fail(tokenStart,"Repeat nesting exceeds 2.");int inner=i,nesting=1;
                        while(i<end&&nesting>0){if(body[i]=='[')nesting++;else if(body[i]==']')nesting--;i++;}
                        if(nesting!=0)Fail(tokenStart,"Unmatched repeat.");int close=i-1,repeats=Number(ref i,end,true);
                        if(repeats<2||repeats>8)Fail(close,"Repeat count must be 2..8.");
                        for(int repeat=0;repeat<repeats;repeat++)foreach(var token in Scan(inner,close,depth+1))yield return token;
                        continue;
                    }
                    if(++budget>32768)Fail(tokenStart,"Expanded token budget exceeds 32768.");
                    string word="";int number=-1,drum=0;bool dot=false;
                    if(channel==3&&c is not 'T' and not 'L' and not 'V' and not 'R' and not 'N')Fail(tokenStart,"Noise allows only T/L/V, rests and N35..81 hits.");
                    if(c=='@'){White(ref i,end);int wordStart=i;while(i<end&&char.IsLetter(body[i]))i++;word=body[wordStart..i].ToUpperInvariant();}
                    else if(c is 'T' or 'O' or 'L' or 'V')number=Number(ref i,end,true);
                    else if(c=='N')
                    {
                        if(channel!=3||version!=2)Fail(tokenStart,"Noise hits require MML2 section [N].");
                        drum=Number(ref i,end,true);if(drum<35||drum>81)Fail(tokenStart,"Noise code must be 35..81; use R for rests.");
                        White(ref i,end);if(i<end&&body[i]=='/'){i++;number=Number(ref i,end,true);}
                        White(ref i,end);if(i<end&&body[i]=='.'){dot=true;i++;}
                    }
                    else if(c is 'A' or 'B' or 'C' or 'D' or 'E' or 'F' or 'G' or 'R')
                    {
                        White(ref i,end);if(c!='R'&&i<end&&body[i] is '#' or '+' or '-')word=body[i++].ToString();
                        number=Number(ref i,end,false);White(ref i,end);if(i<end&&body[i]=='.'){dot=true;i++;}
                    }
                    else if(c is not '<' and not '>')Fail(tokenStart,"Unknown token or unmatched repeat.");
                    yield return new(c,number,word,dot,offsets[tokenStart],drum);
                }
            }
            int tempo=500000,octave=4,length=4,volume=channel==3?9:12,notes=0;long whole=0,remainder=0;bool crossed=false;
            if(channel<3)programs.Add(new(0,channel,initialProgram));
            foreach(var token in Scan(0,body.Length,0))
            {
                int now=RoundMs(whole,remainder),n=token.Number;
                if(movieMs.HasValue&&(now>movieMs.Value||crossed))Error(token.Source,"Only a trailing note/rest may cross video end; no later command or attack.");
                switch(token.Command)
                {
                    case 'T':if(n<40||n>240)Error(token.Source,"Tempo must be 40..240.");tempo=(60000000+n/2)/n;continue;
                    case 'O':if(n<2||n>7)Error(token.Source,"Octave must be 2..7.");octave=n;continue;
                    case '<':if(--octave<2)Error(token.Source,"Octave below 2.");continue;
                    case '>':if(++octave>7)Error(token.Source,"Octave above 7.");continue;
                    case 'V':if(n<0||n>15)Error(token.Source,"Volume must be 0..15.");volume=n;continue;
                    case 'L':if(n is not 1 and not 2 and not 4 and not 8 and not 16 and not 32 and not 64)Error(token.Source,"Length denominator must be 1/2/4/8/16/32/64.");length=n;continue;
                    case '@':int preset=Array.IndexOf(Presets,token.Word);if(preset<0)Error(token.Source,"Unknown WININST12 preset.");programs.Add(new(now,channel,preset*16));continue;
                }
                if(++notes>4096)Error(token.Source,"Maximum 4096 notes/rests per part.");
                if(n<0)n=length;if(n is not 1 and not 2 and not 4 and not 8 and not 16 and not 32 and not 64)Error(token.Source,"Unsupported note/rest denominator.");
                int ticks=384/n;if(token.Dotted)ticks=ticks*3/2;
                long numerator=ticks*(long)tempo+remainder;whole+=numerator/96000;remainder=numerator%96000;int end=RoundMs(whole,remainder);
                if(end>600000)Error(token.Source,"Score exceeds 600 seconds.");
                if(movieMs.HasValue&&end>movieMs.Value+250)Error(token.Source,"Trailing note/rest exceeds the 250 ms video-end allowance.");
                int clipped=movieMs.HasValue?Math.Min(end,movieMs.Value):end;
                if(token.Command!='R'&&volume!=0)
                {
                    int pitch=channel==3?token.Drum:(octave+1)*12+(token.Command switch {'C'=>0,'D'=>2,'E'=>4,'F'=>5,'G'=>7,'A'=>9,'B'=>11,_=>0});
                    if(channel<3){pitch+=token.Word is "#" or "+"?1:token.Word=="-"?-1:0;if(pitch<45||pitch>96)Error(token.Source,"Melodic pitch must be MIDI 45..96.");}
                    if(movieMs.HasValue&&now>=movieMs.Value)Error(token.Source,"New attack at or after video end.");
                    events.Add(new(now,channel,pitch,1+9*(volume-1),true));events.Add(new(clipped,channel,0,0,false));
                }
                crossed=movieMs.HasValue&&end>movieMs.Value;totalDuration=Math.Max(totalDuration,end);
            }
        }
        if(!present.Any(p=>p)||totalDuration==0)Error(0,"Score needs at least one note/rest in a section.");
        int duration=movieMs??totalDuration;
        var states=new SortedDictionary<int,byte[]>{[0]=new byte[10]};byte[] state=new byte[10];
        foreach(var group in events.OrderBy(e=>e.Time).ThenBy(e=>e.Attack?1:0).ThenBy(e=>e.Part).GroupBy(e=>e.Time))
        {state[8]=0;foreach(var ev in group){state[ev.Part]=(byte)ev.Note;state[ev.Part+4]=(byte)ev.Velocity;if(ev.Attack)state[8]|=(byte)(1<<ev.Part);}states[group.Key]=(byte[])state.Clone();}
        states[duration]=new byte[10];if(states.Count>10000)throw new InvalidDataException("MML exceeds 10000 merged WZM states.");
        using var music=new MemoryStream();using(var w=new BinaryWriter(music,Encoding.ASCII,true))
        {w.Write(Encoding.ASCII.GetBytes("WZM1"));w.Write((ushort)20);w.Write((ushort)14);w.Write(states.Count);w.Write(duration);w.Write(0);foreach(var pair in states){w.Write(pair.Key);w.Write(pair.Value);}}
        var instrumentStates=new SortedDictionary<int,byte[]>();byte[] selected=new byte[4];
        foreach(var group in programs.OrderBy(p=>p.Time).GroupBy(p=>p.Time))
        {foreach(var p in group)selected[p.Part]=(byte)p.Value;instrumentStates[group.Key]=(byte[])selected.Clone();}
        if(instrumentStates.Count>10000)throw new InvalidDataException("MML exceeds 10000 merged WZI states.");
        using var instruments=new MemoryStream();using(var w=new BinaryWriter(instruments,Encoding.ASCII,true))
        {w.Write(Encoding.ASCII.GetBytes("WZI1"));w.Write((ushort)20);w.Write((ushort)8);w.Write(instrumentStates.Count);w.Write(duration);w.Write((ushort)(vibrato?1:0));w.Write((ushort)0x0102);foreach(var pair in instrumentStates){w.Write(pair.Key);w.Write(pair.Value);}}
        return new(music.ToArray(),instruments.ToArray(),totalDuration,version);
    }
}
