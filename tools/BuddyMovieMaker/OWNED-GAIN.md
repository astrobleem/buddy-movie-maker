# Owned MIDI gain workflow - WZG1 revision1

This isolated extension adds verified note ownership and cue gain to Maker.
Existing ordinary MIDI/MML exports keep their formats and accepted runtimes.
Enable Verified cue fades (advanced), choose the complete MIDI master, its
ownership CSV and the cue automation CSV, and set the explicit film origin in
milliseconds. This permits pre-trimmed review videos with full-master scores.
Every note must match channel, pitch, attack velocity and exact source on/off
ticks, with unique track identity when needed. CSV film times must agree with
the source tempo map within1ms; output gates use rounded source MIDI times.
Quoted CSV fields are supported. MIDI sustain/all-notes-off controllers are
rejected in the owned workflow: supply explicitly held note gates.

Fades do not rewrite attack velocity. Three constant Organ tones and one
original MML2 fixed-noise voice receive a separate persistent four-lane extra
attenuation stream. Shared channel/pitch overlaps reduce to strongest velocity,
then latest onset; equal-velocity handover retriggers. Other tone polyphony uses
velocity/channel/pitch/track order. Noise uses velocity/class/latest onset/track/
pitch. All discarded instances are reported and never resurrect. Scoped cue-off
removes only that cue. A crop evaluates source gain at its origin; a clipped held
note starts a fresh attack at output zero, and clipped seeds are reported.
Captions and supplied speech remain output-relative. The600s limit is unchanged.

See WZG1.md and Tests/WzgContract/v1 for the separately frozen interchange
contract. Public gain export requires runtime-gain/MOVPLAY.EXE, exact
GAIN.CAP=WZG1 and a matching QUALIFIED.json. No capability is installed merely
for testing. The internal ExportForQualification harness creates clearly marked
unqualified candidates using the same conversion and transactional export core.
Its manifest has qualified:false; this is not a release or final interoperability
qualification. No cue identifier or ownership inference is added to old formats.

Current qualification evidence:178 DOS bundle/mode/seek/replay checks and12
integration checks covering actual generated speech, PWM Escape, unsafe speech
rejection, busy refusal, partial final-frame intervals and complete movie runs.
The unchanged producer/player bytes passed production x64 interoperability:
320 harness checks,156 independent state comparisons and150 actual seek-buffer
comparisons, with zero failures and complete waveOut/movie playback.
The public package additionally passes42 host checks and five public gain-export
checks on generated inputs. Synthetic samples only are distributed; private
qualification media are excluded. Win16 gain playback is unsupported.

The DOS runtime uses its BIOS movie clock (about54.925ms resolution). Terminal
WZM/WZG states are consumed before cleanup. For final video intervals shorter
than55ms, a preloaded final frame may appear up to55ms early if the next BIOS
tick would miss it. This is not sample-accurate playback. Crop seeds start fresh
attack age and are explicitly reported. Physical Tandy hardware and human
listening remain unverified. No CF-card operation is performed.