# Buddy Movie Maker — Windows local preview

Native WPF desktop app for Windows 10/11 x64. The self-contained folder includes
.NET 8.0.31 and a separately built DOS player. It does not require Python
or a separate .NET installation. FFmpeg is **not included**. You need an existing
local Windows x64 FFmpeg distribution containing `ffmpeg.exe` and `ffprobe.exe`.
Run `BuddyMovieMaker.exe` from the extracted folder; keep `runtime/` and
`runtime-mml3/` beside it.

## Make a movie

1. Click **Choose existing FFmpeg** and select `ffmpeg.exe`. The app checks both
   tools in that folder. Choose a local video with a known positive duration.
   After successful validation, the folder is remembered for your Windows user
   in `%LOCALAPPDATA%\BuddyMovieMaker\settings.json`. On later launches Maker
   verifies both tools again. If they have moved or settings cannot be read,
   choose **Choose existing FFmpeg** again; the app remains usable. A save
   failure keeps the validated decoder available for the current session and
   reports that you will need to select it again next time. Older builds ignore
   this settings file. No PATH or machine-wide settings are changed.
   Longer source videos are supported: set **Start (s)** and **End (s)** to
   select at most 600 seconds. Use decimal seconds, for example `12.5`.
   A blank end means the end of the source; the default start is `0`.
   The selected duration and frame count appear before preview/export.
2. Optionally choose an authored MIDI or MML score, captions, and timed audio clips.
3. Build the preview, scrub or play the converted frames.
4. Export to a **new folder name**. Copy that entire folder to your Tandy later.
   The app does not find, mount, or write CF cards.
5. On a Tandy 1000 with DOS 3+, exit Windows and run `PLAY.BAT`.
   Escape/Space stops. Run PLAY again to restart.

Only local decoding occurs. Original video audio is deliberately omitted; the
app does not transcribe an audio soundtrack into PSG music. The preview plays
video frames only, without synthesized music or speech audio. Caption cue text appears
below the preview; the DOS player draws its own bitmap font in the bottom strip.

Start/end times refer to the original video. Separate MIDI/MML, captions and
speech use **output movie-relative time zero**, regardless of source start.
They are validated against the selected duration; they are not automatically
cropped or shifted. For example, selecting source seconds `20` through `22`
exports a two-second movie; caption `0|HELLO` appears at its opening and a
speech start of `300` means 300 ms into that exported movie. Changing the range
clears the previous preview. Conversion uses accurate input seeking and resets
the selected video timestamps; source frame timing and the 4 fps cadence may
round fractional boundaries. The output manifest records the exact source range.
Source media and existing exports are never edited or overwritten.

## Exact profile and limits

- First video stream, fixed 256×160, 4 fps, FFmpeg area scaling (stretches the
  source to this shape), standard 16-color IBM/Tandy RGBI, no dithering.
- Nearest squared RGB quantization, first palette index wins ties. This native
  quantizer is deterministic but is **not a byte-for-byte replacement for
  Pillow's internal palette lookup** in the older Buddy converter.
- Preview decodes the same packed WZV2 bytes that export generates. Frame `n`
  starts at `n × 250 ms`. Up to 2 final frames may repeat to reconcile duration
  rounding; larger decoder/duration discrepancies are errors.
- 1–2,400 frames; each frame 20,480 bytes; WZV2 header 24 bytes. Maximum video
  file: 49,152,024 bytes (~46.875 MiB). Runtime accepts broader legacy profiles,
  but Maker emits this one profile only.
- MIDI format 0/1, PPQN, 1–64 tracks, ≤4 MiB, ≤100,000 parsed relevant events,
  ≤10,000 exported states. Melodic notes must be 45–96. Three melodic PSG voices;
  highest velocity wins excess polyphony, with channel/note/track tie order.
  Sustain and channel all-notes-off are supported. GM channel 10 keys35..81 use
  one fixed-noise lane; unknown drum keys refuse before export. Noise collisions
  and GM timbre reductions are reported in MIDI-REPORT.JSON; losing hits are
  never queued or replayed later. Programs, pitch bend, expression and other
  ignored messages are counted. Same-note overlap within one track/channel
  collapses to one note; different tracks keep separate note ownership.
  No MIDI synthesis in the Windows preview. See [MIDI-DRUMS.md](MIDI-DRUMS.md).
