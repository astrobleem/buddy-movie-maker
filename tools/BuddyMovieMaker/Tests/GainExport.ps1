param([Parameter(Mandatory=$true)][string]$App,[Parameter(Mandatory=$true)][string]$Runtime,
    [Parameter(Mandatory=$true)][string]$Decoder,[Parameter(Mandatory=$true)][string]$Video,
    [Parameter(Mandatory=$true)][string]$Speech,[Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop';$App=(Resolve-Path -LiteralPath $App).Path;$Runtime=(Resolve-Path -LiteralPath $Runtime).Path
$Video=(Resolve-Path -LiteralPath $Video).Path;$Speech=(Resolve-Path -LiteralPath $Speech).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new owned gain export QA directory'}
New-Item -ItemType Directory $Output|Out-Null
Add-Type -Path (Join-Path $App 'BuddyMovieMaker.dll');[AppContext]::SetData('APP_CONTEXT_BASE_DIRECTORY',$App)
[BuddyMovieMaker.MovieEngine]::CheckDecoder($Decoder,[Threading.CancellationToken]::None).GetAwaiter().GetResult()|Out-Null
function Need($ok,$why){if(!$ok){throw $why}}
function Reject($action){$rejected=$false;try{&$action}catch{$ex=$_.Exception.GetBaseException();if($ex-isnot[IO.InvalidDataException]-and$ex-isnot[IO.IOException]-and$ex-isnot[OperationCanceledException]){throw};$rejected=$true};Need $rejected 'Expected export refusal'}
function Vlq($writer,[int]$n){$b=[Collections.Generic.List[byte]]::new();$b.Add([byte]($n-band127));while(($n=$n-shr7)-gt0){$b.Insert(0,[byte](($n-band127)-bor128))};$writer.Write($b.ToArray())}
$part=[IO.MemoryStream]::new();$p=[IO.BinaryWriter]::new($part);$p.Write([byte[]]@(0,255,81,3,15,66,64));$last=0
foreach($e in @(@(0,144,69,100),@(1000,128,69,0),@(1850,144,72,90),@(2000,128,72,0))){Vlq $p ($e[0]-$last);$last=$e[0];$p.Write([byte[]]@($e[1],$e[2],$e[3]))}
$p.Write([byte[]]@(0,255,47,0));$body=$part.ToArray();$p.Dispose();$s=[IO.MemoryStream]::new();$w=[IO.BinaryWriter]::new($s)
$w.Write([byte[]]@(77,84,104,100,0,0,0,6,0,0,0,1,3,232,77,84,114,107));$w.Write([byte[]]@((($body.Length-shr24)-band255),(($body.Length-shr16)-band255),(($body.Length-shr8)-band255),($body.Length-band255)));$w.Write($body)
$midi=Join-Path $Output 'SOURCE.MID';[IO.File]::WriteAllBytes($midi,$s.ToArray());$w.Dispose()
$csv=Join-Path $Output 'OWNERS.csv';@'
part,midi_channel,midi_note,velocity,start_tick,end_tick,film_start_s,film_end_s,source_cue
"held, tone",1,69,100,0,1000,0,1,c02
post-speech,1,72,90,1850,2000,1.85,2,c04
'@|Set-Content -LiteralPath $csv
$score=[BuddyMovieMaker.MidiScore]::VerifyOwnersCsv($midi,$csv)
$plan=[BuddyMovieMaker.CueVolumePlan]::new([BuddyMovieMaker.CueGainEvent[]]@([BuddyMovieMaker.CueGainEvent]::new('c02',0,0,$false),[BuddyMovieMaker.CueGainEvent]::new('c02',400,2,$false),[BuddyMovieMaker.CueGainEvent]::new('c02',1000,15,$true),[BuddyMovieMaker.CueGainEvent]::new('c04',1400,0,$false),[BuddyMovieMaker.CueGainEvent]::new('c04',1500,3,$false),[BuddyMovieMaker.CueGainEvent]::new('c04',2000,15,$true)))
$method=[BuddyMovieMaker.OwnedMovieExport].GetMethod('ExportForQualification',[Reflection.BindingFlags]'NonPublic,Static')
function Stage($dest,$token,$clips=$null,$captions=$null,$currentScore=$score,$currentPlan=$plan,$source=$Video,$origin=0,$progress=$null){
    $arguments=[object[]]@($source,$currentScore,$currentPlan,$dest,$token,$Runtime,[Nullable[int]]$origin,$captions,[decimal]0,$null,$progress,$clips);for($i=0;$i-lt$arguments.Length;$i++){if($null-ne$arguments[$i]){$arguments[$i]=$arguments[$i].PSObject.BaseObject}};$task=$method.Invoke($null,$arguments);$task.GetAwaiter().GetResult()|Out-Null
}
$blocked=Join-Path $Output 'MISSING-CAP'
Reject {[BuddyMovieMaker.OwnedMovieExport]::Export($Video,$score,$plan,$blocked,[Threading.CancellationToken]::None).GetAwaiter().GetResult()|Out-Null}
Need (!(Test-Path -LiteralPath $blocked)) 'Normal gain export published without qualification'
$empty=Join-Path $Output 'EMPTY';Stage $empty ([Threading.CancellationToken]::None)
Need (!(Test-Path (Join-Path $empty 'SPEECH.PCM'))-and(Get-Item (Join-Path $empty 'MOVIE.LRC')).Length-eq0) 'Empty optional inputs not empty'
$manifest=Get-Content (Join-Path $empty 'MANIFEST.JSON') -Raw|ConvertFrom-Json
Need (!$manifest.qualified-and$manifest.duration_ms-eq2000-and$manifest.frames-eq8) 'Candidate status/duration differs'
foreach($f in $manifest.files.PSObject.Properties){Need ((Get-FileHash (Join-Path $empty $f.Name)).Hash-eq$f.Value) 'Candidate inventory mismatch'}
Need ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $empty 'MOVIE.WZV')),0,4)-ceq'WZV4') 'Wrong gain video magic'
$info=[BuddyMovieMaker.MovieEngine]::Probe($Video,[Threading.CancellationToken]::None).GetAwaiter().GetResult();$baseline=Join-Path $Output 'BASELINE.WZV'
[BuddyMovieMaker.MovieEngine]::Convert($Video,$baseline,$info,[Threading.CancellationToken]::None).GetAwaiter().GetResult()|Out-Null
$old=[IO.File]::ReadAllBytes($baseline);$new=[IO.File]::ReadAllBytes((Join-Path $empty 'MOVIE.WZV'));Need ([Linq.Enumerable]::SequenceEqual([byte[]]$old[4..($old.Length-1)],[byte[]]$new[4..($new.Length-1)])) 'Gain changed packed preview/video bytes'
$before=(Get-FileHash (Join-Path $empty 'MANIFEST.JSON')).Hash;Reject {Stage $empty ([Threading.CancellationToken]::None)};Need ((Get-FileHash (Join-Path $empty 'MANIFEST.JSON')).Hash-eq$before) 'Overwrite altered existing bundle'
$retry=Join-Path $Output 'RETRY';$cts=[Threading.CancellationTokenSource]::new();$cts.Cancel();try{Reject {Stage $retry $cts.Token}}finally{$cts.Dispose()};Need (!(Test-Path $retry)) 'Cancelled bundle published';Stage $retry ([Threading.CancellationToken]::None)
Add-Type -TypeDefinition @'
using System;using System.IO;using System.Threading;
public sealed class GainCancelProbe:IProgress<double>{readonly CancellationTokenSource source;public GainCancelProbe(CancellationTokenSource s){source=s;}public void Report(double p){if(p>=0.25)source.Cancel();}}
public sealed class GainRaceProbe:IProgress<double>{readonly string target;public GainRaceProbe(string p){target=p;}public void Report(double p){if(p>=0.25&&!Directory.Exists(target)){Directory.CreateDirectory(target);File.WriteAllText(Path.Combine(target,"EXISTING.txt"),"owned destination race");}}}
'@
$mid=Join-Path $Output 'MID-CANCEL';$cts=[Threading.CancellationTokenSource]::new();$probe=[GainCancelProbe]::new($cts)
try{Reject {Stage $mid $cts.Token $null $null $score $plan $Video 0 $probe}}finally{$cts.Dispose()};Need (!(Test-Path $mid)) 'Mid-conversion cancellation published';Stage $mid ([Threading.CancellationToken]::None)
$race=Join-Path $Output 'RACE';$probe=[GainRaceProbe]::new($race);Reject {Stage $race ([Threading.CancellationToken]::None) $null $null $score $plan $Video 0 $probe}
Need ([IO.File]::ReadAllText((Join-Path $race 'EXISTING.txt'))-eq'owned destination race'-and!(Test-Path (Join-Path $race 'MANIFEST.JSON'))) 'Destination race overwrote existing content'
$captions=Join-Path $Output 'CAPTIONS.TXT';@('0|GENERATED GAIN','1200|SPEECH','1850|RESTORED GAIN')|Set-Content -LiteralPath $captions
$clips=[BuddyMovieMaker.SpeechRequest[]]@([BuddyMovieMaker.SpeechRequest]::new($Speech,1200));$goodSpeech=Join-Path $Output 'SPEECH';Stage $goodSpeech ([Threading.CancellationToken]::None) $clips $captions
Need ((Get-Content (Join-Path $goodSpeech 'MANIFEST.JSON') -Raw|ConvertFrom-Json).speech_clips-eq1) 'Actual speech preparation missing'
$badSpeech=Join-Path $Output 'SPEECH-CONFLICT';$overlap=[BuddyMovieMaker.SpeechRequest[]]@([BuddyMovieMaker.SpeechRequest]::new($Speech,400));Reject {Stage $badSpeech ([Threading.CancellationToken]::None) $overlap};Need (!(Test-Path $badSpeech)) 'Speech treated attenuation as logical rest'
Need (@(Get-ChildItem -LiteralPath $Output -Directory|Where-Object Name -like '.buddy-gain-*').Count-eq0) 'Orphan staging folder'
$private=@()
@{pass=$true;checks=10;scope='Actual owned export transaction and speech preparation; explicit internal qualification staging, no fabricated receipt; regular gain export still blocked; pre/mid-conversion cancellation and destination race preserved';private=$private;runtime_sha256=(Get-FileHash -LiteralPath $Runtime).Hash;producer_sha256=(Get-FileHash (Join-Path $App 'BuddyMovieMaker.dll')).Hash}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $Output 'RESULTS.json')
Write-Output 'PASS owned export:10 transaction/media/speech checks'
