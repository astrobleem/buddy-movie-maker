# Local MIDI drum integration and pending cue gains

This local candidate preserves the existing WZM1/WZI1/INST.REQ formats and all
frozen MML1/2/3 fixture bytes. MIDI without percussion retains the tone-only
route. GM channel 10 (wire channel 9) accepts keys 35..81 through the existing
MML2 noise mapping: 35/36 E2 Kick, 38/40 E5 Snare, 42/44/46 E4 Hat, all other
keys E6 Snare. These are hardware timbre reductions, not GM instrument fidelity.
Unknown keys refuse with a sorted key list before export. No external MIDI
program, bend, volume or expression synthesis is claimed; ignored messages are
counted in MIDI-REPORT.JSON.

Three tone lanes retain their assignments while sounding. Track/channel/note
identity prevents one track's note-off from removing a different track's note.
MIDI channel controllers retain MIDI channel scope; they are not reinterpreted
as cue controllers. Excess tones use the established highest-velocity policy.
One noise lane uses highest velocity, then Kick/Snare/Hat/other class, track and
key to break ties. Losing drums are discarded immediately, never queued for
later playback. Native repeated equal hits use the explicit retrigger bit.
Export reports source attacks, arbitration states, suppressed/merged drum hits,
maximum active density and every used GM key's reduction. Submillisecond attacks
that round to one state are counted explicitly. A new quantized attack at/after
movie end refuses instead of disappearing. Attack velocities remain unchanged.

Drum exports add an existing WZI1 snapshot with Organ on the three tone lanes,
no vibrato, and the original MML2 noise envelopes. They use the already qualified
sound-owned RuntimeMml3 executable, without a PIT part or /P switch. This avoids
the legacy runtime's last-state-only seek reconstruction and does not change
either runtime's source or accepted binary. No PIT requirement is invented.
The package capability receipt is required before creating an export folder.
The 600-second export limit is unchanged; separate scores still use output
movie-relative time zero. No automatic source-window cropping is claimed.

## Agreed separate gain contract (not yet emitted by the app)

[WZG1 revision1](WZG1.md) is the normative, separate extension contract agreed
with DOS, Windows x64 and Win16 consumer owners. Existing MML3 v1 documents,
fixtures and accepted runtime binaries remain unchanged. Its frozen synthetic
reference corpus is in Tests/WzgContract/v1; runtime qualification is separate.

Gain bundles use WZV4/WZM3 and mandatory WZI1 flag bit1 (0x0002), matching WZG1,
exact GAIN.REQ=WZG1 and INST.REQ=WZI1. In this new family only, bit2 (0x0004)
requires matching WZP1 and PIT.REQ=WZP1, including empty/all-rest PIT parts.
Valid WZI flags are2,3,6,7. Validate declarations before choosing a PIT route.
Deleting both PIT artifacts cannot remove a declared requirement. Every mode
must preflight the complete bundle; no sidecar-ignore or video-only fallback.
Old WZV2/WZM1 and WZV3/WZM2 remain unchanged. A WZI flag alone is insufficient
to gate old readers that skip sidecars: the new primary magic is mandatory.

CueVolumePlan remains a source-only model. The app currently emits drums using
the already qualified runtime; it does not emit gain bundles or claim fade
playback. Velocity retains its note-attack meaning. Gain adds extra attenuation
once to InstRead, preserving attack preset, velocity, age and phase; gain-only
volume flush bypasses the 55ms service early return. Equal-time processing is
WZI programs, WZM attacks, complete persistent WZG snapshot, then one flush.

Each source note instance requires verified cue ownership. Scoped cue03 off at
234000ms cannot kill cue04 starting233836ms. Same-pitch/same-velocity owner
handover retriggers unless explicitly authored legato; losing notes have no
resurrection queue. Crop gain evaluates source state at the origin. Existing
WZM cannot encode a negative pre-origin attack age, so arbitrary cropped held
envelope age is not promised. Seek within a complete output preserves attacks.

Production gain export remains gated on qualified consumers: fades without
restart, noise phase preservation, expired-envelope behavior, owner overlap,
seek/replay, speech restoration, terminal consumption and error cleanup. The
reference corpus establishes exact bytes and accept/refuse decisions, not
hardware timing or a completed runtime implementation.