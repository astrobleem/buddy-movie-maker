# Shared MML3 / PIT movie contract, revision 1

Status: frozen interchange contract for Maker, native Fiddle/Beats and Buddy
players. This document approves bytes and semantics, not a hardware ownership
implementation. Existing MML1 revision 2 and MML2 revision 1 remain unchanged.
The independent conformance corpus is `Tests/Mml3Contract/v1/`; its manifest
pins every fixture and this specification. No existing runtime is promoted by
this contract. DOS Windows-child refusal/ownership must be qualified separately.

## Source and authoring opt-in

`MML3` is the first nonblank, noncomment standalone line, case insensitive.
ASCII, no BOM, semicolon comments and existing whitespace rules are unchanged.
Sections `[A]`, `[B]`, `[C]`, `[N]` retain complete MML2 semantics; optional `[P]`
is a fifth, independent monophonic PIT voice. Duplicate sections are errors.
Explicit `[P]` is authoring opt-in, even if empty or all-rest. At least one
note/rest must advance the overall score, as in MML1/2. Missing sections are silent.

`[P]` resets defaults to `T120 O4 L4 V1`. It accepts melodic notes/accidentals,
rests, lengths/dots, octave changes, tempo and bounded repeats from MML1.
Emitted pitch is MIDI 45..96. V accepts only 0/1; V0 consumes rest time.
Presets, envelopes, pitch bend, ties and other volume values are errors in P.
Fixed hardware level is binary on/off; software mix gain is not hardware volume.

PPQN96, carried rational timing and half-up rounding are exactly MML1 rules.
Parts keep independent clocks/defaults/remainders. Bounds remain 8192 source
bytes, 32768 expanded tokens shared across all five parts, 4096 notes/rests
per part, and 600 seconds. Maker's existing trailing 250ms allowance may clip
only a final note/rest; no new attack or command is allowed at/after movie end.
All sidecars declare the exact output movie duration; times are output-relative
zero, irrespective of the original video's selected start.

Record limits are **10000 per stream independently**: WZM, WZI and WZP.
There is no additional aggregate union-of-timestamps limit. Writers/readers must
bound each stream before allocation and use checked file-length arithmetic.

## Required version gates and bundle naming

MML1/2 export their original WZV2/WZM1/WZI1 bytes unchanged. MML3 without P may
use WZV2/WZM1 with the existing instrument/noise rules.

Any explicit P section emits a PIT-required bundle, including an all-rest P:

- Movie video: WZV3, same 24-byte header and packed RGBI frames as WZV2; only
  the four-byte magic changes. Existing dimensions/fps/frame/duration bounds stay.
- Music: matching-basename WZM2, mandatory even if every PSG voice is silent.
- PIT: matching-basename WZP1, mandatory.
- `PIT.REQ`: exactly four ASCII bytes `WZP1`, no BOM/newline/trailing data.
- MML authoring exports retain WZI1 plus exact `INST.REQ=WZI1`, as existing
  Maker MML exports do. P itself has no preset or WZI field.

New movie loaders require WZV3/WZM2/WZP1 with identical positive duration.
An audio-only score loader may omit video but must enforce WZM2/WZP1/PIT.REQ;
any video present must be WZV3 and match duration. Old audio-only readers reject
WZM2 even though they skip video, and old video readers reject WZV3. Do not
claim that an unchanged WZM1 stream or a marker alone gates old audio players.

Reject WZV2 plus WZM2 or either PIT artifact; reject WZM1 plus either PIT artifact;
reject WZV3 plus WZM1, missing required files or invalid required markers.
The original WZI1 engine/flags and INST.REQ rules stay unchanged.

PIT.REQ is directory-scoped: a marked directory contains exactly one bundle
basename among all `.WZ*` files. Their basename equals the selected movie/score
basename, compared case-insensitively. Only WZV/WZM/WZI/WZP are allowed there;
extra/unknown/cross-basename WZ files, duplicate case-insensitive containers,
multiple movies/scores, or unknown `.REQ` markers are fatal. Recognized markers
are PIT.REQ and optional INST.REQ. Additional readme/manifest/nonmedia files are
allowed. Unmarked legacy directories retain their existing basename behavior.

## WZP1 exact bytes

All integers are unsigned little-endian. Header is 16 bytes:

| Offset | Size | Value |
|---:|---:|---|
| 0 | 4 | ASCII WZP1 |
| 4 | 2 | version=1 |
| 6 | 2 | flags=0 |
| 8 | 4 | duration_ms, 1..600000 |
| 12 | 2 | count, 2..10000 |
| 14 | 2 | reserved=0 |

Each record is 8 bytes:

| Offset | Size | Value |
|---:|---:|---|
| 0 | 4 | timestamp_ms |
| 4 | 1 | note: 0/off, or MIDI45..96 |
| 5 | 1 | flags: bit0 explicit attack/retrigger; all other bits zero |
| 6 | 2 | reserved=0 |

