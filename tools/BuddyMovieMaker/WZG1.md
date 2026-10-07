# WZG1 gain extension — revision 1

This separately versioned extension preserves frozen MML1/MML2/MML3 and their
no-gain families. It defines interchange, not musical accuracy or physical
timing qualification. Required gain exports remain disabled until a compatible
runtime passes qualification. Historic Win16 may explicitly refuse this family.

## Directly consumed family gates

Gain-required music is **WZM3**; included video is **WZV4**. Their header/frame/
record layouts are unchanged from WZM2/WZV3: only magic changes; WZM reserved
u32 remains0. All gain bundles require matching WZM3, WZI1, WZG1 and exact
INST.REQ/GAIN.REQ. Audio-only may omit video; any video present must be WZV4.
No WZV4 video-only fallback when music or sidecars are missing. A player mode
that omits required music refuses the bundle rather than dropping gain/PIT.
Maker's independent silent frame preview is not such a player mode.

No-gain WZV2/WZM1 and PIT WZV3/WZM2 rules stay frozen. Gain artifacts, gain flags
or mixed old/new families reject. Direct music/video magic gates prevent entry
paths that skip optional sidecars from silently accepting the new family.

## WZI declarations

Only in WZV4/WZM3, WZI1 engine0x0102 keeps its existing layout and gains flags:

| Bit | Value | Meaning |
|---|---:|---|
|0|0x0001|Existing eligible-preset vibrato|
|1|0x0002|Required WZG1 gain stream; must be set|
|2|0x0004|Required WZP1 PIT voice, including empty/all-rest P|

Allowed mask is7; unknown bits reject. Valid new values are2/3/6/7. Old-family
flags still allow only bit0; bit1/bit2 remain invalid there. Require WZI and
validate its declarations before selecting PIT/non-PIT playback paths.
Flag4 set requires matching WZP1 and exact PIT.REQ=WZP1. Flag4 clear rejects
either PIT artifact. Stripping both cannot erase the requirement declared in
WZI; stripping WZI itself also fails. Existing WZP1 bytes/rules stay unchanged.

One selected bundle basename per marked directory; Maker/DOS use MOVIE.
GAIN.REQ is exactly four ASCII bytes WZG1, no BOM/newline/trailing data.
INST.REQ is exactly WZI1; PIT.REQ when required is exactly WZP1. All required
durations match. Reject missing/unknown/mixed members before acquisition,
port writes, rendering or audio submission in every entry path and mode.

## WZG1 exact bytes

All integers are little-endian. Header is20 bytes:

| Offset | Bytes | Field |
|---:|---:|---|
|0|4|ASCII WZG1|
|4|2|u16 header_size20|
|6|2|u16 record_size8|
|8|4|u32 count2..10000|
|12|4|u32 duration_ms1..600000|
|16|4|u32 reserved0|

Record is8 bytes: u32 time_ms at0; four u8 extra attenuation steps at4..7 for
PSG A/B/C/noise. Each step0..15 adds2 dB chip steps, clamped to silence15.
PIT has no gain lane; no physical PC-speaker volume is promised.

Exact length20+8*count, maximum80,020 bytes. Times strictly increase, first0,
last=duration, no out-of-range time. Final four steps must all be15. Intermediate
15 is allowed but is not a logical rest. First snapshot may be nonzero when
source gain is already active at a cropped origin. Default gain before first
snapshot is0; no output occurs before the time0 snapshot is evaluated.
Counts for WZM/WZI/WZP/WZG are independent, not a combined10,000 budget.
WZM3 retains exact20/14 layouts, bounded notes/velocities/retrigger/reserved
rules; first0, final duration and final ten payload bytes all0.

## Causal ordering, holds and output

At one timestamp: apply WZI program state before WZM attacks, then the complete
persistent four-lane WZG snapshot; flush once after the group. Producers merge
same-time source gain changes into one record; duplicate WZG times reject.
Held notes retain attack velocity/preset/divider/time, envelope age, oscillator/
vibrato phase and noise state. WZI program changes affect future attacks only.
Same-pitch/same-velocity ownership handover retriggers unless explicitly legato.

InstRead already includes attack-velocity attenuation. Effective attenuation is
min(15, InstRead attenuation+extra), adding extra exactly once. Gain-only changes
must flush volume even inside an already-serviced55ms envelope quantum. They
never call InstStart, change pitch, reset noise or restart an envelope. Ordinary
envelope/vibrato scheduling stays unchanged. Expired voices remain expired when
gain rises. BIOS-tick DOS service may be late; exact logical timestamps do not
claim exact physical dispatch or calibrated 4.77MHz performance.

Late catch-up consumes history, preserves each surviving attack's own snapshot,
and applies latest gain at current time without replaying stale hardware writes.
Seek reconstructs all streams through the target inclusively before output;
backward seek/replay resets prior state. Gain state persists across notes; it is
not implicitly cleared by a new attack. Producer must supply the new owner's
gain at handover. Post-speech invalidates output-volume caches and restores
current gain without reviving expired voices. Speech guards require WZM logical
rests and existing PIT rests; gain15 is never a substitute. End consumes terminal
states and releases/mutes owned sound; stop/error/ownership loss also cleans up.

## Producer ownership and selection

Cue identity is producer-only, bound to verified note instances, not inferred
from shared channels, pitch or global time windows. Reject missing/ambiguous
annotation matches. Resolve scoped off before new on at equal source time,
discard losing instances without a resurrection queue, then select voices and
write their persistent gain snapshot. Cue03 off234000 removes only cue03;
cue04 from233836 survives with its own gain. Preserve source attack velocities.

Crop initialization evaluates source cue gain at the selected origin, then
rebases output times; the600s limit is unchanged. WZG has no attack-age field.
Existing segment-initial held-note seeding does not encode a negative pre-origin
attack time: do not claim arbitrary cropped-envelope age/phase preservation.
Whole-output seeks preserve attack history present in that output. BBB's current
segmented MIDI tones use constant Organ; clipped seeds are reported separately.
