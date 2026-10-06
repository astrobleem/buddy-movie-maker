# Buddy Movie Player — Windows x64

Native Windows 10/11 x64 desktop player for Buddy movies. The downloadable
`BuddyMoviePlayer.exe` includes .NET 8.0.31; users need no Python, separate .NET
installation, FFmpeg, DOS emulator, or Tandy driver. This is the modern x64
companion to the existing **16-bit Windows 3.0** player.

Open a `.WZV` movie or `.WZM` audio score, keep its sidecars together, and press Play. Open accepts any
basename (e.g. `MOVIE.WZV` or `WEEZER.WZV`). Space toggles play/pause, Left/Right
seek five seconds, F11 toggles fullscreen, and Escape exits fullscreen. Replay
starts at zero. Volume affects this player's PCM buffer only. The player does
not modify movie files, install drivers, change system volume, or save settings.

PIT-required movies need the **PIT voice (fixed level)** checkbox enabled before
opening. It defaults off on every launch, including for all-rest PIT streams.
Disabling it stops the required bundle; playback cannot silently omit that voice.
For PIT bundles, Escape, window deactivation and Windows session changes stop
this player's output. Re-enable/resume explicitly after returning to the player.

## Supported contract

- Packed, uncompressed WZV2 video: includes legacy 64×48 at 4 fps and Maker
  256×160 at 4 fps; DOS bounds 4..320 width (multiple of four), 1..200 height,
  2/4/8 fps, at most 4,800 frames and 600 seconds. RGBI palette, high nibble first.
- WZM1: all three melodic voices (notes 45..96) and noise voice (35..81),
  velocity attenuation, note-off and explicit repeated-note retrigger flags.
- Frozen MML3 v1: WZV3 video + WZM2 music + WZP1 PIT stream + exact directory
  marker `PIT.REQ=WZP1`. Audio-only WZM2/WZP1 bundles are supported. The full
  bundle is validated before audio output: one basename, known media/required
  markers, matching durations, exact lengths, independent 10,000-record limits,
  initial time zero and final all-zero/off states. Mixed legacy/PIT versions,
  missing artifacts, unknown sidecars and malformed records fail explicitly.
- PIT is an independent fifth generator. Notes 45..96 use the canonical whole-Hz
  table and rounded 1.193182 MHz channel-2 mode-3 divisor. Odd divisors retain
  the longer high half. Equal-pitch flag 0 preserves phase; changed pitch or
  attack flag 1 resets phase immediately without an invented silence gap.
  PIT has fixed software gain and no PSG envelope or velocity.
- WZI1 engine `0x0102`: all eight WININST12 melodic presets, 55 ms attenuation
  curves, optional divider-based vibrato, program-before-note ordering and
  attack snapshots. WZI without WZM, missing required WZI, malformed/unknown
  engines, flags, programs and same-basename `.WZ*` sidecars fail before playback.
- Noise mappings follow DOSPLAY/MML2: kick 35/36 periodic E2; snare 38/40 white
  E5; hats 42/44/46 white E4; other drums white E6. Fixed noise dividers never
  borrow tone C. WZI supplies kick/snare/hat envelopes.
- Same-basename LRC captions use absolute `milliseconds|text`, with empty text
  clearing the caption. Strict ASCII, 52 characters, 256 cues. Text is shown
  uppercase in a separate band below the aspect-correct nearest-neighbor image.
- Directory-level `SPEECH.PCM` SPC1: 6 kHz PWM values 1..72, up to 16 clips / 60
  seconds total. Values convert to signed host PCM. Active/imminent score
  overlap fails explicitly instead of silently skipping speech.
- Every held PIT span must avoid the half-open 150 ms speech guard. Off exactly
  at the lower boundary and attack exactly at the upper boundary are allowed.
  No stale pre-speech tone is restored.
- CUE is validated, but this version plays the full movie. It does not expose
  a song-only CUE range. Original DOS defaults also select the full movie.

Video files are streamed. Audio is rendered once to deterministic 24 kHz mono
16-bit PCM (up to 28.8 MB for 600 seconds). Playback and seeking use Windows
waveOut's sample clock, completed-buffer flag and independently owned buffer.
Every seek restores the same timeline samples, including held-note envelopes,
program snapshots, retriggers and speech offsets. Pause/seek/open/end/close reset
and release the previous output buffer. Volume changes resume at the audio clock.

