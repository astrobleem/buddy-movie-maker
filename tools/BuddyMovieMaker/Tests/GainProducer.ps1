param([Parameter(Mandatory=$true)][string]$Assembly,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop';$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new owned gain QA directory'}
New-Item -ItemType Directory $Output|Out-Null;Add-Type -Path (Resolve-Path -LiteralPath $Assembly).Path
function Need($ok,$why){if(!$ok){throw $why}}
function Reject($action,$why){$rejected=$false;try{& $action}catch{if($_.Exception.GetBaseException()-isnot[IO.InvalidDataException]){throw};$rejected=$true};Need $rejected $why}
function E($t,$s,$a,$b){@{t=$t;s=$s;a=$a;b=$b}}
function Vlq($w,[int]$n){$b=[Collections.Generic.List[byte]]::new();$b.Add([byte]($n-band127));while(($n=$n-shr7)-gt0){$b.Insert(0,[byte](($n-band127)-bor128))};$w.Write($b.ToArray())}
function Midi($name,$tracks){
    $s=[IO.MemoryStream]::new();$w=[IO.BinaryWriter]::new($s);$w.Write([byte[]]@(77,84,104,100,0,0,0,6,0,1,0,$tracks.Count,3,232))
    foreach($events in $tracks){$part=[IO.MemoryStream]::new();$p=[IO.BinaryWriter]::new($part);$p.Write([byte[]]@(0,255,81,3,15,66,64));$last=0
        foreach($e in $events|Sort-Object t){Vlq $p ($e.t-$last);$last=$e.t;$p.Write([byte[]]@($e.s,$e.a,$e.b))}
        Vlq $p (1000-$last);$p.Write([byte[]]@(255,47,0));$bytes=$part.ToArray();$p.Dispose()
        $w.Write([byte[]]@(77,84,114,107));$w.Write([byte[]]@((($bytes.Length-shr24)-band255),(($bytes.Length-shr16)-band255),(($bytes.Length-shr8)-band255),($bytes.Length-band255)));$w.Write($bytes)
    };$path=Join-Path $Output ($name+'.MID');[IO.File]::WriteAllBytes($path,$s.ToArray());$w.Dispose();return $path
}
function A($cue,$velocity,$start,$end,$track=$null){[BuddyMovieMaker.MidiCueAnnotation]::new($cue,0,69,$velocity,$start,$end,$start,$end,$track)}
function ReadStates($bytes,$record){$out=@();for($i=0;$i-lt[BitConverter]::ToInt32($bytes,8);$i++){$at=20+$record*$i;$out+=@{t=[BitConverter]::ToInt32($bytes,$at);data=$bytes[($at+4)..($at+$record-1)]}};return $out}
function Save($name,$arrangement){$dir=Join-Path $Output $name;New-Item -ItemType Directory $dir|Out-Null;[IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZM'),$arrangement.Music);[IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZI'),$arrangement.Instruments);[IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZG'),$arrangement.Gain);[IO.File]::WriteAllText((Join-Path $dir 'GAIN.REQ'),'WZG1',[Text.Encoding]::ASCII);[IO.File]::WriteAllText((Join-Path $dir 'INST.REQ'),'WZI1',[Text.Encoding]::ASCII);$arrangement.Report|ConvertTo-Json|Set-Content (Join-Path $dir 'OWNERSHIP-REPORT.json')}
$results=@()
$path=Midi 'OVERLAP' @(@((E 0 144 69 100),(E 800 128 69 0)),@((E 700 144 69 100),(E 1000 128 69 0)))
$annotations=[BuddyMovieMaker.MidiCueAnnotation[]]@((A 'c03' 100 0 800),(A 'c04' 100 700 1000))
$verified=[BuddyMovieMaker.MidiScore]::VerifyOwners($path,$annotations)
$plan=[BuddyMovieMaker.CueVolumePlan]::new([BuddyMovieMaker.CueGainEvent[]]@([BuddyMovieMaker.CueGainEvent]::new('c03',0,0,$false),[BuddyMovieMaker.CueGainEvent]::new('c03',500,2,$false),[BuddyMovieMaker.CueGainEvent]::new('c03',800,15,$true),[BuddyMovieMaker.CueGainEvent]::new('c04',700,0,$false),[BuddyMovieMaker.CueGainEvent]::new('c04',1000,15,$true)))
$r=[BuddyMovieMaker.MidiScore]::ArrangeOwned($verified,$plan,0,1000);$m=ReadStates $r.Music 14;$g=ReadStates $r.Gain 8
Need (($m|Where-Object t -eq 700).data[0]-eq69-and($m|Where-Object t -eq 700).data[8]-eq1) 'Equal-note owner handover did not retrigger'
Need (($m|Where-Object t -le 800|Select-Object -Last 1).data[0]-eq69) 'Scoped old cue off killed new owner'
Need (($g|Where-Object t -eq 500).data[0]-eq2-and($g|Where-Object t -eq 700).data[0]-eq0) 'Owner handover inherited prior fade'
Need (@($m|Where-Object t -eq 500).Count-eq0-and$r.Report.DiscardedInstances-eq1) 'Gain rewrote WZM attack or arbitration went unreported'
Save 'OVERLAP-BUNDLE' $r;$results+=@{name='Verified scoped ownership; same-pitch handover/retrigger; no velocity fade rewrite';pass=$true}
$crop=[BuddyMovieMaker.MidiScore]::ArrangeOwned($verified,$plan,600,300);$cg=ReadStates $crop.Gain 8
Need ($cg[0].data[0]-eq2-and($cg|Where-Object t -eq 100).data[0]-eq0-and$crop.Report.ClippedHeldSeeds-eq1) 'Crop did not evaluate source owner gain'
Save 'CROP-BUNDLE' $crop;$results+=@{name='Crop gain evaluated at origin; clipped attack age explicitly reported';pass=$true}
Reject {[void][BuddyMovieMaker.MidiScore]::VerifyOwners($path,[BuddyMovieMaker.MidiCueAnnotation[]]@($annotations[0]))} 'Missing annotation accepted'
Reject {[void][BuddyMovieMaker.MidiScore]::VerifyOwners($path,[BuddyMovieMaker.MidiCueAnnotation[]]@((A 'c03' 99 0 800),$annotations[1]))} 'Changed attack velocity accepted'
$bad=[BuddyMovieMaker.MidiCueAnnotation]::new('c03',0,69,100,0,800,6,800,$null)
Reject {[void][BuddyMovieMaker.MidiScore]::VerifyOwners($path,[BuddyMovieMaker.MidiCueAnnotation[]]@($bad,$annotations[1]))} 'Wrong film tempo accepted'
$results+=@{name='Reject incomplete, changed and inconsistent ownership';pass=$true}
$same=Midi 'AMBIGUOUS' @(@((E 0 144 69 100),(E 500 128 69 0)),@((E 0 144 69 100),(E 500 128 69 0)))
Reject {[void][BuddyMovieMaker.MidiScore]::VerifyOwners($same,[BuddyMovieMaker.MidiCueAnnotation[]]@((A 'c03' 100 0 500),(A 'c03' 100 0 500)))} 'Ambiguous track owner accepted'
$explicit=[BuddyMovieMaker.MidiScore]::VerifyOwners($same,[BuddyMovieMaker.MidiCueAnnotation[]]@((A 'c03' 100 0 500 0),(A 'c03' 100 0 500 1)))
Need ($explicit.Notes.Count-eq2) 'Explicit track ownership failed';$results+=@{name='Ambiguous source tracks refuse; exact track identity resolves';pass=$true}
$short=Midi 'NOQUEUE' @(@((E 0 144 69 100),(E 800 128 69 0)),@((E 700 144 69 110),(E 750 128 69 0)))
$v=[BuddyMovieMaker.MidiScore]::VerifyOwners($short,[BuddyMovieMaker.MidiCueAnnotation[]]@((A 'c03' 100 0 800),(A 'c04' 110 700 750)))
$nr=[BuddyMovieMaker.MidiScore]::ArrangeOwned($v,$plan,0,1000);$ns=ReadStates $nr.Music 14
Need (($ns|Where-Object t -le 800|Select-Object -Last 1).data[0]-eq0) 'Losing old owner resurrected after winner ended';$results+=@{name='Suppressed instances never resurrect';pass=$true}
Reject {[void][BuddyMovieMaker.MidiScore]::ArrangeOwned($verified,$plan,0,600001)} '600s limit changed';$results+=@{name='Existing duration limit retained';pass=$true}
@{pass=$true;count=$results.Count;tests=$results;producer_sha256=(Get-FileHash -LiteralPath $Assembly).Hash;scope='Owned producer wire bytes; synthetic tests and explicitly supplied private master; no runtime qualification implied'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $Output 'RESULTS.json')
Write-Output ('PASS owned gain producer '+$results.Count+' checks')
