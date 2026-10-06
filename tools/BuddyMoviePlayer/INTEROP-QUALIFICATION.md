# Production Maker interoperability — experimental x64 player

2026-10-06: 235 cross-producer/consumer checks passed. No format or semantic
interoperability gap was found; no playback source change was required.

Producer source: `e1670caa1113912eadcbeeb7179a5e6023d306e0`.
Producer DLL SHA256:
`407945708C49EE81AA5D3DF4E25FC30949A9C4C6F55DF4DE36F282684776E21E`.
All 511 app files matched the supplied producer inventory.

Consumer source: `45bc23148e862be4349ea70a6c5a76f873898219`.
Qualified EXE SHA256:
`16E636E22F2DA3992BBE93616D8E40490F083535B648D5E8B97F85454D4AC2E0`.
Exact bundled player assembly SHA256:
`E71736C653917DDB9325030E8824B635E6F7A8D3FEE3AEE7C298BCF77C429383`.

An external test harness loaded the unchanged assembly extracted from that EXE,
using .NET 8.0.31. It exercised the actual Movie, Synth, Player and WaveAudio
implementations, including WinForms rendering and real waveOut submissions.
It did not automate the EXE's native file-dialog/keyboard front door.

The production exports were synthetic PITMIX, PITSPEAK, PITEMPTY and PITREST,
each 256x160 at 4 fps, eight frames / 2,000 ms. All manifest hashes were checked.
All 49 original files and read-only input copies retained their hashes after
testing. Compiled DOS players accompanying the exports were not run in this
x64 check, and are not included in this source PR.

| Export | Verified behavior | Full playback wall time |
|---|---|---:|
| PITMIX | A/B/C, noise and PIT independently produce output; sum matches the full mix within PCM rounding; final silence | 2,078 ms |
| PITSPEAK | Exact speech PWM mapping at 300..700 ms; complete PIT guard; no stale tone restoration; current PSG/noise/PIT starts at 1,000 ms | 2,097 ms |
| PITEMPTY | Empty required PIT lane is silent while PSG plays; default-off refuses | 2,083 ms |
| PITREST | All-rest required bundle remains silent; default-off refuses; clock/end operates | 2,092 ms |

Movie and audio entry paths accepted all four exports. Each packed frame matched
its file offset. Caption boundaries were HELLO TANDY at zero, SECOND CUE at
1,000 ms and clear at 1,500 ms, including UI seeks.

Positions were monotonic; steady-region timing ratios were 1.0014..1.0154.
Pause froze the clock and released output. Replay started at zero. Seeks at
500/750/1,100/1,500/100 ms covered speech, silence, music and backward seeking;
actual submitted waveOut samples matched the timeline slice after local volume
scaling. Replacement/audio entry/close released owned output and file handles.
These production fixtures are two seconds long; the separate 60-second device
pacing evidence is in PIT-QUALIFICATION.md.

Physical Tandy/PC-speaker fidelity and human listening are unqualified. Native
file-dialog/keyboard and actual focus/session-event delivery still need manual
desktop acceptance. No private media, absolute private paths, captured audio,
compiled test harness or release binaries are included in this source PR.

The frozen fixture copy at Tests/PitContract/v1 remains identical to the Maker's
Tests/Mml3Contract/v1 contract: 362 manifest entries plus its manifest, with the
same pinned specification/manifest hashes. Keep both copies byte-identical;
do not normalize CRLF or edit intentionally malformed fixtures.