## Fidelity limits

This is a meaningful software interpretation, **not physical Tandy fidelity**.
Tone pitches use the DOS 3.579545 MHz / 32 divider table and 2 dB attenuation
steps. Noise uses a classic TI SN76489 15-bit XOR LFSR (adjacent low-bit taps),
not every later Tandy NCR/PSSJ variant. Those variants differ; see the
[MAME PSG implementation notes](https://github.com/mamedev/mame/blob/master/src/devices/sound/sn76496.cpp).
The implementation is original and does not incorporate MAME source.
Square waves/noise are sampled directly at 24 kHz without a hardware analog
filter or cycle-accurate resampler, so aliasing and phase behavior differ.
Speech converts PWM duty values into host samples, not PC-speaker pulses.
PIT mode-3 output is sampled into host PCM at a chosen fixed mix level; it does
not establish physical PC-speaker loudness, analog filtering or Tandy fidelity.
No hardware ports, PIT0/1, interrupts or shared DOS audio driver are accessed.
Unlike DOS's BIOS-tick service loop, this player preserves every score event
and continues video during speech. Captions use a host font, not CAPFONT glyphs.
No raw MIDI/MML input or generic video decoding is supported.

## Build and test

From this folder, `./Build.ps1 -Output <new-directory>` builds the self-contained
single EXE and copies licenses. The development machine needs the .NET 8 SDK
and cached/downloadable runtime 8.0.31 packages. End users do not.

Run `BuddyMoviePlayer.exe --self-test <new-evidence-directory>` for synthetic
format, synthesis, malformed input and real Windows waveOut/UI checks. It creates
synthetic movies only, a UI PNG, raw 24 kHz signed little-endian PCM, and a test
report. A nonzero process exit means failure. These tests validate output-buffer
submission and device-clock behavior; they do not establish what a listener
hears or physical hardware sound quality. Interactive testing of Open's file
dialog and keyboard shortcuts remains a manual check.

CI runs `--self-test-headless <new-evidence-directory>` to exercise format and
synthesis checks without requiring an interactive desktop or audio device.
This mode omits the WinForms/waveOut integration checks; it does not replace
the full local test or manual UI/listening acceptance.

`BuddyMoviePlayer.exe --pace-test synthetic <new-evidence-directory>` runs a
60-second wall-clock comparison through the real player and audio device, plus
timed pause, seek, backward seek, end and replay checks. It generates a 72-second
movie and CSV clock observations. Replace `synthetic` with a local WZV path to
test an existing movie (at least 30.5 seconds long); it never copies that media.
This audio-device check is separate from headless CI.

`--pit-contract-test <Tests/PitContract/v1> <new-evidence-directory>` verifies
the frozen hashes, 112 movie/audio acceptance decisions, 52 pitch divisors,
phase/attack semantics, speech guards, five independent generators and real
waveOut/internal WinForms lifecycle paths. `--pit-contract-test-headless` omits
device/UI checks. These commands do not parse the Maker's MML source examples.
`--pace-test synthetic-pit <new-evidence-directory>` measures 60 seconds of
PIT plus three melodic PSG voices and noise. Generated synthetic WAV captures
support listening review; device submission tests cannot prove audible quality.
Actual file-dialog, keyboard, focus-loss and OS session-event behavior still
requires manual desktop acceptance.

The PIT contract is frozen Maker commit `280a043867ee5bbca0959ec3c4ba2029f5587758`,
spec SHA256 `C47A115B936F67C21665A5C542CF1F0B1684DEEF3809E21C21BBCFEAF2860768`.
The pre-PIT player baseline is PR head `7c4a5b85b644002bb87e3526fd1f2d0a9969060e`.

Source baseline: public `astrobleem/buddy-movie-maker` commit
`6567a4de9ccccc29de7e0c6ba1b75407195b1305`. Contract references:
`tools/BuddyMovieMaker/Runtime/DOSPLAY.C`, `INSTR.C`, `PERIODS.H`, `CAPTION.C`,
`HARDWARE.ASM`, `SpeechAudio.cs`, `MML1.md`, `MML2.md`. Legacy compatibility was
also checked against `examples/BUDDY/WIN30/source/TINYVID.C` in the read-only
upstream oemsound-tandy checkout (not distributed here).

No user movies or copyrighted media are distributed. The repository's GPL
license applies to the player; bundled .NET licenses/notices accompany builds.
