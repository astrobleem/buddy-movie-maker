param([Parameter(Mandatory=$true)][string]$Fixtures,[Parameter(Mandatory=$true)][string]$Runtime,[Parameter(Mandatory=$true)][string]$Output,
    [string]$PrivateMovie='', [string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe')
$ErrorActionPreference='Stop'
$Output=[IO.Path]::GetFullPath($Output);$Fixtures=(Resolve-Path -LiteralPath $Fixtures).Path;$Runtime=(Resolve-Path -LiteralPath $Runtime).Path
if(Test-Path -LiteralPath $Output){throw 'Use a new native MIDI QA directory.'}
New-Item -ItemType Directory -Path $Output|Out-Null
$cases=@('ALL47','SEEK','REPLAY','BADNOISE');if($PrivateMovie){$PrivateMovie=(Resolve-Path -LiteralPath $PrivateMovie).Path;$cases+='PRIVATE'}
$results=@();$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{foreach($case in $cases){
    $dir=Join-Path $Output $case;New-Item -ItemType Directory -Path $dir|Out-Null
    if($case-eq'PRIVATE'){Copy-Item (Join-Path $PrivateMovie '*') $dir}else{
        Copy-Item -LiteralPath (Join-Path $Fixtures 'ALL47.WZM') -Destination (Join-Path $dir 'MOVIE.WZM');Copy-Item -LiteralPath (Join-Path $Fixtures 'ALL47.WZI') -Destination (Join-Path $dir 'MOVIE.WZI')
        [IO.File]::WriteAllText((Join-Path $dir 'INST.REQ'),'WZI1',[Text.Encoding]::ASCII)
        $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZV')))
        try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZV2'));$w.Write([ushort]256);$w.Write([ushort]160);$w.Write([ushort]4);$w.Write([ushort]24);$w.Write([int]48);$w.Write([int]12000);$w.Write([int]20480);for($i=0;$i-lt48;$i++){$w.Write([byte[]]::new(20480))}}finally{$w.Dispose()}
        Copy-Item -LiteralPath $Runtime -Destination (Join-Path $dir 'MOVPLAY.EXE')
    }
    $playerArguments='';if($case-eq'SEEK'){$w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.CUE')));try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZC1'));$w.Write([int]12000);$w.Write([int]1550);$w.Write([int]2000)}finally{$w.Dispose()};$playerArguments='/R'}
    if($case-eq'BADNOISE'){$path=Join-Path $dir 'MOVIE.WZM';$b=[IO.File]::ReadAllBytes($path);$b[27]=34;[IO.File]::WriteAllBytes($path,$b)}
    $batch="@echo off`r`nMOVPLAY $playerArguments`r`n";if($case-eq'REPLAY'){$batch+="copy MOVPLAY.LOG FIRST.LOG`r`nMOVPLAY`r`n"};$batch+="echo RETURNED > RETURNED.TXT`r`nexit`r`n";[IO.File]::WriteAllText((Join-Path $dir 'RUN.BAT'),$batch,[Text.Encoding]::ASCII)
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
mount C "$dir"
C:
RUN.BAT
"@
    $cnf=Join-Path $dir 'RUN.CNF';[IO.File]::WriteAllText($cnf,$config,[Text.Encoding]::ASCII)
    $watch=[Diagnostics.Stopwatch]::StartNew();$p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
    try{if(!$p.WaitForExit($(if($case-eq'PRIVATE'){110000}else{35000}))){$p.Kill();throw ('Own native MIDI test timed out: '+$case)}}finally{if(!$p.HasExited){$p.Kill()}}
    $watch.Stop();if(!(Test-Path (Join-Path $dir 'RETURNED.TXT'))){throw 'No DOS return marker'}
    $lines=Get-Content (Join-Path $dir 'MOVPLAY.LOG');$fields=@{};foreach($line in $lines){if($line.Contains('=')){$k,$v=$line.Split('=',2);$fields[$k]=$v}}
    $expectedError=if($case-eq'BADNOISE'){'25'}else{'0'}
    if($fields.error-ne$expectedError-or$fields.sound_mask_after_stop-ne'0'-or$fields.speaker_bits_after_stop-ne'0'-or$fields.old_mode-ne$fields.restored_mode){throw ('Native MIDI error/cleanup failure: '+$case)}
    if($case-eq'BADNOISE'){if($fields.psg_writes-ne'0'){throw 'Malformed initial noise wrote to PSG'}}else{
        if($lines[0]-ne'Complete'-or$fields.pit_required-ne'0'-or$fields.noise_tone_clock_writes-ne'0'-or[int]$fields.noise_resets-le0){throw ('Native MIDI playback/noise isolation failure: '+$case)}
        if($case-eq'ALL47'-and($fields.frames-ne'48'-or$fields.dropped_frames-ne'0'-or[int]$fields.noise_resets-ne47)){throw 'All 47 GM attacks were not rendered/reset'}
        if($case-eq'SEEK'-and($fields.play_start_ms-ne'1550'-or$fields.play_end_ms-ne'2000'-or[int]$fields.prerolled_records-le0)){throw 'Range seek failed'}
        if($case-eq'REPLAY'){$first=Get-Content (Join-Path $dir 'FIRST.LOG');if($first[0]-ne'Complete'-or!($first-contains'noise_resets=47')-or$fields.noise_resets-ne'47'){throw 'Fresh replay differs'}}
    }
    $results+=@{name=$case;pass=$true;wall_seconds=$watch.Elapsed.TotalSeconds;fields=$fields};Write-Output ('PASS native MIDI '+$case+': '+$watch.Elapsed.TotalSeconds+' wall seconds; resets '+$fields.noise_resets)
}}finally{$lease.Dispose()}
@{pass=$true;tests=$results;runtime_sha256=(Get-FileHash $Runtime).Hash;scope='Actual player, fixed 3000 DOSBox-X cycles/8086_prefetch, no host sound; no physical hardware/hearing claim; fades not exported'}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $Output 'RESULTS.json')
