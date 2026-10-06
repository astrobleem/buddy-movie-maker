# Reference conformance/integrity check; no hardware writes or production parser.
param([Parameter(Mandatory=$true)][string]$Fixtures)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $Fixtures).Path
$manifest=Get-Content -LiteralPath (Join-Path $root 'MANIFEST.json') -Raw | ConvertFrom-Json
$spec=Join-Path (Split-Path $PSScriptRoot) 'MML3.md'
if((Get-FileHash -LiteralPath $spec).Hash -ne $manifest.spec_sha256){throw 'Frozen specification hash mismatch.'}
foreach($f in $manifest.files){$p=Join-Path $root $f.path;if((Get-Item -LiteralPath $p).Length -ne $f.size -or (Get-FileHash -LiteralPath $p).Hash -ne $f.sha256){throw ('Fixture hash mismatch: '+$f.path)}}
function Need([bool]$ok,[string]$message){if(!$ok){throw [IO.InvalidDataException]::new($message)}}
function U16([byte[]]$b,[int]$p){[BitConverter]::ToUInt16($b,$p)}
function U32([byte[]]$b,[int]$p){[BitConverter]::ToUInt32($b,$p)}
function Magic([byte[]]$b){Need ($b.Length -ge 4) 'short magic';[Text.Encoding]::ASCII.GetString($b,0,4)}
function Read([string]$dir,[string]$name){Need (Test-Path -LiteralPath (Join-Path $dir $name) -PathType Leaf) ('missing '+$name);return ,[IO.File]::ReadAllBytes((Join-Path $dir $name))}
function Check([string]$dir,[bool]$audio){
    $m=Read $dir 'MOVIE.WZM';Need ($m.Length -ge 20) 'short music';$mm=Magic $m
    Need ($mm -in @('WZM1','WZM2')) 'music magic';$duration=U32 $m 12
    Need ($duration -gt 0 -and $duration -le 600000) 'duration'
    $hasVideo=Test-Path -LiteralPath (Join-Path $dir 'MOVIE.WZV')
    Need ($audio -or $hasVideo) 'movie needs video'
    $vm=$null
    if($hasVideo){$v=Read $dir 'MOVIE.WZV';Need ($v.Length -ge 24) 'short video';$vm=Magic $v;Need ($vm -in @('WZV2','WZV3')) 'video magic';$frames=U32 $v 12;Need ((U16 $v 4) -eq 256 -and (U16 $v 6) -eq 160 -and (U16 $v 8) -eq 4 -and (U16 $v 10) -eq 24 -and (U32 $v 16) -eq $duration -and (U32 $v 20) -eq 20480 -and $frames -eq [Math]::Ceiling($duration/250.0) -and $v.Length -eq 24+$frames*20480) 'video profile/length'}
    $required=$vm -eq 'WZV3' -or $mm -eq 'WZM2'
    $marker=Test-Path -LiteralPath (Join-Path $dir 'PIT.REQ');$hasPit=Test-Path -LiteralPath (Join-Path $dir 'MOVIE.WZP')
    if($required){
        Need ($mm -eq 'WZM2' -and (!$hasVideo -or $vm -eq 'WZV3') -and $marker -and $hasPit) 'required version pairing'
        Need (([Text.Encoding]::ASCII.GetString((Read $dir 'PIT.REQ'))) -ceq 'WZP1') 'PIT marker'
        foreach($file in Get-ChildItem -LiteralPath $dir -File){$ext=$file.Extension.ToUpperInvariant();if($ext.StartsWith('.WZ')){Need ($file.BaseName -ieq 'MOVIE' -and $ext -in @('.WZV','.WZM','.WZI','.WZP')) 'mixed/unknown WZ basename'};if($ext -eq '.REQ'){Need ($file.Name -iin @('PIT.REQ','INST.REQ')) 'unknown marker'}}
    }else{Need (!$marker -and !$hasPit) 'legacy with PIT artifact'}
    $n=U32 $m 8;Need ((U16 $m 4) -eq 20 -and (U16 $m 6) -eq 14 -and (U32 $m 16) -eq 0 -and $n -ge 2 -and $n -le 10000 -and $m.Length -eq 20+14*$n) 'music header/count/length'
    $prev=-1L
    for($i=0;$i -lt $n;$i++){$at=20+14*$i;$time=U32 $m $at;Need ($time -gt $prev -and $time -le $duration -and ($i -ne 0 -or $time -eq 0)) 'music times';$prev=$time;Need (($m[$at+12] -band 240) -eq 0 -and $m[$at+13] -eq 0) 'music flags/reserved';for($j=0;$j -lt 4;$j++){$note=$m[$at+4+$j];$velocity=$m[$at+8+$j];Need ($velocity -le 127 -and (($note -eq 0 -and $velocity -eq 0) -or ($velocity -gt 0 -and $note -ge $(if($j -eq 3){35}else{45}) -and $note -le $(if($j -eq 3){81}else{96})))) 'music note/velocity'}}
    if($mm -eq 'WZM2'){Need ($prev -eq $duration -and !($m[($m.Length-10)..($m.Length-1)] | Where-Object {$_ -ne 0})) 'music final mute'}
    $inst=Read $dir 'MOVIE.WZI';Need ($inst.Length -eq 28 -and (Magic $inst) -eq 'WZI1' -and (U16 $inst 4) -eq 20 -and (U16 $inst 6) -eq 8 -and (U32 $inst 8) -eq 1 -and (U32 $inst 12) -eq $duration -and (U16 $inst 16) -eq 0 -and (U16 $inst 18) -eq 0x0102 -and (U32 $inst 20) -eq 0) 'instrument fixture';Need (([Text.Encoding]::ASCII.GetString((Read $dir 'INST.REQ'))) -ceq 'WZI1') 'instrument marker'
    if($required){
        $p=Read $dir 'MOVIE.WZP';Need ($p.Length -ge 16) 'short PIT';$count=U16 $p 12
        Need ((Magic $p) -eq 'WZP1' -and (U16 $p 4) -eq 1 -and (U16 $p 6) -eq 0 -and (U32 $p 8) -eq $duration -and (U16 $p 14) -eq 0 -and $count -ge 2 -and $count -le 10000 -and $p.Length -eq 16+8*$count) 'PIT header/count/length'
        $events=@();$prev=-1L
        for($i=0;$i -lt $count;$i++){$at=16+8*$i;$t=U32 $p $at;$note=$p[$at+4];$flags=$p[$at+5];Need ($t -gt $prev -and $t -le $duration -and ($i -ne 0 -or $t -eq 0)) 'PIT times';Need (($note -eq 0 -or ($note -ge 45 -and $note -le 96)) -and ($flags -band 254) -eq 0 -and ($note -ne 0 -or $flags -eq 0) -and (U16 $p ($at+6)) -eq 0) 'PIT note/flags/reserved';$prev=$t;$events+=@{time=$t;note=$note}}
        Need ($prev -eq $duration -and $note -eq 0 -and $flags -eq 0) 'PIT final mute'
        if(Test-Path -LiteralPath (Join-Path $dir 'SPEECH.PCM')){
            $sp=Read $dir 'SPEECH.PCM';Need ((Magic $sp) -eq 'SPC1' -and $sp.Length -eq 2420 -and (U16 $sp 4) -eq 1 -and (U32 $sp 8) -eq 600 -and (U32 $sp 12) -eq 1000) 'speech fixture'
            $low=[Math]::Max(0,600-150);$high=[Math]::Min($duration,1000+150)
            for($i=0;$i -lt $events.Count-1;$i++){Need (!($events[$i].note -ne 0 -and $events[$i].time -lt $high -and $events[$i+1].time -gt $low)) 'PIT speech guard'}
        }
    }
}
$tested=0
foreach($case in $manifest.cases){foreach($audio in @($false,$true)){$expected=if($audio){$case.audio_accept}else{$case.movie_accept};$accepted=$true;try{Check (Join-Path $root $case.name) $audio}catch [IO.InvalidDataException]{$accepted=$false};if($accepted -ne $expected){throw ('Wrong reference result: '+$case.name+' audio='+$audio+' expected='+$expected)};$tested++}}
$pitch=Get-Content -LiteralPath (Join-Path $root 'PITCH.json') -Raw | ConvertFrom-Json
Need ($pitch.Count -eq 52) 'pitch table count'
for($i=0;$i -lt 52;$i++){Need ($pitch[$i].note -eq 45+$i -and $pitch[$i].divisor -eq [Math]::Floor((1193182+[Math]::Floor($pitch[$i].hz/2.0))/$pitch[$i].hz)) 'pitch/divisor'}
Write-Output ('PASS: '+$manifest.files.Count+' exact fixture files; '+$tested+' movie/audio reference decisions; 52 canonical divisors; spec hash.')
