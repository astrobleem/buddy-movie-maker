# Shared MML1 contract, revision 2 (Maker / native Fiddle)

This specification incorporates the native Fiddle owner's C6 timing, memory and
WININST12 instrument requirements. No legacy gate/velocity preset aliases.

## Source and grammar

ASCII UTF-8 text, maximum 8,192 bytes. Optional UTF-8 BOM is not supported.
Case insensitive. Whitespace ignored; semicolon starts a line comment.
Three monophonic PSG tone sections: `[A]`, `[B]`, `[C]`, each on its own line.
Duplicate sections are errors. Missing sections are silent. Content before the
first section is an error. Source errors identify 1-based line and column.
Each section resets defaults: `T120 O4 L4 V12 @KEYS`.

- `T40..240`: tempo in BPM for that part.
- `O2..7`; `<` lowers and `>` raises the octave. `C4` pitch = MIDI 60.
  Every emitted melodic pitch must be MIDI 45..96.
- `L1/2/4/8/16/32/64`: default denominator.
- Notes `C D E F G A B`, optional `#`/`+` sharp or `-` flat, optional
  denominator from the above set, optional one dot. A token `C4` is a quarter
  C in the current octave, **not** an octave command.
- `R` rest with optional denominator and dot.
- `V0..15`: V0 is silent/rest; V1..15 maps to MIDI velocity `1+9*(V-1)`.
  V12 is exactly 100. Existing PSG attenuation is exactly `15-V`.
- Repeats `[sequence]N`, N2..8, maximum nesting 2; section headers are recognized
  only as standalone lines. No repeat escaping, alternate endings or loops.
- `@KEYS`, `@ORGAN`, `@BASS`, `@PAD`, `@REED`, `@LEAD`, `@BELL`, `@HIT`
  map to zero-based MIDI programs 0/16/32/48/64/80/96/112. Default @KEYS.
  UI selection supplies the initial preset only; explicit @ commands override.
- No ties, chords, noise/percussion, pitch bends, legacy alias presets, TTS or
  automatic soundtrack transcription.

## Timing, order and bounds

PPQN96, whole note384 ticks, single dot multiplies ticks by3/2.
Tempo microseconds/quarter = round(60,000,000/T), half-up. At every time advance,
add `ticks*tempo + remainder`, divide by96,000 to update whole milliseconds and
carry the remainder. Event time = whole milliseconds plus1 when remainder is
at least48,000. This fixed denominator works across tempo changes; no arbitrary
rational LCM. Largest dotted-whole product at T40 is864,000,000, fitting32bits.

Written note duration is100%; NoteOff is immediate and precedes NoteOn at an
equal timestamp. Repeated equal notes retrigger. Same-time commands preserve
source order in their part. Preset changes affect future attacks only; sounding
voices retain preset/velocity/base-divider/attack-time snapshots. Bell/Hit may
self-expire before written NoteOff, exactly as in WININST12.

Maximum expanded-token budget32,768 across all parts, maximum4,096 notes/rests
per part, maximum600 seconds total. Native parsers use streaming iteration or
two-pass validation rather than unbounded arrays. Merged export state limit
10,000 is independent. Maker allows at most250ms overrun only to trim a trailing
note/rest at the video end and write the final mute. It rejects any new attack
at or after video end; no exported WZM/WZI record exceeds declared duration.
Commands after video end are rejected rather than discarded. WZM duration is
the exact movie duration. Fiddle uses the score duration.

## Original expressive engine

Use the original WININST12 instrument curves and nominal55ms update quantum,
from `experimental/WININST12.zip/SOURCE/BEATS/INSTR.C` and `INSTR.MD`.
Optional preset-enabled vibrato applies only to Pad/Reed/Lead: eight-step
triangle, onset440ms, period440ms, depth floor(base divider/256), at most two
depth units. High-register zero-depth behavior is preserved. Updates catch up
directly, without replaying missed quanta. No replacement oscillator waveforms.
MIDI-only exports retain legacy rectangular WZM behavior unless explicitly
extended later; expressive MML must not silently use that fallback.

## WZM1 + WZI1 interchange

WZM1 stays unchanged:20-byte header,14-byte records; its reserved byte stays0.
MML adds mandatory `MOVIE.WZI`, an explicitly versioned preset sidecar:

| Byte | Field |
|---:|---|
|0|ASCII `WZI1`|
|4|u16 header size20|
|6|u16 record size8|
|8|u32 record count1..10,000|
|12|u32 duration_ms, exactly matching WZM/video|
|16|u16 flags: bit0 enables eligible-preset vibrato, others0|
|18|u16 original engine contract version0x0102|

Each record: u32 time_ms, three program bytes for tones A/B/C, one reserved0.
All integers are little-endian. Programs must be exactly0/16/32/48/64/80/96/112. Times increase strictly and fit
duration; first record time0. Same-time preset commands coalesce in source order.
Merge streamed WZI/WZM records chronologically, applying sidecar program states
before WZM attack states at an equal timestamp. Late catch-up snapshots each
attack with the program at that attack time, never the latest wall-clock program.
Preset snapshots at attack prevent later commands altering held notes. Malformed
sidecar is a fatal pre-playback error, not a rectangular fallback. Unknown flags,
engine, programs, reserved values, count/length mismatch and trailing bytes are
fatal. Flag0 means envelopes only (WININST12 config1); flag1 adds eligible-preset
vibrato (config3). Final WZM
state mutes all channels. DOS filenames remain8.3. Maker also emits `INST.REQ`, exactly four ASCII bytes`WZI1`, to require the expressive sidecar. A missing or malformed required sidecar is fatal; this marker prevents accidental legacy fallback after an incomplete copy. Legacy MIDI exports omit the marker.

## Conformance cases

1. `[A] T120 O4 L4 V12 @KEYS C D`: attacks C60 at0ms and D62 at500ms,
   velocity100; final note-off1000ms. Default preset0.
2. `[A] T120 O4 C4. R8 > C8`: C60 at0, off750; rest ends1000;
   C72 at1000, off1250. Note durations750/250ms.
3. `[A] T121 O4 [C64 R64]8`: uses tempo495,868us and carried remainder;
   16 tokens, total496ms (495.868ms rounded half-up).
4. `[A] V0 C4 V15 @ORGAN C4`: first token rests0..500; C60 velocity127,
   program16 at500, off1000. @ changes no preceding attack.
5. `[A] @PAD O3 C1` plus `[B] @BELL O4 G1`: default tempo120, each
   written duration2000ms; presets48/96, Bell self-expiry retained.
6. Reject duplicate section, non-ASCII/BOM, O1, T0, L3, note outside45..96,
   unknown preset, unmatched repeat, repeat9/depth3, expanded-budget overflow,
   no section, and score>600s. Report 1-based source location.
7. Video900ms with `T120 C4 D4`: trim the trailing D at900 and mute; accepted.
   Video400ms with `T120 C4 D4`: rejects the new D attack at500, even if another
   tolerance would otherwise allow it. No state at500 is silently discarded.
8. Sidecar @KEYS at0, @PAD at500, WZM note attack at0 and no retrigger until1000:
   catch-up at750 retains Keys for the held voice. A1000ms attack snapshots Pad.
   Mutated unknown flags/engine/reserved/trailingbyte cases must fail.

DOS cooperative service uses the movie BIOS-tick clock (nominal54.925ms) and
nominal55ms envelope indexing; native Win16 Fiddle uses its Windows pump clock.
Delayed DOS reads/drawing still cause late/collapsed updates. Neither path is a
precision timer or a physical CPU/sound-quality qualification.
