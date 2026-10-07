# Separate WZG1 runtime - implementation checkpoint

This isolated directory copies RuntimeMml3 and adds the separately frozen WZG1 gain reader. Accepted Runtime/RuntimeMml3 copies and binaries remain untouched. Runtime qualification is incomplete; no GAIN.CAP is shipped yet.

# MML3 DOS runtime provenance and resource scope

This is an isolated copy of Maker's legacy DOS runtime plus the frozen MML3
reader and cooperative sound integration. `../Runtime` remains unchanged.

`DOSSND.C`, `DOSSND.H`, `DOSGUARD.H` and `win30/DRIVER/PITCORE.H` are byte-preserved
from the reviewed DOS-Sound-Owner-v1 source handoff, sound-owner commit
`ad8c62a539d33805ec27226c941e5bb5d312a8e3`. They originate in the same GPLv3 Tandy
project. No proprietary compiler headers, libraries or tool binaries are stored
here. Compile the adapter once with MSC6 C89, `/G0 /AS`, default packing/cdecl.
Zero is API success; negative values refuse. Maker does not introduce another
lease or pitch cache inside the adapter.

The adapter manages one cooperative foreground DOS player. Its verified
Windows/ROM detection and quiet-speaker acquisition are platform/resource gates;
they cannot exclude arbitrary TSRs, BIOS beeps or unregistered port writers.
Run in a controlled foreground DOS session with no other sound/timer writers.
No resident component, persistent registration or global interception is added.

The reader fully validates WZV3/WZM2/WZP1 pairing and speech guards before
acquisition, port writes or video changes. `/P` explicitly enables a required
PIT voice, including empty and all-rest parts. Direct launch refuses without it.
`/A` validates the complete audio bundle, including any video present. `/V`
refuses a PIT-required bundle instead of dropping the required part.

Acquisition lasts for the playback lifetime. All PSG output routes through the
adapter. PWM begin/end bracket the whole sampled clip and block PSG/PIT melodic
calls, including caption callbacks between sample chunks. After PWM the player
evaluates current movie time; it never restores a saved speaker divisor.
Stop, Escape, interrupt/error and normal exit release owned output once; repeated
adapter release remains safe. Existing sampled mode0 timing is unchanged.

`/R` uses the existing WZC1 range sidecar, with pre-roll of logical music,
instrument and PIT states before any output. Default playback uses the entire
movie. Seeks reconstruct attack-time presets and PIT state; replay starts in a
fresh process. The video remains 256x160/4fps, with BIOS-tick movie cadence.

Qualification is recorded separately. An MML3 runtime capability file is placed
in a user-facing package only after that runtime and Maker's actual speech path
pass integration tests. The stable player is still used for legacy exports.


Gain declarations are preflighted before PIT route selection. WZI/WZM/WZG merge by source timestamp, with one equal-time group flush. InstRead base attenuation receives extra gain once; gain-only flush bypasses the55ms service cache without another attack/pitch/noise reset. Seek reconstructs attack snapshots and current gain. Terminal states are consumed before cleanup. Logical WZM rests, not gain15, guard speech; post-PWM invalidates volume caches.

The movie clock remains BIOS-tick based (about54.925ms), not sample-accurate. A gain movie with a final video interval shorter than55ms preloads its final frame before acquisition and may display it up toone BIOS tick early to preserve that interval without extending audio duration. Native qualification of this new tail adjustment is pending. Diagnostics distinguish authored rest target from actual dispatch; do not claim zero dispatch lateness.