Length is exactly `16+8*count`, maximum 80016 bytes. Times strictly increase,
first time is0, and last time equals duration with note0/flags0/reserved0.
Unknown versions/flags, bad notes, off+retrigger, missing final off, out-of-range
times, duplicates, length mismatch/truncation/trailing bytes are fatal.

## WZM2 exact bytes

Only WZM1 magic changes to ASCII WZM2. Header is 20 bytes: at offsets0/4/6/8/12/16,
respectively magic[4], u16 header_size20, u16 record_size14, u32 count2..10000,
u32 duration_ms1..600000, u32 reserved0. Each14-byte record is u32 time at0,
note[4] at4, velocity[4] at8, retrigger byte at12, reserved byte0 at13.
The four existing WZM1 voice/velocity/noise/retrigger semantics remain intact.
Exact length is `20+14*count` (maximum140020). Times strictly increase, first
time0, last time=duration, and the last ten payload bytes are **all zero**:
all notes, velocities, retrigger and reserved. PIT-only/all-rest exports carry
two silent records, at0 and duration. WZM2 has no P pitch field.

## State/attack and catch-up semantics

Same-time NoteOff precedes NoteOn in source evaluation; writers merge them into
one replacement record. Off is unconditional release. Off->on or changed
nonzero pitch implies a new attack **even with flag0**. An unchanged nonzero
pitch with flag0 holds the original attack time. Flag1 explicitly attacks or
retriggers, including equal repeated notes. Canonical writers set flag1 for
every attack. Readers accept same-pitch flag0 hold and changed-pitch flag0 attack.

Retrigger is immediate gate-off, reprogram and gate-on, not an invented timed
silent interval. Native clients must off/forget before rearming because the
shared PitClientNote cache deliberately suppresses equal pitches. Held state
retains the pitch/attack snapshot. Catch up by evaluating the current state;
never replay an already expired attack burst. Seeking/replay reevaluates time
and never resurrects a note whose interval has ended. Evaluate all states due
at a boundary before entering speech or starting a replacement note.

## Canonical PIT pitch

Reuse the shared PITCLNT whole-Hz table indexed by note-45:

```
110,117,123,131,139,147,156,165,175,185,196,208,220,233,247,262,
277,294,311,330,349,370,392,415,440,466,494,523,554,587,622,659,
698,740,784,831,880,932,988,1047,1109,1175,1245,1319,1397,1480,
1568,1661,1760,1865,1976,2093
```

PIT clock is1193182Hz; divisor is integer `(1193182+hz/2)/hz`, as PITCORE.
Use channel2 mode3; no PIT0/1, IRQ/vector or cadence changes. Preserve unrelated
port61 bits. Host renderers use the same table/divisor rather than independently
recomputing ideal equal temperament. Host software gain does not change native
binary hardware level. Physical EX summing remains an independent qualification.

## Speech exclusion and ownership

For each SPC1 clip `[start,end)`, require P silent throughout
`[max(0,start-150), min(duration,end+150))`. Validate logical held intervals and
repeated attacks across the entire P stream before playback. NoteOff exactly
at the lower guard boundary is allowed; note-on exactly at the upper boundary
is allowed. An interval intersecting the guarded half-open interval is rejected.
Retain existing PSG speech authoring guards and legacy playback behavior.

PIT is off/forgotten before PWM. Never restore a saved divisor after PWM;
reevaluate the current movie time and acquire/rearm only a presently valid note.
Stop, error, cancellation, Escape, close, deactivation/session loss and lease
refusal silence only owned output and release ownership exactly once.

Parsing and complete P/bundle/guard validation precede sound acquisition,
speaker/PSG writes and video-mode changes. Playback requires explicit PIT enable
and verified runtime capability, **including all-rest P**. Missing capability
or enable refuses playback; never drop P silently. Makers may show a silent
video preview, clearly indicating the required P lane.

DOS acceptance requires verified exclusive DOS-session ownership and actual
Windows-child fail-closed behavior; existing multiplex probes alone do not
establish that. Do not invent a replacement guard or promote a PIT runtime
while that acceptance gate is unresolved. Windows adapters use the shared
lease/capability API; no direct-port fallback on acquisition refusal.

## Frozen fixture rules

The corpus uses synthetic black RGBI frames and authored notes/rests only.
Authoring fixtures use initial PSG program0 and vibrato=false; compare exact
WZM/WZI/WZP output bytes, not approximate score/audio similarity. Reader-only
fixtures intentionally exercise valid noncanonical state replacements.
Fixture metadata states source acceptance, bundle acceptance, movie/audio entry
scope, and explicit runtime-enable/capability expectations independently.
Negative bundle rejection must occur before playback output writes. Old-reader
tests cover video, combined and audio-only paths; neither missing sidecars nor
an all-rest P may let an old reader omit the required voice.
