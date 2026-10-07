# Independent literal-state corpus: does not call any Maker parser or writer.
param([Parameter(Mandatory=$true)][string]$OutputRoot)
$ErrorActionPreference='Stop'
$OutputRoot=[IO.Path]::GetFullPath($OutputRoot)
if(Test-Path -LiteralPath $OutputRoot){throw 'Use a new fixture folder; frozen fixtures are never overwritten.'}
[IO.Directory]::CreateDirectory($OutputRoot) | Out-Null
$utf8=[Text.UTF8Encoding]::new($false)
$cases=[Collections.Generic.List[object]]::new()
function P([int]$time,[int]$note,[int]$flags=1){[pscustomobject]@{time=$time;note=$note;flags=$flags}}
function S([int]$time,[byte[]]$notes,[byte[]]$velocities,[byte]$retrigger=0){[pscustomobject]@{time=$time;notes=$notes;velocities=$velocities;retrigger=$retrigger}}
function MakeBundle([string]$name,[int]$duration,[object[]]$pit,[string]$source='',[object[]]$states=$null,[string]$kind='authoring',[int]$scoreMs=0){
    $dir=Join-Path $OutputRoot $name;[IO.Directory]::CreateDirectory($dir) | Out-Null
    $frames=[int][Math]::Ceiling($duration/250.0)
    $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZV')))
    try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZV3'));$w.Write([UInt16]256);$w.Write([UInt16]160);$w.Write([UInt16]4);$w.Write([UInt16]24);$w.Write([UInt32]$frames);$w.Write([UInt32]$duration);$w.Write([UInt32]20480);$black=[byte[]]::new(20480);for($i=0;$i -lt $frames;$i++){$w.Write($black)}}finally{$w.Dispose()}
    if(!$states){$states=@((S 0 ([byte[]]::new(4)) ([byte[]]::new(4))),(S $duration ([byte[]]::new(4)) ([byte[]]::new(4))))}
    $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZM')))
    try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZM2'));$w.Write([UInt16]20);$w.Write([UInt16]14);$w.Write([UInt32]$states.Count);$w.Write([UInt32]$duration);$w.Write([UInt32]0);foreach($s in $states){$w.Write([UInt32]$s.time);$w.Write([byte[]]$s.notes);$w.Write([byte[]]$s.velocities);$w.Write([byte]$s.retrigger);$w.Write([byte]0)}}finally{$w.Dispose()}
    $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZI')))
    try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZI1'));$w.Write([UInt16]20);$w.Write([UInt16]8);$w.Write([UInt32]1);$w.Write([UInt32]$duration);$w.Write([UInt16]0);$w.Write([UInt16]0x0102);$w.Write([UInt32]0);$w.Write([byte[]]::new(4))}finally{$w.Dispose()}
    $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZP')))
    try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZP1'));$w.Write([UInt16]1);$w.Write([UInt16]0);$w.Write([UInt32]$duration);$w.Write([UInt16]$pit.Count);$w.Write([UInt16]0);foreach($p in $pit){$w.Write([UInt32]$p.time);$w.Write([byte]$p.note);$w.Write([byte]$p.flags);$w.Write([UInt16]0)}}finally{$w.Dispose()}
    [IO.File]::WriteAllBytes((Join-Path $dir 'PIT.REQ'),[Text.Encoding]::ASCII.GetBytes('WZP1'))
    [IO.File]::WriteAllBytes((Join-Path $dir 'INST.REQ'),[Text.Encoding]::ASCII.GetBytes('WZI1'))
    if($source){[IO.File]::WriteAllText((Join-Path $dir 'SCORE.MML'),$source,$utf8)}
    if(!$scoreMs){$scoreMs=$duration}
    $cases.Add([pscustomobject]@{name=$name;kind=$kind;duration_ms=$duration;score_ms=$scoreMs;frames=$frames;pit_records=$pit.Count;source_accept=([bool]$source);movie_accept=$true;audio_accept=$true;pit_required=$true;disabled_or_unavailable_playback='reject before output writes'})
}
function Bad([string]$name,[string]$reason){
    $dir=Join-Path $OutputRoot $name;[IO.Directory]::CreateDirectory($dir) | Out-Null
    foreach($file in Get-ChildItem -LiteralPath (Join-Path $OutputRoot 'BASIC') -File){if($file.Name -ne 'SCORE.MML'){[IO.File]::Copy($file.FullName,(Join-Path $dir $file.Name),$false)}}
    $cases.Add([pscustomobject]@{name=$name;kind='negative_bundle';movie_accept=$false;audio_accept=$false;reason=$reason;output_writes=0})
    return $dir
}
function Change([string]$dir,[string]$file,[int]$offset,[byte[]]$bytes){$p=Join-Path $dir $file;$data=[IO.File]::ReadAllBytes($p);[Array]::Copy($bytes,0,$data,$offset,$bytes.Length);[IO.File]::WriteAllBytes($p,$data)}
$basic=@((P 0 60),(P 500 62),(P 1000 0 0))
MakeBundle BASIC 1000 $basic "MML3`n[P]`nT120 O4 L4 V1 C D`n"
MakeBundle REPEAT 1000 @((P 0 60),(P 500 60),(P 1000 0 0)) "MML3`n[P]`nT120 O4 L4 C C`n"
MakeBundle REST 1000 @((P 0 0 0),(P 500 60),(P 1000 0 0)) "MML3`n[P]`nT120 O4 L4 R C`n"
MakeBundle VZERO 1000 @((P 0 0 0),(P 500 60),(P 1000 0 0)) "MML3`n[P]`nT120 O4 L4 V0 C V1 C`n"
MakeBundle ALLREST 500 @((P 0 0 0),(P 500 0 0)) "MML3`n[P]`nT120 R4`n"
MakeBundle EMPTYP 1000 @((P 0 0 0),(P 1000 0 0)) "MML3`n[A]`nT120 O4 V12 C4 D4`n[P]`n" @((S 0 ([byte[]]@(60,0,0,0)) ([byte[]]@(100,0,0,0)) 1),(S 500 ([byte[]]@(62,0,0,0)) ([byte[]]@(100,0,0,0)) 1),(S 1000 ([byte[]]::new(4)) ([byte[]]::new(4))))
MakeBundle NOPART 1000 @((P 0 0 0),(P 1000 0 0)) "MML3`n[A]`nT120 O4 V12 C4 D4`n" @((S 0 ([byte[]]@(60,0,0,0)) ([byte[]]@(100,0,0,0)) 1),(S 500 ([byte[]]@(62,0,0,0)) ([byte[]]@(100,0,0,0)) 1),(S 1000 ([byte[]]::new(4)) ([byte[]]::new(4))))
$d=Join-Path $OutputRoot 'NOPART';Change $d 'MOVIE.WZV' 3 ([byte[]]@(50));Change $d 'MOVIE.WZM' 3 ([byte[]]@(49));Remove-Item -LiteralPath (Join-Path $d 'MOVIE.WZP'),(Join-Path $d 'PIT.REQ')
$last=$cases[$cases.Count-1];$last.pit_required=$false;$last.pit_records=0;$last.disabled_or_unavailable_playback='legacy behavior; no PIT requirement'
MakeBundle CLIP 900 @((P 0 60),(P 500 62),(P 900 0 0)) "MML3`n[P]`nT120 O4 C4 D4`n" -scoreMs 1000
MakeBundle MIXED 1000 @((P 0 48),(P 500 50),(P 1000 0 0)) "MML3`n[A]`nT120 O4 V12 C2`n[B]`nT120 O4 V12 E2`n[C]`nT120 O4 V12 G2`n[N]`nT120 V9 N38/4 R4`n[P]`nT120 O3 C4 D4`n" @((S 0 ([byte[]]@(60,64,67,38)) ([byte[]]@(100,100,100,73)) 15),(S 500 ([byte[]]@(60,64,67,0)) ([byte[]]@(100,100,100,0))),(S 1000 ([byte[]]::new(4)) ([byte[]]::new(4))))
$carried=@();for($i=0;$i -lt 16;$i++){$time=[int][Math]::Floor(($i*2975208/96000.0)+0.5);$carried+=if($i%2){P $time 0 0}else{P $time 60}}
$carried+=(P 496 0 0)
MakeBundle CARRIED 496 $carried "MML3`n[P]`nT121 O4 [C64 R64]8`n"
MakeBundle HOLD 1000 @((P 0 60),(P 500 60 0),(P 1000 0 0)) -kind reader
MakeBundle IMPLICIT 1000 @((P 0 60 0),(P 500 62 0),(P 1000 0 0)) -kind reader
MakeBundle CATCHUP 1000 @((P 0 60),(P 500 0 0),(P 750 62),(P 1000 0 0)) -kind reader
MakeBundle GUARDOK 2000 @((P 0 60),(P 450 0 0),(P 1150 62),(P 1500 0 0),(P 2000 0 0)) -kind reader
function Speech([string]$dir){$w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'SPEECH.PCM')));try{$w.Write([Text.Encoding]::ASCII.GetBytes('SPC1'));$w.Write([UInt16]1);$w.Write([UInt16]0);$w.Write([UInt32]600);$w.Write([UInt32]1000);$w.Write([UInt16]2400);$w.Write([UInt16]0);$w.Write([byte[]](,(36)*2400))}finally{$w.Dispose()}}
Speech (Join-Path $OutputRoot 'GUARDOK')
$many=@();for($i=0;$i -lt 10000;$i++){$many+=if($i%2 -or $i -eq 9999){P $i 0 0}else{P $i 60}}
MakeBundle COUNTOK 9999 $many -kind reader
$over=@();for($i=0;$i -lt 10001;$i++){$over+=if($i%2 -or $i -eq 10000){P $i 0 0}else{P $i 60}}
MakeBundle COUNTMAX 10000 $over -kind negative_bundle
$last=$cases[$cases.Count-1];$last.movie_accept=$false;$last.audio_accept=$false
MakeBundle UNSORTED 1000 @((P 0 60),(P 700 62),(P 500 64),(P 1000 0 0)) -kind negative_bundle
$last=$cases[$cases.Count-1];$last.movie_accept=$false;$last.audio_accept=$false
foreach($entry in @(@('VERSION',4,2,'unknown WZP version'),@('HFLAGS',6,1,'unknown WZP header flags'),@('RHDR',14,1,'reserved WZP header'),@('RREC',22,1,'reserved WZP record'),@('COUNT0',12,0,'zero WZP count'),@('COUNT1',12,1,'one WZP count'),@('PITCH44',20,44,'pitch below range'),@('PITCH97',20,97,'pitch above range'),@('RFLAGS',21,2,'unknown record flags'),@('OFFFLAG',37,1,'off requests attack'))){$d=Bad $entry[0] $entry[3];Change $d 'MOVIE.WZP' $entry[1] ([byte[]]@($entry[2]))}
$d=Bad FIRST1 'first time is not zero';Change $d 'MOVIE.WZP' 16 ([BitConverter]::GetBytes([UInt32]1))
$d=Bad DUPTIME 'duplicate time';Change $d 'MOVIE.WZP' 24 ([BitConverter]::GetBytes([UInt32]0))
$d=Bad NOFINAL 'missing final note-off';Change $d 'MOVIE.WZP' 36 ([byte[]]@(60,1))
$d=Bad END999 'final time differs from duration';Change $d 'MOVIE.WZP' 32 ([BitConverter]::GetBytes([UInt32]999))
$d=Bad PASTEND 'record after duration';Change $d 'MOVIE.WZP' 24 ([BitConverter]::GetBytes([UInt32]1001))
$d=Bad ZERODUR 'zero PIT duration';Change $d 'MOVIE.WZP' 8 ([BitConverter]::GetBytes([UInt32]0))
$d=Bad MISMATCH 'PIT duration mismatch';Change $d 'MOVIE.WZP' 8 ([BitConverter]::GetBytes([UInt32]1001))
$d=Bad TRUNC 'truncated PIT record';$path=Join-Path $d 'MOVIE.WZP';$b=[IO.File]::ReadAllBytes($path);[IO.File]::WriteAllBytes($path,$b[0..($b.Length-2)])
$d=Bad TRAIL 'PIT trailing byte';$path=Join-Path $d 'MOVIE.WZP';$b=[IO.File]::ReadAllBytes($path);[IO.File]::WriteAllBytes($path,([byte[]]($b+[byte]0)))
$d=Bad NOMARK 'missing PIT marker';Remove-Item -LiteralPath (Join-Path $d 'PIT.REQ')
$d=Bad MARKVER 'bad PIT marker tag';Change $d 'PIT.REQ' 3 ([byte[]]@(50))
$d=Bad MARKLEN 'PIT marker trailing newline';[IO.File]::WriteAllText((Join-Path $d 'PIT.REQ'),"WZP1`n",$utf8)
$d=Bad NOWZP 'missing PIT sidecar';Remove-Item -LiteralPath (Join-Path $d 'MOVIE.WZP')
$d=Bad NOWZM 'missing required WZM2';Remove-Item -LiteralPath (Join-Path $d 'MOVIE.WZM')
$d=Bad LOSTBOTH 'PIT marker and sidecar missing; old version gates still mandatory';Remove-Item -LiteralPath (Join-Path $d 'MOVIE.WZP'),(Join-Path $d 'PIT.REQ')
$d=Bad VIDEO2 'legacy video with PIT artifacts';Change $d 'MOVIE.WZV' 3 ([byte[]]@(50))
$d=Bad MUSIC1 'legacy music with required PIT';Change $d 'MOVIE.WZM' 3 ([byte[]]@(49))
$d=Bad MUSICEND 'WZM2 final retrigger not zero';Change $d 'MOVIE.WZM' 46 ([byte[]]@(1))
$d=Bad MUSICRSV 'WZM2 final reserved not zero';Change $d 'MOVIE.WZM' 47 ([byte[]]@(1))
$d=Bad MUSICNOT 'WZM2 final note not zero';Change $d 'MOVIE.WZM' 38 ([byte[]]@(60))
$d=Bad MUSICVEL 'WZM2 final velocity not zero';Change $d 'MOVIE.WZM' 42 ([byte[]]@(100))
$d=Bad MULTIPLE 'directory contains multiple movie basenames';[IO.File]::Copy((Join-Path $d 'MOVIE.WZV'),(Join-Path $d 'OTHER.WZV'),$false)
$d=Bad CROSSP 'cross-basename PIT sidecar';[IO.File]::Move((Join-Path $d 'MOVIE.WZP'),(Join-Path $d 'OTHER.WZP'))
$d=Bad CROSSM 'cross-basename music sidecar';[IO.File]::Move((Join-Path $d 'MOVIE.WZM'),(Join-Path $d 'OTHER.WZM'))
$d=Bad UNKNOWN 'unknown WZ sidecar';[IO.File]::WriteAllBytes((Join-Path $d 'MOVIE.WZX'),[byte[]]@(1))
$d=Bad REQUNK 'unknown capability marker';[IO.File]::WriteAllText((Join-Path $d 'OTHER.REQ'),'WZP1',$utf8)
foreach($entry in @(@('GUARDOFF',20),@('GUARDON',24))){
    $d=Join-Path $OutputRoot $entry[0];[IO.Directory]::CreateDirectory($d) | Out-Null
    foreach($f in Get-ChildItem -LiteralPath (Join-Path $OutputRoot 'GUARDOK') -File){[IO.File]::Copy($f.FullName,(Join-Path $d $f.Name),$false)}
    if($entry[0] -eq 'GUARDOFF'){Change $d 'MOVIE.WZP' 24 ([BitConverter]::GetBytes([UInt32]451))}else{Change $d 'MOVIE.WZP' 32 ([BitConverter]::GetBytes([UInt32]1149))}
    $cases.Add([pscustomobject]@{name=$entry[0];kind='negative_bundle';movie_accept=$false;audio_accept=$false;reason='PIT intersects 150ms guarded speech interval';output_writes=0})
}
$d=Join-Path $OutputRoot 'AUDIO';[IO.Directory]::CreateDirectory($d) | Out-Null
foreach($f in Get-ChildItem -LiteralPath (Join-Path $OutputRoot 'BASIC') -File){if($f.Name -notin @('MOVIE.WZV','SCORE.MML')){[IO.File]::Copy($f.FullName,(Join-Path $d $f.Name),$false)}}
$cases.Add([pscustomobject]@{name='AUDIO';kind='reader';movie_accept=$false;audio_accept=$true;reason='audio-only WZM2/PIT bundle; no video';pit_required=$true;disabled_or_unavailable_playback='reject before output writes'})
$badSource=[ordered]@{NOVERS="[P]`nC4`n";MML4="MML4`n[P]`nC4`n";LATEVER="[A]`nC4`nMML3`n[P]`nC4`n";DUPPART="MML3`n[P]`nC4`n[P]`nD4`n";VOLUME="MML3`n[P]`nV2 C4`n";PRESET="MML3`n[P]`n@KEYS C4`n";LOWNOTE="MML3`n[P]`nO2 C4`n";HIGHNOTE="MML3`n[P]`nO7 C#4`n";NOISEP="MML3`n[P]`nN35`n";TIE="MML3`n[P]`nC4&C4`n";NEST3="MML3`n[P]`n[[[C4]2]2]2`n";EMPTY="MML3`n[P]`n";ENDATT="MML3`n[P]`nC4 D4`n"}
$badSource['SRCLIMIT']="MML3`n[P]`n"+(' '*8192)+'C4'
$badSource['NOTELIM']="MML3`n[P]`nT240 L64 "+('C'*4097)
$badSource['DURLIMIT']="MML3`n[P]`nT40 [[C1 C1]8]8`n"
$badSource['TOKLIMIT']="MML3`n"+(@('A','B','C','N','P') | ForEach-Object {"[$_]`n[[T240 L64 "+('V1 '*140)+"R64]8]8`n"} | Out-String)
[IO.Directory]::CreateDirectory((Join-Path $OutputRoot 'BADMML')) | Out-Null
foreach($name in $badSource.Keys){[IO.File]::WriteAllText((Join-Path $OutputRoot ('BADMML\'+$name+'.BAD')),$badSource[$name],$utf8)}
$hz=@(110,117,123,131,139,147,156,165,175,185,196,208,220,233,247,262,277,294,311,330,349,370,392,415,440,466,494,523,554,587,622,659,698,740,784,831,880,932,988,1047,1109,1175,1245,1319,1397,1480,1568,1661,1760,1865,1976,2093)
$pitch=@();for($i=0;$i -lt $hz.Count;$i++){$pitch+=[pscustomobject]@{note=45+$i;hz=$hz[$i];divisor=[int][Math]::Floor((1193182+[Math]::Floor($hz[$i]/2.0))/$hz[$i])}}
[IO.File]::WriteAllText((Join-Path $OutputRoot 'PITCH.json'),($pitch | ConvertTo-Json -Depth 4),$utf8)
$manifest=@(Get-ChildItem -LiteralPath $OutputRoot -File -Recurse | ForEach-Object {[pscustomobject]@{path=$_.FullName.Substring($OutputRoot.Length+1).Replace('\','/');size=$_.Length;sha256=(Get-FileHash -LiteralPath $_.FullName).Hash}} | Sort-Object path)
$spec=Join-Path (Split-Path $PSScriptRoot) 'MML3.md'
$summary=[pscustomobject]@{contract='MML3/PIT revision1';spec_sha256=(Get-FileHash -LiteralPath $spec).Hash;fixtures='literal independent states and synthetic black frames; no production compiler invoked';cases=$cases;invalid_sources=@($badSource.Keys | ForEach-Object {[pscustomobject]@{path='BADMML/'+$_.ToString()+'.BAD';source_accept=$false;movie_ms=if($_ -eq 'ENDATT'){400}elseif($_ -eq 'DURLIMIT'){$null}elseif($_ -eq 'NOTELIM'){600000}else{1000}}});files=$manifest}
[IO.File]::WriteAllText((Join-Path $OutputRoot 'MANIFEST.json'),($summary | ConvertTo-Json -Depth 8),$utf8)
Write-Output ('Frozen corpus: '+$cases.Count+' bundle cases; '+$badSource.Count+' invalid sources; '+$manifest.Count+' files.')
