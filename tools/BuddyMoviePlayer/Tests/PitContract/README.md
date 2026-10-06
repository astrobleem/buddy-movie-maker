# Frozen MML3 v1 player contract

MML3.md and v1/ are exact copies of the frozen Maker contract package. Do not edit canonical fixture bytes. The runner checks all 362 manifest entries by size and SHA256 before acceptance or synthesis.

Specification SHA256: C47A115B936F67C21665A5C542CF1F0B1684DEEF3809E21C21BBCFEAF2860768
Manifest SHA256: 6BCE0C757CF890154AF27B55B866CE42A0B97791F6DE1F74FFED8D26601A4861
Maker source: 280a043867ee5bbca0959ec3c4ba2029f5587758
Player baseline: 7c4a5b85b644002bb87e3526fd1f2d0a9969060e

Run the published EXE with --pit-contract-test or --pit-contract-test-headless, followed by the absolute v1 path and a new evidence folder. Keep generated evidence outside the frozen corpus. Also run --self-test and --pace-test synthetic-pit with new evidence folders.

The corpus covers 56 bundles and 112 movie/audio entry decisions. Additional checks cover disabled/unavailable refusal, all 52 canonical divisors, phase/hold/retrigger/implicit attacks, catch-up, final off, independent stream bounds and complete speech guard spans. The 17 invalid MML authoring examples belong to Maker; this player does not parse MML.

Synthesis is compared against a closed-form phase oracle. Synthetic WAV captures include separate PSG/PIT audio, all five generators and guarded speech. Device tests use actual waveOut. Deactivation, Escape and session-loss handlers are invoked as internal WinForms events; these do not prove external keyboard, focus or OS-session delivery. Complete those manually on a normal desktop.

No user movies are included. Preserve the baseline waveOut clock, legacy tests and accepted EXE.
