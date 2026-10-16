param([Parameter(Mandatory=$true)][string]$Exports,[Parameter(Mandatory=$true)][string]$Runtime,
    [Parameter(Mandatory=$true)][string]$Output,[string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe',
    [Parameter(Mandatory=$true)][string]$StopKey,
    [string]$Busy='')
$ErrorActionPreference='Stop';$Exports=(Resolve-Path -LiteralPath $Exports).Path;$Runtime=(Resolve-Path -LiteralPath $Runtime).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new actual gain integration directory'}
New-Item -ItemType Directory $Output|Out-Null
$cases=@('SPEECH','REPLAY','STOP','BADGUARD','TAIL17','TAIL1','TAIL54','TAIL55','C02','PART1','PART2');if($Busy){$Busy=(Resolve-Path -LiteralPath $Busy).Path;$cases+='BUSY'}
$results=@()
foreach($case in $cases){
    $source=switch($case){C02{'PRIVATE-C02'};PART1{'PRIVATE-PART1'};PART2{'PRIVATE-PART2'};default{'SPEECH'}}
    $dir=Join-Path $Output $case;New-Item -ItemType Directory $dir|Out-Null;Copy-Item -Path (Join-Path $Exports ($source+'/*')) -Destination $dir
    Copy-Item -LiteralPath $Runtime -Destination (Join-Path $dir 'MOVPLAY.EXE') -Force
    $flags='';$batch="@echo off`r`n"
    if($case-eq'STOP'){Copy-Item -LiteralPath $StopKey -Destination (Join-Path $dir 'STOPKEY.EXE');$batch+="STOPKEY`r`n"}
    if($case-eq'BUSY'){Copy-Item -LiteralPath $Busy -Destination (Join-Path $dir 'BUSY61.EXE');$batch+="BUSY61 1`r`n"}
    if($case-eq'BADGUARD'){$path=Join-Path $dir 'SPEECH.PCM';$b=[IO.File]::ReadAllBytes($path);[BitConverter]::GetBytes([uint32]400).CopyTo($b,8);[BitConverter]::GetBytes([uint32]800).CopyTo($b,12);[IO.File]::WriteAllBytes($path,$b)}
    if($case-like'TAIL*'){
        # Synthetic1.25s plus exact partial interval, with a distinct final RGBI frame.
        $tail=[int]$case.Substring(4);$d=1250+$tail;$count=6
        $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZV')))
        try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZV4'));$w.Write([ushort]256);$w.Write([ushort]160);$w.Write([ushort]4);$w.Write([ushort]24);$w.Write([uint32]$count);$w.Write([uint32]$d);$w.Write([uint32]20480);for($i=0;$i-lt$count;$i++){$frame=[byte[]]::new(20480);if($i-eq5){[Array]::Fill[byte]($frame,0x33)};$w.Write($frame)}}finally{$w.Dispose()}
        $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZM')))
        try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZM3'));$w.Write([ushort]20);$w.Write([ushort]14);$w.Write([uint32]3);$w.Write([uint32]$d);$w.Write([uint32]0);$w.Write([uint32]0);$w.Write([byte[]]@(69,0,0,0,100,0,0,0,1,0));$w.Write([uint32]($d-12));$w.Write([byte[]]::new(10));$w.Write([uint32]$d);$w.Write([byte[]]::new(10))}finally{$w.Dispose()}
        $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZI')));try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZI1'));$w.Write([ushort]20);$w.Write([ushort]8);$w.Write([uint32]1);$w.Write([uint32]$d);$w.Write([ushort]2);$w.Write([ushort]258);$w.Write([uint32]0);$w.Write([byte[]]@(16,16,16,0))}finally{$w.Dispose()}
        $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZG')));try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZG1'));$w.Write([ushort]20);$w.Write([ushort]8);$w.Write([uint32]2);$w.Write([uint32]$d);$w.Write([uint32]0);$w.Write([uint32]0);$w.Write([byte[]]::new(4));$w.Write([uint32]$d);$w.Write([byte[]]@(15,15,15,15))}finally{$w.Dispose()}
        # Original speech/captions do not fit the synthetic short container;
        # stage tail cases without those optional files instead of deleting.
        $tailOnly=Join-Path $Output ($case+'RUN');New-Item -ItemType Directory $tailOnly|Out-Null
        foreach($f in Get-ChildItem -LiteralPath $dir -File|Where-Object{$_.Name-in@('MOVIE.WZV','MOVIE.WZM','MOVIE.WZI','MOVIE.WZG','INST.REQ','GAIN.REQ','MOVPLAY.EXE')}){Copy-Item -LiteralPath $f.FullName -Destination $tailOnly}
        $dir=$tailOnly
    }
    if($case-in@('PART1','PART2')){
        $d=[BitConverter]::ToUInt32([IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZM')),12);$w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.CUE')))
        try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZC1'));$w.Write([uint32]$d);$w.Write([uint32]($d-2000));$w.Write([uint32]$d)}finally{$w.Dispose()};$flags='/R'
    }
    $batch+="MOVPLAY $flags`r`n";if($case-eq'REPLAY'){$batch+="copy MOVPLAY.LOG FIRST.LOG > nul`r`nMOVPLAY`r`n"};if($case-eq'BUSY'){$batch+="BUSY61 0`r`n"};$batch+="echo RETURNED > RETURNED.TXT`r`nexit`r`n"
    [IO.File]::WriteAllText((Join-Path $dir 'RUN.BAT'),$batch,[Text.Encoding]::ASCII)
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
cycles=fixed3000
fpu=false
[dos]
xms=false
ems=false
umb=false
[mixer]
nosound=true
[midi]
mididevice=none
[autoexec]
mount C "$dir"
C:
RUN.BAT
"@
    $config=$config.Replace('cycles=fixed3000','cycles=fixed 3000');$configPath=Join-Path $dir 'RUN.CNF';[IO.File]::WriteAllText($configPath,$config,[Text.Encoding]::ASCII)
    $watch=[Diagnostics.Stopwatch]::StartNew();$lease=$null;$deadline=[DateTime]::UtcNow.AddSeconds(15)
    while(!$lease){try{$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{if([DateTime]::UtcNow-ge$deadline){throw 'Shared emulator lease busy; no guest started'};Start-Sleep -Milliseconds 200}}
    try{
        $p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$configPath+'"')) -WindowStyle Hidden -PassThru
        try{$limit=if($case-eq'C02'){115}else{20};while(!$p.WaitForExit(1000)){if($watch.Elapsed.TotalSeconds-gt$limit){throw ('Own gain integration timed out: '+$case)}}}finally{if(!$p.HasExited){$p.Kill()}}
    }finally{$lease.Dispose()}
    $watch.Stop();if(!(Test-Path (Join-Path $dir 'RETURNED.TXT'))){throw 'No native return marker'}
    $lines=Get-Content (Join-Path $dir 'MOVPLAY.LOG');$f=@{};foreach($line in $lines){if($line.Contains('=')){$k,$v=$line.Split('=',2);$f[$k]=$v}}
    $expectedError=switch($case){BADGUARD{'83'};BUSY{'87'};default{'0'}}
    if($f.error-ne$expectedError-or$f.sound_mask_after_stop-ne'0'-or$f.old_mode-ne$f.restored_mode){throw ('Error/cleanup mismatch '+$case)}
    if($case-eq'BUSY'){if($f.psg_writes-ne'0'-or$f.speaker_bits_after_stop-ne'3'){throw 'Unowned busy output changed'}}elseif($f.speaker_bits_after_stop-ne'0'){throw 'Speaker cleanup mismatch'}
    if($case-eq'BADGUARD'-and($f.psg_writes-ne'0'-or$f.frames-ne'0')){throw 'Unsafe speech emitted output'}
    if($case-in@('SPEECH','REPLAY')){
        if($lines[0]-ne'Complete'-or$f.speech_completed-ne'1'-or[int]$f.speech_samples-le0-or$f.speech_avoided_music-ne'0'-or$f.voice_0_attacks-ne'2'){throw 'Actual gain/PWM/restoration failed'}
        $restore=0;for($j=0;$j-lt[int]$f.gain_trace_count;$j++){if($f[('gain_'+$j+'_time')]-eq'1850'){$restore=$j}}
        $v=$f[('gain_'+$restore+'_lane_0')].Split(',');if($v[3]-ne'3'-or$v[4]-ne'8'){throw 'Post-speech selected gain not restored'}
        if($case-eq'REPLAY'-and(Get-Content (Join-Path $dir 'FIRST.LOG'))[0]-ne'Complete'){throw 'Fresh replay failed'}
    }
    if($case-eq'STOP'-and($lines[0]-ne'Stopped'-or$f.speech_completed-ne'0'-or[int]$f.speech_samples-le0)){throw 'Escape did not stop actual PWM'}
    if($case-like'TAIL*'){
        if($f.frames-ne'6'-or$f.dropped_frames-ne'0'-or[int]$f.last_frame_advance_ms-gt55-or$f.gain_applied-ne'2'-or$f.music_events_applied-ne'3'){throw ('Final partial interval/event loss '+$case)}
        if([int]$f.final_rest_dispatch_ms-lt[int]$f.final_rest_target_ms-or[int]$f.final_rest_dispatch_ms-[int]$f.final_rest_target_ms-gt55){throw 'Authored rest dispatch exceeds BIOS bound'}
    }
    if($case-eq'C02'){
        $m=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZM'));$g=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZG'));$v=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZV'))
        if([int]$f.music_events_applied-ne[BitConverter]::ToInt32($m,8)-or[int]$f.gain_applied-ne[BitConverter]::ToInt32($g,8)-or[int]$f.frames-ne[BitConverter]::ToInt32($v,12)-or$f.noise_resets-ne'73'-or$f.dropped_frames-ne'0'){throw 'Private source attack/frame/terminal counts differ'}
    }
    $results+=@{name=$case;pass=$true;wall_seconds=$watch.Elapsed.TotalSeconds;fields=$f};Write-Output ('PASS actual gain '+$case+'; lease released; '+$watch.Elapsed.TotalSeconds+' wall seconds')
}
@{pass=$true;count=$results.Count;tests=$results;runtime_sha256=(Get-FileHash -LiteralPath $Runtime).Hash;scope='Actual export/PWM/escape/busy and source-matched private C02 plus segment tail seeks; fixed3000/8086/640KiB; BIOS dispatch bounds, no physical-hearing claim';lease_released=$true}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $Output 'RESULTS.json')
