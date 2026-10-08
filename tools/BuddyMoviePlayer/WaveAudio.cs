using System.Runtime.InteropServices;
namespace BuddyMoviePlayer;
public sealed class WaveAudio : IDisposable
{
 public const uint TimeMilliseconds=1,TimeSamples=2,TimeBytes=4;
 [StructLayout(LayoutKind.Sequential)] struct Format {public ushort Tag,Channels;public uint Rate,Bytes;public ushort Align,Bits,Extra;}
 [StructLayout(LayoutKind.Sequential)] struct Header {public IntPtr Data;public uint Length,Recorded;public UIntPtr User;public uint Flags,Loops;public IntPtr Next;public UIntPtr Reserved;}
 [StructLayout(LayoutKind.Explicit,Size=12)] struct Position {[FieldOffset(0)]public uint Type;[FieldOffset(4)]public uint Value;}
 [DllImport("winmm.dll")]static extern uint waveOutOpen(out IntPtr handle,uint device,ref Format format,IntPtr callback,IntPtr instance,uint flags);
 [DllImport("winmm.dll")]static extern uint waveOutPrepareHeader(IntPtr h,IntPtr header,uint size);
 [DllImport("winmm.dll")]static extern uint waveOutWrite(IntPtr h,IntPtr header,uint size);
 [DllImport("winmm.dll")]static extern uint waveOutReset(IntPtr h);
 [DllImport("winmm.dll")]static extern uint waveOutUnprepareHeader(IntPtr h,IntPtr header,uint size);
 [DllImport("winmm.dll")]static extern uint waveOutClose(IntPtr h);
 [DllImport("winmm.dll")]static extern uint waveOutGetPosition(IntPtr h,ref Position position,uint size);
 IntPtr handle,data,header;int start;public bool Active=>handle!=IntPtr.Zero;
 public bool Completed=>header!=IntPtr.Zero&&(Marshal.PtrToStructure<Header>(header).Flags&1)!=0;
 public (uint Type,uint Value) ReadClock() {Position p=new(){Type=TimeSamples};Check(waveOutGetPosition(handle,ref p,12));return(p.Type,p.Value);}
 static void Check(uint error) {if(error!=0)throw new IOException("Windows audio error "+error+". Check that an output device is available.");}
 public void Start(short[] samples,int ms,double volume)
 {
  Stop();start=ms;int offset=Math.Min(samples.Length,ms*(Synth.Rate/1000)),count=samples.Length-offset;if(count==0)return;
  try {
   short[] scaled=new short[count];for(int i=0;i<count;i++)scaled[i]=(short)(samples[offset+i]*volume);
   data=Marshal.AllocHGlobal(count*2);Marshal.Copy(scaled,0,data,count);
   Format f=new(){Tag=1,Channels=1,Rate=Synth.Rate,Bytes=Synth.Rate*2,Align=2,Bits=16};Check(waveOutOpen(out handle,0xffffffff,ref f,IntPtr.Zero,IntPtr.Zero,0));
   header=Marshal.AllocHGlobal(Marshal.SizeOf<Header>());Marshal.StructureToPtr(new Header{Data=data,Length=(uint)count*2},header,false);
   Check(waveOutPrepareHeader(handle,header,(uint)Marshal.SizeOf<Header>()));Check(waveOutWrite(handle,header,(uint)Marshal.SizeOf<Header>()));
  }catch {Stop();throw;}
 }
 // MMTIME TIME_SAMPLES counts PCM frames; TIME_BYTES counts bytes.
 // Mono PCM16 has two bytes per frame. These units must not be interchanged.
 public static int ToMilliseconds(uint type,uint value)=>checked((int)(type switch {
  TimeSamples=>(long)value*1000/Synth.Rate,
  TimeBytes=>(long)value*1000/(Synth.Rate*2),
  TimeMilliseconds=>(long)value,
  _=>throw new IOException("Unsupported audio clock.")
 }));
 public int Milliseconds {get {if(!Active)return start;var clock=ReadClock();return start+ToMilliseconds(clock.Type,clock.Value);}}
 public void Stop() {if(handle!=IntPtr.Zero) {waveOutReset(handle);if(header!=IntPtr.Zero)waveOutUnprepareHeader(handle,header,(uint)Marshal.SizeOf<Header>());waveOutClose(handle);handle=IntPtr.Zero;}if(header!=IntPtr.Zero){Marshal.FreeHGlobal(header);header=IntPtr.Zero;}if(data!=IntPtr.Zero){Marshal.FreeHGlobal(data);data=IntPtr.Zero;}}
 public void Dispose()=>Stop();
}