- MIDI timeline (including end-of-track) must fit video, with 250 ms tolerance
  for rounding. It starts at movie time zero. A shorter score becomes silent
  after its note-offs; cleanup always mutes PSG at movie end. All exported WZM
  files declare exactly the video duration.
- Captions are UTF-8 `milliseconds|text`, strictly increasing times within the
  video, at most 256 cues and 52 characters/cue. Empty text clears the strip.
  Lowercase becomes uppercase; supported output characters are ASCII 32–90.
  Blank lines and `#` comments are ignored. Maximum input file 24,000 bytes.
  No SRT, lyric extraction, automatic wrapping or subtitle OCR.
- Empty optional music/caption/speech inputs are supported.
- PSG/rendering timing remains BIOS-tick based; preview is not an electrical,
  cycle-accurate or perceived-audio reproduction. Physical hardware untested.

## MML and timed speech

MML3 accepts a first-line `MML3` declaration and an optional fifth `[P]` part for
PC-speaker pitches 45..96 and `V0`/`V1`. See the frozen [MML3.md](MML3.md) contract.
Without `[P]`, export retains WZV2/WZM1 and the unchanged legacy DOS player.
Explicit `[P]`, including empty or all-rest parts, requires the **Enable required
MML3 [P] PC-speaker voice** checkbox, which starts unchecked. Preview stays silent
and identifies the required lane. The qualified package exports WZV3/WZM2/WZP1,
`PIT.REQ`, WZI1/`INST.REQ` and the new player together. `PLAY.BAT` passes `/P`;
direct `MOVPLAY` launch refuses a required voice without that switch. Missing
runtime capability also refuses export before creating its destination.

The DOS adapter controls one cooperative foreground player. Use a controlled
DOS session with no other sound/timer writers; it cannot exclude arbitrary TSRs,
BIOS beeps or unrelated direct-port programs. It refuses Windows and an already
active speaker before output writes. PSG and PIT rest throughout each guarded
speech interval. PWM temporarily owns the speaker; resume evaluates current
movie time rather than restoring a saved pitch. Stop/error/exit releases owned
output. No resident component, driver installation or system-beep interception
is added. Native tests cover the actual Windows3 real-mode DOS-child refusal;
other Windows modes and physical hardware remain unverified.

MML1 accepts three parts `[A]`, `[B]`, `[C]`, notes/rests, tempo/octave/length/
volume, bounded repeats and eight original WININST12 presets. Choose an initial
preset and optional eligible-preset vibrato; explicit `@` commands override it.
See [MML1.md](MML1.md) for exact syntax, timing, limits and shared conformance.
Tone-only MIDI keeps the established plain PSG mapping. MIDI with drums uses
constant Organ tones plus original WININST12 noise envelopes and the qualified
sound-owned player. MML uses the original WININST12 55 ms envelope engine.
A later preset command does not change a held note. Cue-scoped held-note fades
are modeled separately and are not exported until consumers agree a gain stream.

Add local WAV/MP3/FLAC/OGG/M4A/AAC clips and edit their start times in milliseconds.
Maximum 16 clips, 8 seconds each, 60 seconds total, 64 MiB per source file.
Audio becomes mono 6 kHz PC-speaker PWM using the existing proven playback path.
Late service skips leading speech samples to preserve the timeline; the slow
guest fixture started 84 ms late (504 of 2,400 samples skipped). Playback
quality and timing are therefore approximate. Clips must fit the video, remain
at least 150 ms apart, and fall in logical PSG (and required PIT)
rests with 150 ms guards before and after. Conflicting music is rejected.
There is no TTS or automatic soundtrack transcription. Video holds during each
clip and catches up afterward while the movie clock continues. Captions update
at clip boundaries. Physical PC-speaker sound quality remains untested.

## MML2 drums

Use the explicit first nonblank/noncomment line `MML2` to add optional `[N]`.
In that lane, write `N35` with the current length, or `N38/16.` with an explicit
(dotted) length. Codes35..81 map to original Kick/Snare/Hat fixed PSG noise.
T/L/V, R and bounded repeats work; O, melodic notes and @ presets are errors.
`V0` rests. Equal hits retrigger the shift register. Noise never borrows or
retunes tone C; selectors3/E3/E7 are not used. @HIT stays a melodic preset.
See [MML2.md](MML2.md) for the authoritative shared revision1 contract.

