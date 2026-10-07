namespace BuddyMoviePlayer;
public record SynthSnapshot(int Time,byte[] Notes,byte[] Velocities,int[] Presets,int[] Attacks,byte[] Extra,int[] EnvelopeAttenuations,int[] EffectiveAttenuations,double[] TonePhase,int NoiseState);
public static class Synth
{
 public const int Rate=24000;
 static readonly int[] Periods=[1017,960,906,855,807,762,719,679,641,605,571,539,508,480,453,428,404,381,360,339,320,302,285,269,254,240,226,214,202,190,180,170,160,151,143,135,127,120,113,107,101,95,90,85,80,76,71,67,64,60,57,53];
 static readonly int[][] Curves=[
 [0,0,1,2,3,4,5,6,7,8,8,8,8,8,8,8], [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0],
 [0,0,1,1,2,2,3,3,4,4,5,5,5,5,5,5], [12,9,6,4,2,1,0,0,1,1,1,1,1,1,1,1],
 [4,2,1,0,0,1,1,1,2,2,2,2,2,2,2,2], [1,0,0,1,1,1,1,1,2,2,2,2,2,2,2,2],
 [0,2,4,5,6,7,8,9,10,11,12,13,14,15,15,15], [0,2,4,6,8,10,12,14,15,15,15,15,15,15,15,15],
 [1,2,4,7,10,13,15,15,15,15,15,15,15,15,15,15], [0,2,5,8,11,15,15,15,15,15,15,15,15,15,15,15],
 [2,6,10,15,15,15,15,15,15,15,15,15,15,15,15,15]];
 static readonly int[] Motion=[0,1,2,1,0,-1,-2,-1];
 public static (int Period,int Attenuation) Envelope(int preset,int baseAtten,int period,int attackMs,int nowMs,bool vibrato)
 {
  int elapsed=nowMs/55-attackMs/55,curve=Curves[preset][Math.Min(15,elapsed)];
  if(curve==15)return(period,15);
  if(vibrato&&elapsed>=8&&preset is 3 or 4 or 5)period=Math.Clamp(period+Motion[elapsed&7]*(period>>8),1,1023);
  return(period,Math.Min(15,curve+baseAtten));
 }
 public static short[] Render(Movie movie,bool includePsg=true,bool includePit=true,bool includeSpeech=true,Action<SynthSnapshot>? observe=null)
 {
  short[] output=new short[movie.Duration*(Rate/1000)];byte[] notes=new byte[4],vel=new byte[4],programs=new byte[3];
  int[] attack=new int[4],preset=new int[4],period=new int[4],atten=new int[4];double[] phase=new double[3];int score=0,inst=0,speech=0,lfsr=0x4000;double noisePhase=0;
  bool expressive=movie.Instruments.Count>0;int pitIndex=0,pitNote=0,pitDivisor=0,gain=0;byte[] extra=new byte[4];long pitPhase=0;
  for(int sample=0;sample<=output.Length;sample++) {
   int ms=sample/(Rate/1000);
   while(pitIndex<movie.PitNotes.Count&&movie.PitNotes[pitIndex].Time<=ms) {
    var p=movie.PitNotes[pitIndex++];
    if(p.Note==0){pitNote=0;pitPhase=0;}
    else if(p.Note!=pitNote||p.Attack){pitNote=p.Note;pitDivisor=PitOscillator.Divisor(p.Note);pitPhase=0;}
   }
   while((score<movie.Scores.Count&&movie.Scores[score].Time<=ms)||(inst<movie.Instruments.Count&&movie.Instruments[inst].Time<=ms)) {
    if(inst<movie.Instruments.Count&&movie.Instruments[inst].Time<=ms&&(score==movie.Scores.Count||movie.Instruments[inst].Time<=movie.Scores[score].Time)) {programs=movie.Instruments[inst++].Programs;continue;}
    Score s=movie.Scores[score++];
    for(int i=0;i<4;i++)if(notes[i]!=s.Notes[i]||vel[i]!=s.Velocities[i]||(s.Retrigger&(1<<i))!=0) {
     notes[i]=s.Notes[i];vel[i]=s.Velocities[i];attack[i]=s.Time;
     if(notes[i]==0)continue;
     atten[i]=14-((vel[i]-1)*14/126);
     if(i<3) {period[i]=Periods[notes[i]-45];preset[i]=programs[i]>>4;}
     else {preset[i]=notes[i] is 35 or 36?8:notes[i] is 42 or 44 or 46?10:9;period[i]=notes[i] is 35 or 36?2:notes[i] is 38 or 40?5:notes[i] is 42 or 44 or 46?4:6;lfsr=0x4000;noisePhase=0;}
    }
   }
   while(gain<movie.Gains.Count&&movie.Gains[gain].Time<=ms)extra=movie.Gains[gain++].Steps;
   if(observe!=null&&sample%(Rate/1000)==0){int[] env=new int[4],effective=new int[4];for(int i=0;i<4;i++){env[i]=notes[i]==0?15:expressive?Envelope(preset[i],atten[i],period[i],attack[i],ms,i<3&&movie.Vibrato).Attenuation:atten[i];effective[i]=Math.Min(15,env[i]+extra[i]);}observe(new(ms,(byte[])notes.Clone(),(byte[])vel.Clone(),(int[])preset.Clone(),(int[])attack.Clone(),(byte[])extra.Clone(),env,effective,(double[])phase.Clone(),lfsr));}
   if(sample==output.Length)break;
   double mix=0;
   for(int i=0;includePsg&&i<4;i++) {
    if(notes[i]==0)continue;
    var e=expressive?Envelope(preset[i],atten[i],period[i],attack[i],ms,i<3&&movie.Vibrato):(period[i],atten[i]);
    int effective=Math.Min(15,e.Item2+extra[i]);
    double amplitude=effective==15?0:Math.Pow(10,-effective/10.0)*0.19;
    if(i<3) {phase[i]+=3579545.0/(32*e.Item1*Rate);phase[i]-=Math.Floor(phase[i]);mix+=(phase[i]<0.5?1:-1)*amplitude;}
    else {noisePhase+=3579545.0/((512<<(period[i]&3))*Rate);while(noisePhase>=1) {noisePhase--;int feedback=(period[i]&4)!=0?(lfsr^(lfsr>>1))&1:lfsr&1;lfsr=(lfsr>>1)|(feedback<<14);}mix+=((lfsr&1)!=0?1:-1)*amplitude;}
   }
   if(includePit&&pitNote!=0) {
    mix+=(pitPhase<((pitDivisor+1)/2)*(long)Rate?1:-1)*0.19;
    pitPhase=(pitPhase+PitOscillator.Clock)%(pitDivisor*(long)Rate);
   }
   while(speech<movie.Speeches.Count&&ms>=movie.Speeches[speech].End)speech++;
   if(includeSpeech&&speech<movie.Speeches.Count&&ms>=movie.Speeches[speech].Start) {var s=movie.Speeches[speech];int p=(sample-s.Start*(Rate/1000))/4;mix=(s.Samples[p]-36.5)/35.5*0.75;}
   output[sample]=(short)Math.Clamp(Math.Round(mix*32767),-32768,32767);
  }
  return output;
 }
}
public static class PitOscillator
{
 public const int Clock=1193182;
 public static readonly int[] Hertz=[110,117,123,131,139,147,156,165,175,185,196,208,220,233,247,262,277,294,311,330,349,370,392,415,440,466,494,523,554,587,622,659,698,740,784,831,880,932,988,1047,1109,1175,1245,1319,1397,1480,1568,1661,1760,1865,1976,2093];
 public static int Divisor(int note) {if(note is <45 or >96)throw new ArgumentOutOfRangeException(nameof(note));int hz=Hertz[note-45];return (Clock+hz/2)/hz;}
}
