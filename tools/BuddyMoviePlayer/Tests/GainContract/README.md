# Frozen WZG1 revision 1 player contract

`WZG1.md` and `v1/` are exact frozen Maker inputs. Preserve their bytes. The player runner checks the specification, manifest and all 254 manifest entries before decoding.

Maker source: `b447d64ab45a016be37ca010ae6ccce3e9c13b69`.

Specification SHA256: `5B7797BB161C4D1BD4005F03FD617DFF096BBBF9EE2A16E6E700831B569612BB`.

Manifest SHA256: `8FD7091E3A3FC292EA7B531437718F752DD232EC9A36EC98B07FFA5A81C5BB6A`.

Run `--gain-contract-test <absolute v1 directory> <new evidence directory>` on the packaged EXE. The `--gain-contract-test-headless` variant omits WinForms and waveOut. Generated evidence must stay outside the canonical corpus. Also run both legacy and PIT tests, and `--pace-test synthetic-gain-pit <new evidence directory>`.

Tests cover 43 frozen bundles; video and audio entry points; independent limits; 600-second rendering; same-time WZI/attack/gain ordering; extra attenuation applied once; unchanged tone phase and noise state; gain inside the 55 ms envelope quantum; expired-envelope non-revival; cropped initial gain; producer-resolved cue handover; independent PIT and speech; and actual submitted seek/replay buffers. Internal gain deactivation, Escape and session-loss events exercise cleanup. External desktop event delivery and audible quality require manual acceptance.

This is a local experimental extension. The accepted player and public PIT draft remain unchanged. Host synthesis does not establish physical Tandy fidelity.