The existing WZM1/WZI1 formats and INST.REQ marker are unchanged. The new
MOVPLAY supports their fourth-slot noise with the original WININST12 curves.
Older Maker parsers reject MML2 text and older expressive players reject these
noise records; keep the newly exported player in every updated movie folder.
MML1 songs remain byte-compatible. MIDI percussion uses the same map. Logical
noise must rest throughout the same150ms speech guards even after its envelope
has self-expired. The Windows preview remains silent.

## Export contents

`MOVPLAY.EXE`, `MOVIE.WZV`, `MOVIE.CUE`, `MOVIE.LRC` (possibly empty),
optional `MOVIE.WZM`, MML-only `MOVIE.WZI` + `INST.REQ`, optional `SPEECH.PCM`,
`PLAY.BAT`, `README.TXT`, `MANIFEST.JSON`.
Required MML3 PIT movies also contain `MOVIE.WZP` and `PIT.REQ`.
All guest names are DOS 8.3. The manifest records the conversion profile,
duration, frame count, optional-track status and SHA-256 of exported files.
The generic player uses these filenames and no fixed Buddy speech windows.
The old Buddy player, assets, converters and builds are unchanged.

Exports stage in a randomly named sibling directory and publish by rename.
Existing files/folders are rejected; failed/cancelled jobs remove staging;
the same destination can be retried. Cancel after successful publication cannot
undo a completed export. Closing while busy requests cancellation first.

## Developer build and tests

Requires serviced .NET 8 SDK (8.0.425 tested), DOSBox-X and a separately supplied MSC6/MASM/DDK linker
toolchain. The source app has no third-party NuGet package dependencies.
`Build.ps1` pins the serviced Microsoft runtime in the project; it installs
nothing and does not download or copy a decoder into the deliverable.

```powershell
.\tools\BuddyMovieMaker\Build.ps1 -ToolchainRoot C:\path\dos-toolchain -Output C:\path\new-build
# Optional portable SDK: add -Dotnet C:\path\sdk\dotnet.exe
# Concurrent workers must all pass -EmulatorLock C:\path\shared-emulator.lock.
# Self-test uses only a synthetic FFmpeg pattern, tiny authored MIDI/captions.
Start-Process C:\path\new-build\BuddyMovieMaker\BuddyMovieMaker.exe `
  -ArgumentList '--self-test','C:\path\new-test-output','C:\path\existing-ffmpeg\bin' -Wait
.\tools\BuddyMovieMaker\Tests\Emulator.ps1 `
  -Fixtures C:\path\new-test-output -Output C:\path\new-emulator-output
```

Self-test output must be new. Tests cover validation, silent/scored export,
packed-preview identity, no-overwrite, cancellation/retry and cleanup.
Emulator tests cover silent/scored playback, truncated WZV, mismatched score
duration, malformed caption fallback and complete replay. They assert return to
DOS, restored video mode, silent PSG/speaker and expected event/frame counts.
Enhanced tests cover speech-only, MIDI/MML musical rests, malformed speech and
instrument data, required-sidecar enforcement, held-preset snapshots, Escape
inside PWM and replay. Build the test-only injector and run the additional suite:

```powershell
.\tools\BuddyMovieMaker\Tests\BuildStopKey.ps1 -ToolchainRoot C:\path\dos-toolchain -Output C:\path\new-helper
.\tools\BuddyMovieMaker\Tests\Enhanced.ps1 -Fixtures C:\path\new-test-output `
  -Output C:\path\new-enhanced-tests -StopKey C:\path\new-helper\STOPKEY.EXE -Cycles 3000
# Repeat with a new Output and -Cycles 240 for a deliberately slow guest.
```

The injector stays in disposable DOSBox guests; it is never shipped in runtime/.
Cycle budgets are emulator stress settings, not a calibrated 4.77 MHz 8088.
These tests do not certify perceived audio or real hardware.

MML3 builds both isolated runtimes. A `Tests/QualifiedMml3Runtime.json` receipt
must match the newly built MML3 executable and accepted native test counts before
Build creates its `MML3.CAP` capability file. A missing receipt leaves PIT export
disabled; a mismatched receipt fails the build. Do not copy a capability marker
onto another executable. The reviewed adapter source and cooperative-session
scope are documented in `RuntimeMml3/ADAPTER.md` in source and
`runtime-mml3/ADAPTER.md` in the packaged app.

```powershell
.\tools\BuddyMovieMaker\Tests\CheckMml3Compiler.ps1 `
  -Assembly C:\path\new-build\BuddyMovieMaker\BuddyMovieMaker.dll `
  -Output C:\path\new-compiler-report.json
