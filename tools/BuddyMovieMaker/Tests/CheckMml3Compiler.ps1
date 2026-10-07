param(
    [Parameter(Mandatory=$true)][string]$Assembly,
    [Parameter(Mandatory=$true)][string]$Output
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $Output){throw 'Use a new report file.'}
Add-Type -Path (Resolve-Path -LiteralPath $Assembly).Path
$root=Join-Path $PSScriptRoot 'Mml3Contract\v1'
& (Join-Path $PSScriptRoot 'CheckMml3Contract.ps1') -Fixtures $root
$manifest=Get-Content -LiteralPath (Join-Path $root 'MANIFEST.json') -Raw | ConvertFrom-Json
$results=@()
function Equal([byte[]]$actual,[byte[]]$expected,[string]$name){if(![Linq.Enumerable]::SequenceEqual($actual,$expected)){throw ('Exact bytes differ: '+$name)}}
foreach($case in $manifest.cases | Where-Object kind -eq 'authoring'){
    $dir=Join-Path $root $case.name
    $r=[BuddyMovieMaker.MmlScore]::Compile([IO.File]::ReadAllText((Join-Path $dir 'SCORE.MML')),[int]$case.duration_ms,0,$false)
    if($r.ScoreMs -ne $case.score_ms -or $r.Version -ne 3){throw ('Score metadata differs: '+$case.name)}
    Equal $r.Music ([IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZM'))) ($case.name+' WZM')
    Equal $r.Instruments ([IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZI'))) ($case.name+' WZI')
    if($case.pit_required){Equal $r.Pit ([IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZP'))) ($case.name+' WZP')}
    elseif($null-ne$r.Pit){throw ('Unexpected PIT stream: '+$case.name)}
    $results+=@{name=$case.name;kind='exact authoring bytes';pass=$true}
}
foreach($case in $manifest.invalid_sources){
    # Read outside catch so missing fixture or harness failure cannot count as parser rejection.
    $source=[IO.File]::ReadAllText((Join-Path $root $case.path));$rejected=$false
    try{[void][BuddyMovieMaker.MmlScore]::Compile($source,$case.movie_ms,0,$false)}
    catch{if($_.Exception.GetBaseException() -isnot [IO.InvalidDataException]){throw};$rejected=$true}
    if(!$rejected){throw ('Accepted invalid source: '+$case.path)}
    $results+=@{name=$case.path;kind='invalid source';pass=$true}
}
foreach($name in @('GUARDOK','GUARDOFF','GUARDON')){
    $pit=[IO.File]::ReadAllBytes((Join-Path $root "$name\MOVIE.WZP"));$rejected=$false
    try{[BuddyMovieMaker.SpeechAudio]::ValidatePitWindow($pit,600,1000,2000)}
    catch{if($_.Exception.GetBaseException() -isnot [IO.InvalidDataException]){throw};$rejected=$true}
    if($rejected -ne ($name-ne'GUARDOK')){throw ('Wrong half-open speech guard decision: '+$name)}
    $results+=@{name=$name;kind='speech guard';pass=$true}
}
foreach($name in @('BASIC','REPEAT','REST','VZERO','ALLREST','EMPTYP','NOPART','CLIP','MIXED','CARRIED')){
    $dir=Join-Path $root $name;$source=[IO.File]::ReadAllText((Join-Path $dir 'SCORE.MML'))
    # Removes the fifth part, restoring prior MML2 authoring to verify unchanged PSG output.
    $source=($source -split '\[P\]',2)[0] -replace 'MML3','MML2'
    if($source -notmatch '\[[ABCN]\]'){continue}
    $duration=($manifest.cases|Where-Object name -eq $name).duration_ms
    $r=[BuddyMovieMaker.MmlScore]::Compile($source,[int]$duration,0,$false)
    $expected=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZM'));$expected[3]=[byte][char]'1'
    Equal $r.Music $expected ($name+' unchanged MML2 PSG')
    Equal $r.Instruments ([IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZI'))) ($name+' unchanged MML2 WZI')
    if($null-ne$r.Pit){throw 'MML2 unexpectedly emitted PIT'}
    $results+=@{name=$name;kind='legacy PSG regression';pass=$true}
}
[IO.File]::WriteAllText([IO.Path]::GetFullPath($Output),($results|ConvertTo-Json -Depth 4))
Write-Output ('PASS: '+$results.Count+' production MML3 compiler/speech checks; report '+$Output)
