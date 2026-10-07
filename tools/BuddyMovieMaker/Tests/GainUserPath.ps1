param([Parameter(Mandatory=$true)][string]$App,[Parameter(Mandatory=$true)][string]$Decoder,
 [Parameter(Mandatory=$true)][string]$FixtureRoot,[Parameter(Mandatory=$true)][string]$Video,
 [Parameter(Mandatory=$true)][string]$Speech,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop';$App=(Resolve-Path -LiteralPath $App).Path;$FixtureRoot=(Resolve-Path -LiteralPath $FixtureRoot).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new public gain user-path QA directory'}
$cap=Join-Path $App 'runtime-gain/GAIN.CAP';$receipt=Join-Path $App 'runtime-gain/QUALIFIED.json'
if(!(Test-Path $cap)-or!(Test-Path $receipt)){throw 'Qualification not activated; this test does not create capability files'}
$q=Get-Content -LiteralPath $receipt -Raw|ConvertFrom-Json
if(!$q.native_pass-or!$q.speech_pass-or!$q.x64_interop_pass-or!$q.full_segments_pass){throw 'Final native/full-segment/x64 qualification still pending'}
New-Item -ItemType Directory $Output|Out-Null
Add-Type -Path (Join-Path $App 'BuddyMovieMaker.dll');[AppContext]::SetData('APP_CONTEXT_BASE_DIRECTORY',$App)
[BuddyMovieMaker.MovieEngine]::CheckDecoder($Decoder,[Threading.CancellationToken]::None).GetAwaiter().GetResult()|Out-Null
function Need($ok,$why){if(!$ok){throw $why}}
function Reject($action){$rejected=$false;try{&$action}catch{$e=$_.Exception.GetBaseException();if($e-isnot[IO.IOException]-and$e-isnot[IO.InvalidDataException]-and$e-isnot[OperationCanceledException]){throw};$rejected=$true};Need $rejected 'Expected public export refusal'}
$source=[BuddyMovieMaker.MidiScore]::VerifyOwnersCsv((Join-Path $FixtureRoot 'SOURCE.MID'),(Join-Path $FixtureRoot 'OWNERS.csv'))
$plan=[BuddyMovieMaker.CueVolumePlan]::new([BuddyMovieMaker.CueGainEvent[]]@([BuddyMovieMaker.CueGainEvent]::new('c02',0,0,$false),[BuddyMovieMaker.CueGainEvent]::new('c02',400,2,$false),[BuddyMovieMaker.CueGainEvent]::new('c02',1000,15,$true),[BuddyMovieMaker.CueGainEvent]::new('c04',1400,0,$false),[BuddyMovieMaker.CueGainEvent]::new('c04',1500,3,$false),[BuddyMovieMaker.CueGainEvent]::new('c04',2000,15,$true)))
$video=(Resolve-Path -LiteralPath $Video).Path;$voice=(Resolve-Path -LiteralPath $Speech).Path
function Export($file,$score,$gain,$dest,$origin,$token,$captions=$null,$speech=$null){[BuddyMovieMaker.OwnedMovieExport]::Export($file,$score,$gain,$dest,$token,$origin,$captions,[decimal]0,$null,$null,[BuddyMovieMaker.SpeechRequest[]]$speech).GetAwaiter().GetResult()|Out-Null}
$completed=@()
foreach($mode in @('EMPTY','SPEECH')){
    $dest=Join-Path $Output $mode;$clips=if($mode-eq'SPEECH'){[BuddyMovieMaker.SpeechRequest[]]@([BuddyMovieMaker.SpeechRequest]::new($voice,1200))}else{$null}
    $captions=if($mode-eq'SPEECH'){Join-Path $FixtureRoot 'CAPTIONS.TXT'}else{$null};Export $video $source $plan $dest 0 ([Threading.CancellationToken]::None) $captions $clips
    $m=Get-Content (Join-Path $dest 'MANIFEST.JSON') -Raw|ConvertFrom-Json;Need $m.qualified 'Public user-path export still unqualified'
    foreach($entry in $m.files.PSObject.Properties){Need ((Get-FileHash (Join-Path $dest $entry.Name)).Hash-eq$entry.Value) 'Public export inventory mismatch'}
    $baseline=Join-Path $FixtureRoot $mode;foreach($file in @('MOVIE.WZV','MOVIE.WZM','MOVIE.WZI','MOVIE.WZG','GAIN.REQ','INST.REQ','MOVPLAY.EXE','MOVIE.LRC')){Need ((Get-FileHash (Join-Path $dest $file)).Hash-eq(Get-FileHash (Join-Path $baseline $file)).Hash) ('Qualified public path changed native-tested bytes '+$file)}
    if($mode-eq'SPEECH'){Need ((Get-FileHash (Join-Path $dest 'SPEECH.PCM')).Hash-eq(Get-FileHash (Join-Path $baseline 'SPEECH.PCM')).Hash) 'Public PCM changed'}
    $completed+=@{name=$mode;manifest_sha256=(Get-FileHash (Join-Path $dest 'MANIFEST.JSON')).Hash}
}
$existing=Join-Path $Output 'EMPTY';$before=(Get-FileHash (Join-Path $existing 'MANIFEST.JSON')).Hash;Reject {Export $video $source $plan $existing 0 ([Threading.CancellationToken]::None)};Need ((Get-FileHash (Join-Path $existing 'MANIFEST.JSON')).Hash-eq$before) 'Public overwrite changed destination'
$retry=Join-Path $Output 'RETRY';$cts=[Threading.CancellationTokenSource]::new();$cts.Cancel();try{Reject {Export $video $source $plan $retry 0 $cts.Token}}finally{$cts.Dispose()};Need (!(Test-Path $retry)) 'Public cancelled export published';Export $video $source $plan $retry 0 ([Threading.CancellationToken]::None)
# Temporarily hide only our new package's text receipt, never a decoder/player.
$held=$cap+'.user-path-held';if(Test-Path $held){throw 'Capability test collision'}
Move-Item -LiteralPath $cap -Destination $held
try{$blocked=Join-Path $Output 'MISSING-CAP';Reject {Export $video $source $plan $blocked 0 ([Threading.CancellationToken]::None)};Need (!(Test-Path $blocked)) 'Public gain path ignored missing capability'}finally{Move-Item -LiteralPath $held -Destination $cap}
@{pass=$true;checks=5;tests=$completed;producer_sha256=(Get-FileHash (Join-Path $App 'BuddyMovieMaker.dll')).Hash;qualification_receipt_sha256=(Get-FileHash $receipt).Hash;scope='Public gain exporter used by desktop UI; receipt-gated normal path, empty optional inputs, actual speech/captions, no-overwrite, cancellation/retry, missing capability; no internal qualification override'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $Output 'RESULTS.json')
