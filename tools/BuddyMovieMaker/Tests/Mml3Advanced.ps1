param(
    [Parameter(Mandatory=$true)][string]$Fixtures,
    [Parameter(Mandatory=$true)][string]$Runtime,
    [Parameter(Mandatory=$true)][string]$Assembly,
    [Parameter(Mandatory=$true)][string]$Helpers,
    [Parameter(Mandatory=$true)][string]$StopKey,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe'
)
$ErrorActionPreference='Stop'
$Fixtures=(Resolve-Path -LiteralPath $Fixtures).Path;$Runtime=(Resolve-Path -LiteralPath $Runtime).Path
$Helpers=(Resolve-Path -LiteralPath $Helpers).Path;$StopKey=(Resolve-Path -LiteralPath $StopKey).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new advanced QA directory.'}
Add-Type -Path (Resolve-Path -LiteralPath $Assembly).Path
New-Item -ItemType Directory $Output|Out-Null
$results=@()
$rest='T120 [[R1 R1]8]8 [[R1 R1]8]8 [R1]8 [R1]8 [R1]8 [R1]8 [R1]8 R1 R1 R1 R2 '
$score=[BuddyMovieMaker.MmlScore]::Compile("MML3`n[A]`n${rest}C4 D4`n[P]`n${rest}C4 D4`n",600000,0,$false)
if($score.ScoreMs-ne600000){throw 'Long fixture duration differs.'}
foreach($case in @('PITMIX','PITSPEAK','PITREST','PITEMPTY','STOP','REPLAY','BUSY','TAIL600','HELDSEEK')){
    $dir=Join-Path $Output $case;New-Item -ItemType Directory $dir|Out-Null
    if($case -in @('TAIL600','HELDSEEK')){
        [IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZM'),$score.Music);[IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZI'),$score.Instruments);[IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZP'),$score.Pit)
        [IO.File]::WriteAllText((Join-Path $dir 'INST.REQ'),'WZI1',[Text.Encoding]::ASCII);[IO.File]::WriteAllText((Join-Path $dir 'PIT.REQ'),'WZP1',[Text.Encoding]::ASCII)
        $file=[IO.File]::Create((Join-Path $dir 'MOVIE.WZV'));$w=[IO.BinaryWriter]::new($file)
        $w.Write([Text.Encoding]::ASCII.GetBytes('WZV3'));$w.Write([ushort]256);$w.Write([ushort]160);$w.Write([ushort]4);$w.Write([ushort]24);$w.Write([uint32]2400);$w.Write([uint32]600000);$w.Write([uint32]20480);$w.Flush();$file.SetLength(49152024);$w.Dispose()
        $start=if($case-eq'TAIL600'){599000}else{599250};$end=if($case-eq'TAIL600'){600000}else{599750}
        $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.CUE')));$w.Write([Text.Encoding]::ASCII.GetBytes('WZC1'));$w.Write([uint32]600000);$w.Write([uint32]$start);$w.Write([uint32]$end);$w.Dispose()
    }else{
        $source=switch($case){'STOP'{'PITSPEAK'} 'REPLAY'{'PITMIX'} 'BUSY'{'PITMIX'} default {$case}}
        Copy-Item -Path (Join-Path $Fixtures ($source+'\*')) -Destination $dir
    }
    Copy-Item -LiteralPath $Runtime -Destination (Join-Path $dir 'MOVPLAY.EXE')
    if($case-eq'STOP'){Copy-Item -LiteralPath $StopKey -Destination (Join-Path $dir 'STOPKEY.EXE')}
    if($case-eq'BUSY'){Copy-Item -LiteralPath (Join-Path $Helpers 'BUSY61.EXE') -Destination $dir}
}
$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    foreach($case in @('PITMIX','PITSPEAK','PITREST','PITEMPTY','STOP','REPLAY','BUSY','TAIL600','HELDSEEK')){
        $dir=Join-Path $Output $case;$capture=Join-Path $dir 'captures';New-Item -ItemType Directory $capture|Out-Null
        $batch="@echo off`r`n"
        if($case-eq'STOP'){$batch+="STOPKEY`r`n"}
        if($case-eq'BUSY'){$batch+="BUSY61 1`r`n"}
        $flags=if($case-in@('TAIL600','HELDSEEK')){' /P /R'}else{' /P'}
        $batch+="DX-CAPTURE /A /M MOVPLAY.EXE$flags`r`n"
        if($case-eq'REPLAY'){$batch+="copy MOVPLAY.LOG FIRST.LOG`r`nMOVPLAY /P`r`n"}
        if($case-eq'BUSY'){$batch+="BUSY61 0`r`n"}
        $batch+="echo RETURNED > RETURNED.TXT`r`nexit`r`n"
        [IO.File]::WriteAllText((Join-Path $dir 'RUN.BAT'),$batch,[Text.Encoding]::ASCII)
        $config=@"
[sdl]
fullscreen=false
output=surface
[dosbox]
machine=tandy
memsize=0
memsizekb=640
captures=$capture
[cpu]
core=normal
cputype=8086_prefetch
cycles=fixed 3000
fpu=false
[dos]
xms=false
ems=false
umb=false
[mixer]
nosound=false
[midi]
mididevice=none
[autoexec]
mount C "$dir"
C:
RUN.BAT
"@
        $cnf=Join-Path $dir 'RUN.CNF';[IO.File]::WriteAllText($cnf,$config,[Text.Encoding]::ASCII)
        $p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
        if(!$p.WaitForExit(30000)){$p.Kill();throw ($case+' own advanced run timed out.')}
        if(!(Test-Path -LiteralPath (Join-Path $dir 'RETURNED.TXT'))){throw ($case+' did not return to DOS.')}
        $lines=Get-Content -LiteralPath (Join-Path $dir 'MOVPLAY.LOG');$f=@{}
        foreach($line in $lines){if($line.Contains('=')){$k,$v=$line.Split('=',2);$f[$k]=$v}}
        if($case-eq'BUSY'){
            if($f.error-ne'87'||$f.psg_writes-ne'0'||$f.speaker_bits_after_stop-ne'3'||(Test-Path -LiteralPath (Join-Path $dir 'DOSSTART.LOG'))){throw 'Busy refusal changed unowned output.'}
        }else{
            if($f.error-ne'0'||$f.sound_mask_after_stop-ne'0'||$f.speaker_bits_after_stop-ne'0'||$f.old_mode-ne$f.restored_mode){throw ($case+' cleanup failed.')}
            $reason=if($case-eq'STOP'){'Stopped'}else{'Complete'};if($lines[0]-ne$reason){throw ($case+' wrong exit reason.')}
            if($case-eq'PITSPEAK' -and ([int]$f.speech_samples-le0||$f.speech_completed-ne'1'||$f.speech_avoided_music-ne'0')){throw 'Actual sampled speech did not complete.'}
            if($case-eq'STOP' -and ($f.speech_completed-ne'0'||$f.speech_samples-eq'0')){throw 'Escape did not interrupt actual PWM.'}
            if($case-in@('TAIL600','HELDSEEK')){
                $expected=if($case-eq'TAIL600'){1000}else{500};if([int]$f.duration_ms-ne600000||[int]$f.run_elapsed_ms-lt$expected||[int]$f.run_elapsed_ms-gt$expected+110){throw ($case+' long-duration arithmetic/clock differs.')}
            }
            if($case-eq'REPLAY' -and (Get-Content -LiteralPath (Join-Path $dir 'FIRST.LOG'))[0]-ne'Complete'){throw 'First replay failed.'}
        }
        $results+=@{case=$case;pass=$true;fields=$f;captures=(Get-ChildItem -LiteralPath $capture -File|Select-Object -ExpandProperty Name)}
        Write-Output ($case+': PASS')
    }
    @{tests=$results;count=$results.Count;runtime_sha256=(Get-FileHash -LiteralPath $Runtime).Hash;scope='Actual Maker exports, PWM escape, replay, unowned busy refusal, 600-second container and held-note late seek; captured emulator audio; not a full ten-minute wall-clock run or physical-hardware claim'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Output 'RESULTS.json')
}finally{$lease.Dispose()}
