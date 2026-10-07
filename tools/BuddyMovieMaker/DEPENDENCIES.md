# Build and distribution dependencies

The app uses WPF and standard .NET APIs with no third-party application NuGet
packages. The project pins Microsoft .NET/Windows Desktop runtime 8.0.31;
SDK 8.0.425 was used for the qualified Windows build. Runtime packages are
resolved through NuGet during build. No SDK/runtime binary is committed.
The self-contained build copies the packages' license and third-party notice
files into its output folder. Corresponding notice texts are also in `notices/`.

Official release metadata rechecked on 2026-10-07 confirmed runtime8.0.31 and SDK8.0.425 remain current for .NET8, and identified .NET 8 support ending
2026-11-10. The pinned build needs a supported-runtime migration before that date.
Official metadata: https://dotnetcli.blob.core.windows.net/dotnet/release-metadata/8.0/releases.json

The DOS player requires externally supplied Microsoft C 6, MASM and DDK linker
5.01.17, run in DOSBox-X. `Build.ps1`, `Tests/BuildStopKey.ps1`, and
`Tests/NoiseEngine.ps1` take an explicit `-ToolchainRoot`; none copy toolchain
files into the app or repository. This repository's GPL does not grant rights
to redistribute those proprietary prerequisites. Binary release preparation
must separately verify the legacy toolchain/runtime distribution terms.

FFmpeg and ffprobe are supplied separately and verified as paired executables.
Maker stores a successfully validated folder in per-user LocalApplicationData
settings and verifies it again on startup. Missing or invalid saved tools require
reselection; save failure leaves the current session usable. No global PATH,
automatic installer, decoder download or security-policy change is performed.
No FFmpeg binary, DLL, archive or linked-library binary is committed or bundled.
See https://ffmpeg.org/legal.html for its build-dependent license requirements.

Fixtures in `Tests/Mml2Contract` are short synthetic authored scores, compiled
WZM/WZI data, invalid-source examples and expected results. Their provenance
retains the authoritative archive hash without private paths or Library IDs.
The host suite generates video/audio during tests. No movie or user audio is
committed. Native WPF layout rendering and DOSBox-X checks do not certify
physical Tandy hardware or perceived audio quality. The Windows app is unsigned.
