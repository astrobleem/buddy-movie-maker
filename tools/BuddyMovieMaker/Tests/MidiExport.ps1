param([Parameter(Mandatory=$true)][string]$App,[Parameter(Mandatory=$true)][string]$Decoder,
    [Parameter(Mandatory=$true)][string]$Fixtures,[Parameter(Mandatory=$true)][string]$Video,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
$App=(Resolve-Path -LiteralPath $App).Path;$Fixtures=(Resolve-Path -LiteralPath $Fixtures).Path;$Video=(Resolve-Path -LiteralPath $Video).Path
$Output=[IO.Path]::GetFullPath($Output);if(Test-Path -LiteralPath $Output){throw 'Use a new MIDI export QA directory.'};New-Item -ItemType Directory $Output|Out-Null
Add-Type -Path (Join-Path $App 'BuddyMovieMaker.dll');[AppContext]::SetData('APP_CONTEXT_BASE_DIRECTORY',$App)
[BuddyMovieMaker.MovieEngine]::CheckDecoder($Decoder,[Threading.CancellationToken]::None).GetAwaiter().GetResult()|Out-Null
function Export($score,$destination,$token){[BuddyMovieMaker.MovieEngine]::Export($Video,$score,$null,$destination,$token).GetAwaiter().GetResult()|Out-Null}
function Reject($action){$no=$false;try{&$action}catch{$ex=$_.Exception.GetBaseException();if($ex-isnot[IO.InvalidDataException]-and$ex-isnot[IO.IOException]-and$ex-isnot[OperationCanceledException]){throw};$no=$true};if(!$no){throw 'Expected export refusal'}}
$score=Join-Path $Fixtures 'COLLISION.MID';$good=Join-Path $Output 'DRUMS';Export $score $good ([Threading.CancellationToken]::None)
$report=Get-Content (Join-Path $good 'MIDI-REPORT.JSON') -Raw|ConvertFrom-Json
if($report.Report.DrumAttacks-ne2-or$report.Report.DrumReductionStates-ne1-or!(Test-Path (Join-Path $good 'MOVIE.WZI'))-or[IO.File]::ReadAllText((Join-Path $good 'INST.REQ'))-ne'WZI1'-or!(Get-FileHash (Join-Path $good 'MOVPLAY.EXE')).Hash.Equals((Get-FileHash (Join-Path $App 'runtime-mml3/MOVPLAY.EXE')).Hash)){throw 'Drum export sidecars/report/runtime mismatch'}
$manifest=Get-Content (Join-Path $good 'MANIFEST.JSON') -Raw|ConvertFrom-Json
foreach($entry in $manifest.files.PSObject.Properties){if((Get-FileHash (Join-Path $good $entry.Name)).Hash-ne$entry.Value){throw 'Export inventory mismatch'}}
$initial=(Get-FileHash (Join-Path $good 'MANIFEST.JSON')).Hash;Reject {Export $score $good ([Threading.CancellationToken]::None)};if((Get-FileHash (Join-Path $good 'MANIFEST.JSON')).Hash-ne$initial){throw 'Existing destination modified'}
$unknown=Join-Path $Output 'UNKNOWN';Reject {Export (Join-Path $Fixtures 'BAD34.MID') $unknown ([Threading.CancellationToken]::None)};if(Test-Path $unknown){throw 'Unknown drum published destination'}
$cancelled=Join-Path $Output 'RETRY';$cts=[Threading.CancellationTokenSource]::new();$cts.Cancel();try{Reject {Export $score $cancelled $cts.Token}}finally{$cts.Dispose()};if(Test-Path $cancelled){throw 'Cancelled export published'};Export $score $cancelled ([Threading.CancellationToken]::None)
$cap=Join-Path $App 'runtime-mml3/MML3.CAP';$hidden=$cap+'.midi-test-held';if(Test-Path $hidden){throw 'Capability test collision'}
$blocked=Join-Path $Output 'MISSING-CAP';Move-Item -LiteralPath $cap -Destination $hidden
try{Reject {Export $score $blocked ([Threading.CancellationToken]::None)};if(Test-Path $blocked){throw 'Unqualified drum player published'}}finally{Move-Item -LiteralPath $hidden -Destination $cap}
$legacy=Join-Path $Output 'LEGACY';Export (Join-Path $Fixtures 'LEGACY.MID') $legacy ([Threading.CancellationToken]::None)
if(Test-Path (Join-Path $legacy 'MOVIE.WZI')){throw 'Tone-only MIDI gained instrument sidecar'}
if((Get-FileHash (Join-Path $legacy 'MOVPLAY.EXE')).Hash-ne(Get-FileHash (Join-Path $App 'runtime/MOVPLAY.EXE')).Hash){throw 'Tone-only legacy runtime changed'}
@{pass=$true;checks=7;scope='Actual MovieEngine export, report/inventory, no-overwrite, unknown drum, cancel/retry, missing capability refusal, tone-only legacy route; generated media only';player=(Get-FileHash (Join-Path $good 'MOVPLAY.EXE')).Hash}|ConvertTo-Json|Set-Content (Join-Path $Output 'RESULTS.json')
Write-Output 'PASS: 7 targeted MIDI export checks'
