# Buddy Movie Maker

A Windows desktop app that turns local video into a ready-to-copy Tandy DOS
movie folder. Native WPF UI, exact-pixel 16-color preview, source start/end
selection, optional authored MIDI or MML music, captions, and timed digital speech.

The current app targets **Windows 10/11 x64**. A portable converter/CLI is a
possible future extraction; Linux/macOS support is not implemented or tested.
There is no automatic soundtrack-to-PSG transcription. Windows preview is silent.

## Use

1. Build the app, then run `BuddyMovieMaker.exe` from its complete output folder.
2. Select an existing `ffmpeg.exe` with `ffprobe.exe` beside it. Maker remembers
   the validated folder for your Windows user and checks it on subsequent launches.
3. Choose a video and source start/end in seconds. Blank end means EOF.
   Export selections are limited to 600 seconds at 256x160 and 4 fps.
4. Optionally add MIDI **or** MML, captions, and speech clips. These separate
   tracks use output movie-relative time zero, regardless of source start.
5. Build the preview, then export to a **new** folder. Manually copy the complete
   exported folder to your Tandy 1000 running DOS 3+ and run `PLAY.BAT`.

Original media and existing exports are preserved. Maker does not access CF cards.
Built Windows packages include .NET and need no Python or separate .NET install.
FFmpeg is supplied separately; this source repository includes no release binaries.
See the [full guide](tools/BuddyMovieMaker/README.md) for exact profiles and limits.

## Windows x64 playback

The [Buddy Movie Player](tools/BuddyMoviePlayer/README.md) opens exported Buddy
movies on Windows 10/11 x64, including legacy 64x48 and Maker 256x160 WZV2 files.
It supports WZM/WZI music, captions and timed speech, with play/pause, seeking,
replay, volume and fullscreen. Its self-contained EXE requires no separate .NET,
Python, FFmpeg or DOS installation. Build it separately with
`tools/BuddyMoviePlayer/Build.ps1 -Output <new-directory>`.

This is the modern **64-bit** companion to the original **16-bit Windows 3.0**
player listed in oemsound-tandy. Host PSG synthesis follows the format's score
and instrument semantics; physical Tandy sound fidelity is not certified.

## Build and test

Prerequisites: Windows x64, PowerShell, .NET SDK 8.0.425 (tested), DOSBox-X, and a
separately supplied, appropriately licensed Microsoft C 6/MASM/DDK linker toolchain.
The toolchain root must contain `BIN/CL.EXE`, `BIN/MASM.EXE`, `INCLUDE/`, `LIB/`,
and `DDK/286/TOOLS/LINK4.EXE` (5.01.17 tested). These proprietary tools are not
included. Runtime source uses C89, 8086 instructions and the small memory model.

```powershell
.\tools\BuddyMovieMaker\Build.ps1 -ToolchainRoot C:\path\dos-toolchain `
  -Output C:\path\new-build
# Optional: -Dotnet C:\path\sdk\dotnet.exe -Dosbox C:\path\dosbox-x.exe
Start-Process C:\path\new-build\BuddyMovieMaker\BuddyMovieMaker.exe `
  -ArgumentList '--self-test','C:\path\new-tests','C:\path\ffmpeg\bin' -Wait
.\tools\BuddyMovieMaker\Tests\CheckMml1.ps1 `
  -Fixtures C:\path\new-tests\MML-CONFORMANCE
.\tools\BuddyMovieMaker\Tests\Emulator.ps1 `
  -Fixtures C:\path\new-tests -Output C:\path\new-dos-tests
```

Use new output directories. Self-tests generate synthetic video/audio and authored
scores/captions; no movie assets are included. Settings checks close and relaunch
the actual app with isolated test settings. Additional speech/noise qualification
commands are in the full guide. Emulator tests do not certify physical hardware,
perceived audio quality, or a calibrated 4.77 MHz 8088.

## License and origin

Source is provided under [GNU GPL version 3](LICENSE), preserving the upstream
project license. It was extracted from
[astrobleem/oemsound-tandy](https://github.com/astrobleem/oemsound-tandy), including
the generic BUDCAP-derived player and original WININST12 instrument curves.
See [NOTICE.md](NOTICE.md) and [dependency details](tools/BuddyMovieMaker/DEPENDENCIES.md).
No Buddy movie assets, user media, SDK/compiler binaries, FFmpeg binaries, private
settings, or previous project history are included.
