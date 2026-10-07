# Local WZG1 revision 1 qualification

Experimental branch: `player-wzg1-local-20261007`, based on PIT draft head `80c6222a18b574343a2e761d96d1a256a3a45a69`. No remote publication or accepted-build replacement is part of this qualification.

Frozen Maker contract source: `b447d64ab45a016be37ca010ae6ccce3e9c13b69`. Specification and manifest pins are recorded in `Tests/GainContract/README.md`. All 254 fixture entries passed hash/size checks; all 256 frozen files, including the separate specification and manifest, retain exact hashes in Git's index. The previous 364 frozen PIT files also retain their hashes.

Qualified Windows x64 single-file EXE SHA256: `FDA4FF469A9CC070FCB141BB91245A4A6655E949D8548A768911911ACE1CB075` (161,738,237 bytes). Its extracted application DLL matches the tested build output, SHA256 `472513580B60495511018ED88FBFFEF371E1F9537233279E7D929E12EFA2CF84`. .NET 8.0.31 is bundled; no end-user runtime, Python or FFmpeg installation is required.

The exact EXE completed six suites with zero failures. PASS-line counts, including each completion line: gain full 444/headless 419; PIT full 589/headless 572; legacy full 42/headless 33. Gain coverage includes the 43 frozen decisions, both applicable entry points, full 600-second rendering, 10,000 records, causal instrument/attack/gain ordering, held fades, nonzero cropped gain, expired envelopes, owner handover, unattenuated speech, required PIT refusal, actual waveOut seek buffers and internal ownership events. Generated noise and held-fade WAVs support manual listening.

The actual waveOut timing run advanced 60,012 ms in 60,020 ms wall time (ratio 0.999867, maximum drift 23 ms). Pause, forward and backward seek, final stop and replay passed. A seek to 30 seconds advanced 4,988 ms in 5,008 ms; replay advanced 5,002 ms in 5,023 ms. The original legacy PCM hash remains `40D07E2FB0E74E0ADEA6E1483443372782A21DCBDCDB5A364E371E3C0F36CCAC`. The waveOut clock source and both previous qualified EXEs remain unchanged.

Actual pinned old x64 EXEs refused gain inputs in 118 checks. The accepted pre-PIT player was tested through its supported movie entry; the PIT player was also tested through audio entry. Frozen input hashes remained unchanged. Refusal reports come from those original EXEs, not rebuilt substitutes.

Separately supplied native Win16 evidence ZIP SHA256: `61A004A231880253C95194AC841A3BED2D68B9B166C9F7814108295BEF03A24C`. Its two pinned readers passed 42 cases and 506 assertions each, 84 cases/1,012 assertions total. Inspection confirms zero sound acquisition, music events, frames and owner after stop, plus clean cleanup. This agent did not acquire the shared DOS emulator.

Gain adds attenuation once after instrument envelope and velocity, capped at 15; it does not retrigger or modify tone phase, noise state, PIT or speech amplitude. WZV4/WZM3 and required markers fail closed; WZI bit 4 preserves required PIT even when both PIT artifacts are stripped. Owner identities are resolved by Maker before export. Cropped snapshots do not establish pre-origin envelope age or phase.

Remaining acceptance: actual native file-dialog/keyboard/focus/session delivery and human listening. Host PSG/PIT synthesis and these device submission tests do not prove physical Tandy sound fidelity. WZG Maker-production interoperability and DOS gain playback qualification belong to the coordinated producer/runtime work; this result qualifies the frozen contract and x64 consumer only. All distributed fixtures are synthetic.
