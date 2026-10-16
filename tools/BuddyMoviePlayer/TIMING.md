# Playback timing and output ownership

Source audit: 2026-10-16, after integrating PRs #1, #2 and #3.

## Windows x64 player in this repository

`Movie.cs` reads bounded WZV2/WZM1/WZI1 bundles and explicitly enabled
WZV3/WZM2/WZP1 bundles, captions and SPC1 speech. `Synth.Render` renders the
entire timeline to 24,000 Hz mono PCM16 before playback. Score and PIT changes
use movie-relative integer milliseconds (24 samples per millisecond). The
55 ms envelope/vibrato steps emulate the existing instrument engine; they are
PCM synthesis semantics, not a Windows timer dispatch interval.

`WaveAudio` owns one waveOut device and one submitted buffer for the remaining
timeline. `waveOutGetPosition` is the playback master clock: TIME_SAMPLES counts
PCM frames; TIME_BYTES counts bytes, with two bytes per mono PCM16 frame.
`start` adds the seek offset. Pause captures that clock and resets/closes output;
seek, volume changes and replay submit a fresh buffer. Disposal and PIT loss
handlers release this player's output. No direct PSG/PIT port writes, shared
SOUND lease, MIDI driver or shared MIDI event queue are used here.

The 25 ms WinForms timer samples device progress for display. Video is selected
from current audio time, and a bitmap is rebuilt only when the frame changes.
Late UI dispatch can skip pictures; it does not delay or collapse audio events
already rendered in PCM. Captions and the seek control follow the same clock.
Keep this device clock when improving drawing or UI responsiveness. A second
MIDI/PIT timer would not improve this playback path.

Playback needs Windows 10/11 x64, the self-contained app and its complete media
bundle, plus an available Windows waveOut device. New builds embed runtime
8.0.32. No FFmpeg, separate .NET installation, DOS emulator or Tandy driver is
needed by this player. WZG1 gain bundles are deliberately refused; their x64
support is not part of these PRs. Full CUE-range playback is also not exposed.

## Maker and DOS exports in this repository

Maker's WPF preview is silent. Its 250 ms DispatcherTimer advances preview
frames; `MidiScore` parses SMF format 0/1 with PPQN and writes deterministic
millisecond WZM events during export. It does not play or enqueue live MIDI.
Conversion needs separately supplied paired FFmpeg/ffprobe executables.

Exported DOS playback uses the bundled runtime selected by format: legacy,
MML3/PIT, or qualified WZG1 gain. `ClockTick` reads BIOS time; movie scheduling
uses approximately 54.925 ms ticks and instrument updates use 55 ms quanta.
The DOS MML3/gain adapters own cooperative foreground PSG/PIT/PWM output;
sampled speech takes speaker ownership temporarily, then the runtime evaluates
current movie time before resuming tones. These are DOS paths, not clients of
the shared Windows MIDI scheduler. A Windows MIDI driver update cannot change
their timing. Native DOS timing changes require separate runtime qualification.

Builds require an external licensed MSC6/MASM/DDK linker toolchain and DOSBox-X
for DOS binaries, plus the .NET SDK for Windows apps. Respect the shared emulator
lease before building or testing DOS components; the 2026-10-16 merge audit did
not start an emulator. No CF card or media assets were modified.

## Upstream Win16 Buddy: integration still required

This source is maintained outside this repository. The audit checked
[TINYVID.C at upstream commit ebcfe32](https://github.com/astrobleem/oemsound-tandy/blob/ebcfe32a0881dde617157392f4c418714fb9f66a/examples/BUDDY/WIN30/source/TINYVID.C).
That revision uses `SetTimer(window,1,55,NULL)` and `GetTickCount` for its movie
clock. `updateMusic` consumes all due WZM snapshots but applies only the last,
incrementing `skippedEvents` for the others. It sends immediate `MODM_DATA`
note-off/note-on messages through `MIDIMESSAGE`, with zero timestamp parameter.
It does not submit timestamped lookahead events. Video file reads and GDI draws
run in the same foreground callback between music updates. A local later PIT
handoff preserves more attacks, but it is not this upstream main revision.

A faster shared driver alone cannot recover events already collapsed or sent
late by this client. The Win16 client needs an agreed backend contract before
integration:

- One backend-owned clock in milliseconds shared by event deadlines and movie
  position, with documented epoch and wrap behavior.
- Bounded timestamped lookahead submission with capacity/backpressure handling;
  preserve every attack and same-time ordering (offs before ons). Do not assume
  a queue slot represents an entire four-voice WZM snapshot.
- Reset/flush acknowledgement on pause, seek, replay, focus/session loss, error
  and close, so stale queued attacks cannot survive a timeline change.
- Reconstruction of current score/instrument/PIT state after seeking, followed
  by a fresh clock origin and queue fill, under the existing exclusive SOUND
  owner. No parallel direct PSG writes or competing PIT owner.
- Refill audio before potentially slow file reads/GDI work; display frames and
  captions from the backend master time and drop late pictures independently.

The shared Windows timing implementation is developed separately. This audit
does not invent new exported API names or modify that backend or upstream
Win16 source. Queue timing, capacity and flush behavior must be verified against
its final contract before client code or timing guarantees are changed.

## Validation and remaining limits

The merged x64 source passed self-contained publication, legacy and PIT headless
format/synthesis checks, real waveOut/internal WinForms lifecycle checks, and a
synthetic PIT pacing run: 59,983 ms advance in 60,014 ms wall time, monotonic,
maximum drift 52 ms; pause, both seek directions, end and replay passed.
Maker passed frozen MML3/compiler, WZG1 corpus and MIDI drum checks. Subsequent
runtime patch builds must rerun these checks; historical qualification files
continue to identify the earlier binaries they actually tested.

Native dialogs/keyboard/focus/session delivery, human listening and physical
Tandy fidelity remain separate acceptance work. Internal handler tests and
host PCM tests do not certify those behaviors or DOS hardware timing.