.\tools\BuddyMovieMaker\Tests\Mml3Runtime.ps1 `
  -Runtime C:\path\new-build\dos-mml3\MOVPLAY.EXE `
  -Output C:\path\new-mml3-runtime-tests -Lock C:\path\shared-emulator.lock
```

The MML3 suite checks all 56 frozen bundles in enabled/disabled movie/audio modes
(224 decisions). Advanced tests cover actual Maker exports and speech, Escape,
replay, an already busy speaker, the maximum 600-second container and held-note
late seek. Those timing checks play the final second and a half-second range;
the separate full-length test plays all 600 seconds. On 2026-10-06 it completed
in 601.664 wall seconds with all 2,400 frames rendered, zero frame drops and
all eight PIT records applied. Speech at 596.3 seconds began 20 ms late and
skipped 120 elapsed samples; final PSG/PIT notes and cleanup completed. This
attests DOSBox-X normal/8086_prefetch, Tandy, 640 KiB and fixed 3,000 cycles,
not calibrated physical hardware speed. The full run disables host sound;
captured independent SPKR and TANDY tracks from separate short tests verify
emulator output. Physical audio and human listening remain unverified.

```powershell
.\tools\BuddyMovieMaker\Tests\Mml3FullLength.ps1 `
  -Assembly C:\path\new-build\BuddyMovieMaker\BuddyMovieMaker.dll `
  -Runtime C:\path\new-build\dos-mml3\MOVPLAY.EXE `
  -Speech C:\path\host-tests\PITSPEAK\SPEECH.PCM `
  -Output C:\path\new-full-length-tests -Lock C:\path\shared-emulator.lock
```

This generated fixture takes about ten minutes, holds the shared emulator lock,
and bounds its own emulator process at 750 seconds. Use the generated qualified
400 ms/2,400-sample speech fixture; no user media is required.

Noise qualification additionally uses the six shared MML2 binary fixtures and
thirteen invalid-source fixtures, plus all47 hardware mappings, repeated-hit
reset, original envelope expiry, third-tone isolation, direct late catch-up,
noise/speech rest and conflict, Escape during music/PWM, replay and malformed
noise data. Run the test-only engine harness and exported-player suite:

```powershell
.\tools\BuddyMovieMaker\Tests\NoiseEngine.ps1 -ToolchainRoot C:\path\dos-toolchain -Output C:\path\new-noise-engine
.\tools\BuddyMovieMaker\Tests\NoiseRuntime.ps1 -Fixtures C:\path\host-tests `
  -Output C:\path\new-noise-runtime -StopKey C:\path\helper\STOPKEY.EXE `
  -NoiseKey C:\path\new-noise-engine\NOISEKEY.EXE -Cycles 3000
# Repeat NoiseRuntime with a new Output and -Cycles 240.
.\tools\BuddyMovieMaker\Tests\CheckMml1.ps1 -Fixtures C:\path\host-tests\MML-CONFORMANCE
```

The harness invokes production C functions and actual PSG output in disposable
DOSBox guests. Test injectors/harness executables are not app runtime files.

## Distribution status

This is a qualified **decoder-free experimental test build**. See
[DEPENDENCIES.md](DEPENDENCIES.md) for provenance, notices and licensing.
The executable is unsigned; respect Windows security warnings. The package
does not contain FFmpeg binaries, so it does not redistribute that dependency.
The prerequisite trades the original one-folder experience for a responsible
deliverable without an incomplete FFmpeg corresponding-source bundle.

The source PR's Windows CI compiles the self-contained Maker and checks the
frozen contract plus production compiler; it does not build or certify the DOS
player, install a proprietary toolchain, run the native UI, or publish binaries.
The native DOS and host-export qualification above is separate local evidence.
End-to-end manual media-dialog, keyboard and focus acceptance remains pending;
automated host tests and WPF screenshots do not qualify every desktop UI path.
