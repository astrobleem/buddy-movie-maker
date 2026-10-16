# Source and dependency notices

Buddy Movie Maker and its generic DOS player retain the GNU GPL version 3
license from `astrobleem/oemsound-tandy`. The full license text is in `LICENSE`.
Source origin and exact extraction revision are recorded in `SOURCE-PROVENANCE.json`.

The player derives from BUDCAP04 at upstream revision
`b25d5bce188cf63a3eb7a5ae9bab68147a862cd2`. Instrument curves and algorithm derive
from the same project's WININST12 source; speech uses its BUDCAP PWM assembly.
Only the selected Maker/player source and synthetic conformance fixtures are
included. Existing names, comments and shared MML specifications are preserved.

Microsoft .NET/Windows Desktop runtime notices are retained in `notices/` for
build/distribution preparation. No Microsoft executable or library is committed.
Binary packages include the corresponding runtime notices and complete
Maker/player source. Legacy compiler/MASM/DDK files remain external prerequisites;
their redistribution is not authorized by this repository's GPL license.

FFmpeg is an external process prerequisite, not bundled or linked into this
repository. Distribution terms depend on its build configuration; see
[FFmpeg's licensing page](https://ffmpeg.org/legal.html). Do not add decoder
binaries to a release without reviewing their exact corresponding-source and
third-party license requirements.
