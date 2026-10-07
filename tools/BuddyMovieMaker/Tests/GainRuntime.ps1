param([Parameter(Mandatory=$true)][string]$Runtime,[Parameter(Mandatory=$true)][string]$Output,
    [string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe')
$ErrorActionPreference='Stop'
$Runtime=(Resolve-Path -LiteralPath $Runtime).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new gain runtime QA directory'}
& (Join-Path $PSScriptRoot 'CheckWzgContract.ps1')
$corpus=Join-Path $PSScriptRoot 'WzgContract/v1';$manifest=Get-Content (Join-Path $corpus 'MANIFEST.json') -Raw|ConvertFrom-Json
New-Item -ItemType Directory $Output|Out-Null
$jobs=@();$batch="@echo off`r`n";$index=0
foreach($case in $manifest.cases){
    $name='C'+$index.ToString('000');$index++;$dir=Join-Path $Output $name
    New-Item -ItemType Directory $dir|Out-Null
    Copy-Item -Path (Join-Path $corpus ($case.name+'/*')) -Destination $dir
    Copy-Item -LiteralPath $Runtime -Destination (Join-Path $dir 'MOVPLAY.EXE')
    $batch+="cd \$name`r`n"
    $argsAudio='/A';$d=1000;if(Test-Path (Join-Path $dir 'MOVIE.WZM')){$d=[BitConverter]::ToUInt32([IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZM')),12)}
    if($case.proposed_accept-and$d-gt1000){
        $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.CUE')))
        try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZC1'));$w.Write([uint32]$d);$w.Write([uint32]($d-100));$w.Write([uint32]$d)}finally{$w.Dispose()};$argsAudio+=' /R'
    }
    if($case.name-in@('GAIN_PIT','GAIN_PIT_VIBRATO')){$argsAudio+=' /P'}
    foreach($mode in @('A','V','B','D')){
        $playerArgs=switch($mode){A{$argsAudio};V{'/V'};B{'/B'};D{''}}
        # Audio-only valid bundles deliberately refuse video/both; PIT needs explicit /P.
        if($case.proposed_accept-and$mode-in@('B','D')-and$case.name-in@('GAIN_PIT','GAIN_PIT_VIBRATO')){$playerArgs+=' /P'}
        $accept=[bool]$case.proposed_accept-and$mode-eq'A'
        if($case.proposed_accept-and$mode-in@('B','D')-and(Test-Path (Join-Path $dir 'MOVIE.WZV'))){$accept=$true}
        $batch+="MOVPLAY $playerArgs`r`ncopy MOVPLAY.LOG $mode.LOG > nul`r`n"
        $jobs+=@{fixture=$case.name;folder=$name;entry=$mode;accept=$accept}
    }
}
# Explicit seek and fresh replay over the simultaneous program/attack/gain fixture.
foreach($window in @(@(0,200),@(505,650),@(750,1000))){
    $name='S'+$index.ToString('000');$index++;$dir=Join-Path $Output $name;New-Item -ItemType Directory $dir|Out-Null
    Copy-Item -Path (Join-Path $corpus 'SIMULTANEOUS/*') -Destination $dir;Copy-Item -LiteralPath $Runtime -Destination (Join-Path $dir 'MOVPLAY.EXE')
    $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.CUE')));try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZC1'));$w.Write([uint32]1000);$w.Write([uint32]$window[0]);$w.Write([uint32]$window[1])}finally{$w.Dispose()}
    $batch+="cd \$name`r`nMOVPLAY /A /R`r`ncopy MOVPLAY.LOG A.LOG > nul`r`nMOVPLAY /A /R`r`ncopy MOVPLAY.LOG D.LOG > nul`r`n"
    foreach($mode in @('A','D')){$jobs+=@{fixture='SEEK'+$window[0];folder=$name;entry=$mode;accept=$true}}
}
$batch+="cd \`r`necho RETURNED > RETURNED.TXT`r`nexit`r`n";[IO.File]::WriteAllText((Join-Path $Output 'RUN.BAT'),$batch,[Text.Encoding]::ASCII)
$config=@"
[sdl]
fullscreen=false
output=surface
[dosbox]
machine=tandy
memsize=0
memsizekb=640
[cpu]
core=normal
cputype=8086_prefetch
cycles=fixed 3000
fpu=false
[mixer]
nosound=true
[midi]
mididevice=none
[dos]
xms=false
ems=false
umb=false
[autoexec]
mount C "$Output"
C:
RUN.BAT
"@
$configPath=Join-Path $Output 'RUN.CNF';[IO.File]::WriteAllText($configPath,$config,[Text.Encoding]::ASCII)
$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    $p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$configPath+'"')) -WindowStyle Hidden -PassThru
    try{if(!$p.WaitForExit(60000)){throw 'Own gain matrix timed out'}}finally{if(!$p.HasExited){$p.Kill()}}
}finally{$lease.Dispose()}
if(!(Test-Path (Join-Path $Output 'RETURNED.TXT'))){throw 'Missing DOS return marker'}
$results=@()
foreach($job in $jobs){
    $lines=Get-Content -LiteralPath (Join-Path $Output ($job.folder+'/'+$job.entry+'.LOG'));$fields=@{}
    foreach($line in $lines){if($line.Contains('=')){$k,$v=$line.Split('=',2);$fields[$k]=$v}}
    if(($fields.error-eq'0')-ne$job.accept){throw ('Accept/refuse mismatch '+$job.fixture+' '+$job.entry+' error '+$fields.error)}
    if($fields.sound_mask_after_stop-ne'0'-or$fields.speaker_bits_after_stop-ne'0'-or$fields.old_mode-ne$fields.restored_mode){throw 'Cleanup mismatch'}
    if(!$job.accept-and($fields.psg_writes-ne'0'-or$fields.frames-ne'0')){throw 'Invalid bundle emitted output'}
    if($job.accept-and$job.fixture-ne'LEGACY'){
        if($fields.gain_required-ne'1'-or([int]$fields.gain_applied-lt2-and$job.fixture-notlike'SEEK*')){throw 'Gain stream ignored'}
        if($job.fixture-eq'SIMULTANEOUS'-and($fields.noise_resets-ne'1'-or$fields.voice_0_attacks-ne'2'-or$fields.voice_1_attacks-ne'1'-or$fields.voice_2_attacks-ne'1'-or$fields.gain_applied-ne'6'-or[int]$fields.gain_same_quantum_flushes-lt1)){throw 'Gain restart/quantum/order failure'}
        if($job.fixture-in@('SIMULTANEOUS','VIBRATO_GAIN')){
            $curves=@(@(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0),@(12,9,6,4,2,1,0,0,1,1,1,1,1,1,1,1),@(1,0,0,1,1,1,1,1,2,2,2,2,2,2,2,2),@(2,6,10,15,15,15,15,15,15,15,15,15,15,15,15,15))
            for($j=0;$j-lt[int]$fields.gain_trace_count;$j++){
                $logical=[int]$fields[('gain_'+$j+'_time')];$now=[int]$fields[('gain_'+$j+'_dispatch')]
                foreach($lane in 0..3){$trace=([string]$fields[('gain_'+$j+'_lane_'+$lane)]).Split(',')|ForEach-Object{[int]$_};$born=$trace[0];$preset=$trace[1];$base=$trace[2];$extra=$trace[3];$atten=$trace[4]
                    $expectedPreset=@($(if($logical-ge500){5}else{1}),3,5,10)[$lane];$expectedBorn=if($lane-eq0-and$logical-ge500){9}else{0}
                    if($preset-ne$expectedPreset-or$born-ne$expectedBorn-or$base-ne@(3,5,6,3)[$lane]){throw 'Gain changed held preset/attack age/velocity snapshot'}
                    $age=[Math]::Min(15,[Math]::Floor($now/55)-$born);$curve=$curves[$lane];if($lane-eq0-and$preset-eq5){$curve=$curves[2]}
                    $expected=[Math]::Min(15,$curve[$age]+$base+$extra);if($logical-eq1000){$expected=15}
                    if($atten-ne$expected){throw ('Extra attenuation not added once to InstRead: '+$logical+' lane '+$lane)}
                }
            }
        }
        if($job.fixture-notlike'SEEK*'-or$job.fixture-eq'SEEK750'){foreach($lane in 0..3){if($fields[('voice_'+$lane+'_extra')]-ne'15'){throw 'Terminal gain not consumed'}}}
    }
    $results+=@{fixture=$job.fixture;entry=$job.entry;pass=$true;fields=$fields}
}
@{pass=$true;count=$results.Count;runtime_sha256=(Get-FileHash -LiteralPath $Runtime).Hash;tests=$results;scope='Actual isolated DOS gain runtime at3000cycles/8086; no host sound or physical-hearing claim'}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $Output 'RESULTS.json')
Write-Output ('PASS native gain '+$results.Count+' bundle/mode/seek/replay checks')
