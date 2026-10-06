param(
    [Parameter(Mandatory=$true)][string]$Fixtures,
    [Parameter(Mandatory=$true)][string]$Output,
    [Parameter(Mandatory=$true)][string]$StopKey,
    [int]$Cycles=3000,
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe'
)
$ErrorActionPreference='Stop'
$Fixtures=(Resolve-Path $Fixtures).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new output folder.'}
New-Item -ItemType Directory $Output | Out-Null
$results=@()
$cases=@('SPEECH','SPEECHM','MML','MMLSPEAK','BADSPC','BADPWM','STOP','REPLAY','FLAGS','ENGINE','PROGRAM','RESERVED','TRAILING','COUNT','MISSING','REQ','HELD')
foreach($case in $cases){
    $dir=Join-Path $Output $case;New-Item -ItemType Directory $dir | Out-Null
    $source=switch($case){'SPEECH'{'SPEECH'} 'SPEECHM'{'SPEECHM'} 'MML'{'MML'} default {'MMLSPEAK'}}
    Copy-Item (Join-Path $Fixtures "$source\*") $dir
    $expectedError='0';$expectedReason='Complete'
    if($case -eq 'BADSPC'){$f=[IO.File]::OpenWrite((Join-Path $dir 'SPEECH.PCM'));$f.SetLength($f.Length-1);$f.Dispose();$expectedError='61'}
    if($case -eq 'BADPWM'){$f=[IO.File]::OpenWrite((Join-Path $dir 'SPEECH.PCM'));$f.Position=20;$f.WriteByte(0);$f.Dispose();$expectedError='62'}
    if($case -in @('FLAGS','ENGINE','PROGRAM','RESERVED','TRAILING','COUNT')){
        $path=Join-Path $dir 'MOVIE.WZI';$bytes=[IO.File]::ReadAllBytes($path)
        switch($case){
            'FLAGS'{$bytes[16]=2;$expectedError='71'}
            'ENGINE'{$bytes[18]=3;$expectedError='71'}
            'PROGRAM'{$bytes[24]=1;$expectedError='74'}
            'RESERVED'{$bytes[27]=1;$expectedError='74'}
            'TRAILING'{$bytes+=0;$expectedError='72'}
            'COUNT'{$bytes[8]=0;$bytes[9]=0;$bytes[10]=0;$bytes[11]=0;$expectedError='72'}
        }
        [IO.File]::WriteAllBytes($path,$bytes)
    }
    if($case -eq 'MISSING'){Remove-Item -LiteralPath (Join-Path $dir 'MOVIE.WZI');$expectedError='70'}
    if($case -eq 'REQ'){[IO.File]::WriteAllText((Join-Path $dir 'INST.REQ'),'bad');$expectedError='70'}
    if($case -eq 'HELD'){
        # Held Keys attack at0, command Pad500: must retain Keys snapshot.
        Copy-Item (Join-Path $Fixtures 'MML-CONFORMANCE\PRESETS.WZM') (Join-Path $dir 'MOVIE.WZM') -Force
        $m=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZM'));$m[24]=48;$m[25]=0;$m[26]=0;$m[28]=100;$m[29]=0;$m[30]=0;$m[32]=1;[IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZM'),$m)
        $zi=[byte[]](87,90,73,49,20,0,8,0,2,0,0,0,208,7,0,0,1,0,2,1,0,0,0,0,0,0,0,0,244,1,0,0,48,0,0,0)
        [IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZI'),$zi)
        Remove-Item -LiteralPath (Join-Path $dir 'SPEECH.PCM')
    }
    $commands="@echo off`r`n"
    if($case -eq 'STOP'){Copy-Item -LiteralPath $StopKey -Destination (Join-Path $dir 'STOPKEY.EXE');$commands+="STOPKEY`r`n";$expectedReason='Stopped'}
    $commands+="MOVPLAY`r`n"
    if($case -eq 'REPLAY'){$commands+="copy MOVPLAY.LOG FIRST.LOG`r`nMOVPLAY`r`n"}
    $commands+="echo RETURNED > RETURNED.TXT`r`nexit`r`n"
    [IO.File]::WriteAllText((Join-Path $dir 'START.BAT'),$commands,[Text.Encoding]::ASCII)
    $conf=@"
[sdl]
fullscreen=false
output=surface
[dosbox]
machine=tandy
memsize=0
memsizekb=640
allow more than 640kb base memory=false
[cpu]
core=normal
cputype=8086_prefetch
cycles=fixed $Cycles
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
mount C "$dir"
C:
START.BAT
"@
    $cnf=Join-Path $dir 'RUN.CNF';[IO.File]::WriteAllText($cnf,$conf)
    $p=Start-Process $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
    if(!$p.WaitForExit(30000)){$p.Kill();throw "$case timed out"}
    if(!(Test-Path (Join-Path $dir 'RETURNED.TXT'))){throw "$case did not return"}
    $log=Get-Content (Join-Path $dir 'MOVPLAY.LOG');$fields=@{};foreach($line in $log){if($line.Contains('=')){$k,$v=$line.Split('=',2);$fields[$k]=$v}}
    if($fields.error -ne $expectedError -or $fields.old_mode -ne $fields.restored_mode -or $fields.sound_mask_after_stop -ne '0' -or $fields.speaker_bits_after_stop -ne '0'){throw "$case cleanup/error mismatch"}
    if($expectedError -eq '0'){
        if($log[0] -ne $expectedReason){throw "$case reason mismatch"}
        if($case -in @('SPEECH','SPEECHM','MMLSPEAK','REPLAY')){
            if($fields.speech_clips -ne '1' -or $fields.speech_avoided_music -ne '0' -or [int]$fields.speech_samples -eq 0){throw "$case speech not serviced"}
        }
        if($case -eq 'STOP' -and $fields.clip_0_target -notmatch 'reason=1$'){throw 'Escape did not interrupt inside PWM'}
        if($case -in @('MML','MMLSPEAK','HELD') -and ($fields.expressive -ne '1' -or [int]$fields.synth_passes -eq 0)){throw 'Expressive engine not enabled'}
        if($case -eq 'HELD' -and $fields.voice_0_preset -ne '0'){throw 'Held preset changed with later command'}
        if($case -eq 'REPLAY' -and (Get-Content (Join-Path $dir 'FIRST.LOG'))[0] -ne 'Complete'){throw 'First replay failed'}
    }
    $results+=@{case=$case;cycles=$Cycles;pass=$true;fields=$fields}
    Write-Output "$case : PASS"
}
@{count=$results.Count;tests=$results;scope='Tandy/8086_prefetch640KiB; cycles not a physical4.77MHz calibration; no perceived speech/music certification.'}|ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Output 'RESULTS.json')
