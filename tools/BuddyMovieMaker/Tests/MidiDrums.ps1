param([Parameter(Mandatory=$true)][string]$Assembly,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a new MIDI QA directory.'}
New-Item -ItemType Directory -Path $Output | Out-Null
$Output=(Resolve-Path -LiteralPath $Output).Path
Add-Type -Path (Resolve-Path -LiteralPath $Assembly).Path
function Need($ok,$message){if(!$ok){throw $message}}
function E($t,$s,$a,$b){@{t=$t;s=$s;a=$a;b=$b}}
function Vlq($w,[int]$n){$bytes=[Collections.Generic.List[byte]]::new();$bytes.Add([byte]($n-band127));while(($n=$n-shr7)-gt0){$bytes.Insert(0,[byte](($n-band127)-bor128))};$w.Write($bytes.ToArray())}
function Midi($name,$tracks,[int]$duration){
    $stream=[IO.MemoryStream]::new();$w=[IO.BinaryWriter]::new($stream)
    $w.Write([byte[]]@(77,84,104,100,0,0,0,6,0,1,0,$tracks.Count,3,232))
    foreach($events in $tracks){
        $part=[IO.MemoryStream]::new();$p=[IO.BinaryWriter]::new($part);$p.Write([byte[]]@(0,255,81,3,15,66,64));$last=0
        foreach($e in $events|Sort-Object t){Vlq $p ($e.t-$last);$last=$e.t;$p.Write([byte[]]@($e.s,$e.a,$e.b))}
        Vlq $p ($duration-$last);$p.Write([byte[]]@(255,47,0));$body=$part.ToArray();$p.Dispose()
        $w.Write([byte[]]@(77,84,114,107));$w.Write([byte[]]@((($body.Length-shr24)-band255),(($body.Length-shr16)-band255),(($body.Length-shr8)-band255),($body.Length-band255)));$w.Write($body)
    }
    $path=Join-Path $Output ($name+'.MID');[IO.File]::WriteAllBytes($path,$stream.ToArray());$w.Dispose();return $path
}
function States($music){$out=@();for($i=0;$i-lt[BitConverter]::ToInt32($music,8);$i++){$at=20+14*$i;$out+=@{t=[BitConverter]::ToInt32($music,$at);n=$music[($at+4)..($at+7)];v=$music[($at+8)..($at+11)];r=$music[$at+12]}};return $out}
$results=@()
$events=@((E 0 144 69 100),(E 0 145 72 90),(E 0 146 76 80))
for($note=35;$note-le81;$note++){$t=($note-35)*250;$events+=(E $t 153 $note 100),(E ($t+100) 137 $note 0)}
$events+=(E 12000 128 69 0),(E 12000 129 72 0),(E 12000 130 76 0)
$path=Midi 'ALL47' (,$events) 12000
$all=[BuddyMovieMaker.MidiScore]::Arrange($path,12000);$states=States $all.Music
Need ($all.Report.DrumAttacks-eq47-and$all.Report.Drums.Count-eq47-and$all.Report.MaxDrums-eq1) 'All GM drums must be accounted for.'
foreach($note in 35..81){$state=$states|Where-Object t -eq (($note-35)*250);Need ($state.n[3]-eq$note-and($state.r-band8)-eq8) ('Missing drum/reset '+$note);Need (($state.n[0..2]-join',')-eq'69,72,76'-and($state.v[0..2]-join',')-eq'100,90,80') 'Drums retuned or re-attenuated tone lanes.'}
Need ($all.Instruments.Length-eq28-and[BitConverter]::ToUInt16($all.Instruments,16)-eq0-and[BitConverter]::ToUInt16($all.Instruments,18)-eq258) 'Wrong WZI contract.'
Need (($all.Instruments[24..27]-join',')-eq'16,16,16,0') 'MIDI tones must retain constant Organ envelope.'
[IO.File]::WriteAllBytes((Join-Path $Output 'ALL47.WZM'),$all.Music);[IO.File]::WriteAllBytes((Join-Path $Output 'ALL47.WZI'),$all.Instruments)
$results+=@{name='47 GM keys; independent three held tones; existing WZI engine';pass=$true}
foreach($bad in @(34,82)){$path=Midi ('BAD'+$bad) (,@((E 0 153 $bad 100),(E 100 137 $bad 0))) 1000;$rejected=$false;try{[void][BuddyMovieMaker.MidiScore]::Arrange($path,1000)}catch{Need ($_.Exception.GetBaseException()-is[IO.InvalidDataException]) 'Wrong unknown-drum exception';$rejected=$true};Need $rejected 'Unknown drum was silently dropped';$results+=@{name=('reject unknown GM '+$bad);pass=$true}}
$path=Midi 'COLLISION' (,@((E 0 153 36 90),(E 0 153 42 120),(E 50 137 42 0),(E 100 137 36 0))) 1000
$r=[BuddyMovieMaker.MidiScore]::Arrange($path,1000);$s=States $r.Music
Need (($s|Where-Object t -eq 0).n[3]-eq42-and($s|Where-Object t -eq 50).n[3]-eq0-and$r.Report.DrumReductionStates-eq1-and$r.Report.SuppressedOrMergedDrumAttacks-eq1) 'Collision winner or no-resurrection policy failed'
$results+=@{name='one noise voice arbitration; lost hits never delayed/replayed';pass=$true}
$path=Midi 'REPEAT' (,@((E 0 153 42 100),(E 100 137 42 0),(E 100 153 42 100),(E 200 137 42 0))) 1000
$s=States ([BuddyMovieMaker.MidiScore]::Arrange($path,1000).Music)
Need (($s|Where-Object t -eq 100).n[3]-eq42-and(($s|Where-Object t -eq 100).r-band8)-eq8) 'Repeated equal drum must reset noise/envelope'
$results+=@{name='equal drum reattack';pass=$true}
$path=Midi 'DENSITY' (,@((E 0 153 42 100),(E 1 137 42 0),(E 1 153 42 100),(E 100 137 42 0))) 1000
$bytes=[IO.File]::ReadAllBytes($path);$bytes[12]=7;$bytes[13]=208;[IO.File]::WriteAllBytes($path,$bytes)
$r=[BuddyMovieMaker.MidiScore]::Arrange($path,1000)
Need ($r.Report.DrumAttacks-eq2-and$r.Report.SuppressedOrMergedDrumAttacks-eq1) 'Submillisecond hit merging must be reported'
$results+=@{name='bounded millisecond attack density has explicit reduction accounting';pass=$true}
$path=Midi 'ENDATTACK' (,@((E 0 144 69 100),(E 1000 128 69 0),(E 1000 144 71 100),(E 2000 128 71 0))) 2000
$rejected=$false;try{[void][BuddyMovieMaker.MidiScore]::Arrange($path,1000)}catch{Need ($_.Exception.GetBaseException()-is[IO.InvalidDataException]-and$_.Exception.GetBaseException().Message.Contains('attack')) 'Wrong attack boundary refusal';$rejected=$true}
Need $rejected 'Boundary attack silently discarded'
$results+=@{name='movie-end attack refuses rather than disappearing';pass=$true}
$path=Midi 'TRACKS' @(@((E 0 144 69 90),(E 50 128 69 0)),@((E 0 144 69 100),(E 100 128 69 0))) 1000
$s=States ([BuddyMovieMaker.MidiScore]::Arrange($path,1000).Music)
Need (@(($s|Where-Object t -eq 50).n[0..2]|Where-Object{$_-eq69}).Count-eq1) 'One track note-off killed another track owner'
$results+=@{name='track-owned equal-pitch notes independent';pass=$true}
$plain=Join-Path $Output 'LEGACY.MID';[IO.File]::WriteAllBytes($plain,[byte[]]@(77,84,104,100,0,0,0,6,0,0,0,1,1,224,77,84,114,107,0,0,0,13,0,144,69,100,135,64,128,69,0,0,255,47,0))
$r=[BuddyMovieMaker.MidiScore]::Arrange($plain,2000);Need ($null-eq$r.Instruments-and$r.Report.DrumAttacks-eq0) 'Tone-only legacy route changed'
$results+=@{name='tone-only legacy route unchanged';pass=$true}
$plan=[BuddyMovieMaker.CueVolumePlan]::new([BuddyMovieMaker.CueGainEvent[]]@([BuddyMovieMaker.CueGainEvent]::new('c03',0,0,$false),[BuddyMovieMaker.CueGainEvent]::new('c03',230600,2,$false),[BuddyMovieMaker.CueGainEvent]::new('c03',234000,15,$true),[BuddyMovieMaker.CueGainEvent]::new('c04',233836,0,$false)))
Need ($plan.Evaluate('c03',233999).ExtraSteps-eq2-and$plan.Evaluate('c03',234000).CueEnded-and$plan.Evaluate('c04',234000).CueActive-and$plan.Evaluate('c04',234000).ExtraSteps-eq0) 'Cue03 off leaked into overlapping cue04'
Need ($plan.Evaluate('c03',230599).ExtraSteps-eq0-and$plan.Evaluate('c03',230600).ExtraSteps-eq2-and$plan.Evaluate('c03',100).ExtraSteps-eq0) 'Half-open boundary or backward evaluation failed'
$results+=@{name='typed independent extra attenuation; cue overlap/off/boundary/backward seek';pass=$true}
@{pass=$true;count=$results.Count;tests=$results;all47_report=$all.Report;scope='Generated fixtures only; no physical hardware, attenuation wire format or fade playback claim'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $Output 'RESULTS.json')
Write-Output ('PASS: '+$results.Count+' independent MIDI/cue-model cases')
