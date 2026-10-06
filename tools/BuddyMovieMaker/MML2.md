# MML2 noise extension, revision 1

Status: shared contract for Beats export, native MML Fiddle, and MovieMaker.
MML1 revision 2 remains unchanged. All existing MML1 fixtures must still pass.

## Version and syntax

MML2 must be the first nonblank, noncomment standalone line (case insensitive).
Without this header, the source is MML1 and [N] or noise tokens are errors.
With this header, optional [N] joins unchanged [A], [B], [C]. Each section may
appear once; missing parts are silent. Headers remain standalone lines.
All source is ASCII without BOM; semicolon line comments remain supported.

[N] is the single PSG noise voice, not a fourth pitched voice. Its defaults
are T120 L4 V9. Allowed tokens: T, L, V, R, repeats, and noise hits:

    N35          ; drum code 35, current L duration
    N38/16.      ; drum code 38, dotted sixteenth
    N42/32       ; drum code 42, thirty-second

A hit is N followed by integer code 35..81, optional slash and denominator
1/2/4/8/16/32/64, then optional single dot. A slash is mandatory when specifying
an explicit hit duration. Dot without slash dots the current L duration.
O, <, >, melodic notes, @ presets, and ties are errors in [N]. Noise hits are
errors in [A]/[B]/[C]. V0 consumes the duration as a rest. N0 is invalid; use R.
Repeated equal hits retrigger, including the noise shift-register reset.
NoteOff is immediate, precedes NoteOn at equal time, and only affects noise.
No inference from a melodic @HIT preset is permitted.

## Exact existing hardware/engine semantics

Send hits through the existing mapper MIDI channel 9. Codes map as follows:

| Codes | Noise control byte | Type/rate selector | Envelope |
|---|---|---|---|
|35,36|E2|periodic, fixed selector 2|original Kick (8)|
|38,40|E5|white, fixed selector 1|original Snare (9)|
|42,44,46|E4|white, fixed selector 0|original Hat (10)|
|all other 35..81|E6|white, fixed selector 2|original Snare (9)|

Selectors 0/1/2 use the PSG's fixed divider sources, never selector 3. Rates follow the existing PSG clock;
no new absolute-Hz promise is introduced. Neither E3 nor E7 is emitted. Noise must not borrow or retune tone C, even
when all three tone lanes sound. The noise frequency is not a melodic pitch.
These are exactly WININST12's mappings, including its existing limitations.

V1..15 maps to MIDI velocity 1+9*(V-1), base attenuation 15-V. The original
WININST12 noise curves and 55ms update model apply. Noise has no vibrato.
Program changes in A/B/C do not alter noise. Repeated attacks snapshot their
own velocity/attack time. Stop, completion, error and ownership loss mute only
owned sound and release the lease; failed acquisition must perform no writes.
No new timer/IRQ hooks or shared driver installation are introduced.

## Timing and bounds

Reuse MML1 PPQN96, carried rational timing, tempo40..240, duration<=600 seconds,
source<=8192 bytes, expanded tokens<=32768 TOTAL across all four sections.
Each section, including N, permits at most4096 expanded notes/rests; repeat
count2..8, nesting<=2. Merged WZM states remain capped at10000. No unbounded
arrays or catch-up playback of stale attacks. Delayed reconstruction must
retain each held voice's actual attack snapshot before direct envelope catchup.

## Binary compatibility and required capabilities

WZM1 remains unchanged: fourth note/velocity slot carries drum35..81 or0/off;
retrigger bit3 forces a repeated noise attack; reserved byte stays0. Final
state mutes all four voices. WZI1 remains unchanged, with programs for A/B/C
only, exact matching duration, engine0x0102 and existing flags0/1. Sidecar is
mandatory for expressive MML2 just as MML1. INST.REQ stays exactly four ASCII
bytes WZI1. A playback implementation claiming this extension must support
fourth-slot noise using the above existing engine, not silently omit it.
MML2 text is deliberately rejected by old parsers. WZM/WZI are existing media
formats, so no binary version change or invented instrument data is required.

## Beats export policy

Export exactly one eight-step cycle. A step is an eighth; active step uses a
dotted sixteenth hit/note followed by R32, preserving the intended75% gate.
Empty step is R8. Tempo is emitted in each section. All four sections are
included. Tone V11 emits91, matching Beats96's base attenuation4; noise V9 emits73,
matching Beats76's base attenuation6. Velocities are not byte-identical. Expressive
Beats uses @KEYS; legacy rectangular tones may use @ORGAN, but legacy noise
without envelopes requires a separate explicitly supported legacy policy.
This kit exports expressive Beats. The text is generated/read-only; comments
state one cycle, attenuation preservation, and cooperative timing limits.
Beats integer-millisecond truncation and MML carried timing can differ slightly;
no claim of an identical wall-clock event trace or indefinite loop is made.

## Conformance

See EXPECTED.json and exact .MML/.WZM/.WZI fixtures. They cover all47 drum
codes, all three simultaneous tones plus noise, repeated hits, V0/rest, gate,
volume endpoints, preset changes while noise is held, and tempo40/120/240.
Negative fixtures cover missing/misplaced version, duplicate N, bad code,
forbidden noise/tone syntax, invalid duration/volume, repeats and bounds.
Existing MML1 fixtures must remain byte-identical and passing.
