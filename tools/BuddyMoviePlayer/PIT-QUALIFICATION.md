# Windows x64 PIT qualification — 2026-10-06

Local candidate: `BuddyMoviePlayer-PIT-x64-20261006-02/BuddyMoviePlayer.exe`.
SHA256: `16E636E22F2DA3992BBE93616D8E40490F083535B648D5E8B97F85454D4AC2E0`.
Self-contained Windows x64 apphost (PE machine 0x8664), .NET 8.0.31. No end-user
Python, .NET installation or FFmpeg prerequisite.

Player baseline is PR head `7c4a5b85b644002bb87e3526fd1f2d0a9969060e`.
Frozen Maker source is `280a043867ee5bbca0959ec3c4ba2029f5587758`.
The contract ZIP SHA256 is
`B49E61ADB364DFD7DFC7AA1FB319C266AEBF3C96BD0B5EFC82954D9245EE4275`.
Specification and manifest hashes are pinned in Tests/PitContract/README.md.
All 362 manifest entries remained unchanged after tests. All 364 frozen files
(entries, manifest and spec) retain exact SHA256 values in the Git index;
scoped .gitattributes prevents line-ending conversion of those files.

## Published EXE evidence

All commands exited zero. Reports and synthetic captures accompany the local
build under Evidence; the source workspace keeps the full generated observations.

| Check | Result |
|---|---|
| Full PIT contract | 589 PASS lines including completion; all 112 movie/audio decisions match |
| Headless PIT contract | 572 PASS lines including completion |
| Legacy full/headless | Existing 41/32 checks plus completion pass |
| Pitch | All 52 canonical whole-Hz entries/divisors match |
| Semantics | Independent phase oracle matches every valid PIT corpus case: hold, repeat, implicit attack, catch-up, rest and guarded speech |
| Five generators | Separate A/B/C/noise/PIT captures each produce output; sum matches the full mix within integer rounding |
| Runtime refusal | Default off; disabled/unavailable required PIT including all-rest refuses before output |
| Owned output | Actual waveOut open, disable, resume, seek, end, replay, audio-only, replacement/error and close checks pass |
| Internal events | Deactivation, Escape and session-loss handlers stop and release waveOut |
| Pacing | 59,897 ms advance / 60,001 ms wall; ratio 0.998267; monotonic; maximum drift 123 ms |
| Timed lifecycle | Pause frozen; forward/backward seek and replay ratios 0.97985/0.98005/0.98221; end stops at 72,000 ms in 1,083 ms |

The corrected WaveAudio clock source is unchanged. Legacy synthetic PCM SHA256
is `40D07E2FB0E74E0ADEA6E1483443372782A21DCBDCDB5A364E371E3C0F36CCAC`,
byte-identical to the previously qualified realtime-fix build.
The accepted baseline EXE remains unchanged, SHA256
`977444C16D33CA0741E5C7F462D0CDE642A4BA9E54C000716D3AA3A05AC160F1`.

## Limits and remaining acceptance

This establishes parsing, deterministic host PCM, device submission/clock and
internal WinForms behavior. It does not establish physical Tandy/PC-speaker
fidelity, hardware amplitude or audible quality. PIT uses a fixed software mix
level, integer mode-3 phase and direct 24 kHz sampling; host aliasing/filtering
and legacy PSG/noise limitations remain documented in README.md.

The available desktop automation environment could not produce reliable native
focus events. The deactivation/Escape/session handlers were invoked internally;
manual desktop verification of actual focus/session delivery, dialog cancel,
keyboard shortcuts and listening remains required. No global audio/settings,
raw ports, DOS driver, PIT0/1, IRQ or security changes were made.

The player does not parse MML; the corpus's 17 invalid MML authoring sources are
Maker checks. No new remote write, PR promotion, merge or Cloudflare action was
performed for this PIT candidate. The previous public draft player PR remains
the approved baseline. Publication/integration is coordinated by the parent.
