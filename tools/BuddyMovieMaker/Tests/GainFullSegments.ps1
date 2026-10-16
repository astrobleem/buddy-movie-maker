param([Parameter(Mandatory=$true)][string]$Handoff,[Parameter(Mandatory=$true)][string]$Output,
    [string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe')
$ErrorActionPreference='Stop';$Handoff=(Resolve-Path -LiteralPath $Handoff).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new full-segment QA directory'}
New-Item -ItemType Directory $Output|Out-Null
$handoffHash=(Get-FileHash -LiteralPath (Join-Path $Handoff 'HANDOFF.json')).Hash

$results=@()
foreach($name in @('PART1','PART2')){
    $source=Join-Path $Handoff ('EXPORTS/'+$name);$dir=Join-Path $Output $name
    $manifestHash=(Get-FileHash -LiteralPath (Join-Path $source 'MANIFEST.JSON')).Hash
    $manifest=Get-Content -LiteralPath (Join-Path $source 'MANIFEST.JSON') -Raw|ConvertFrom-Json
    foreach($entry in $manifest.files.PSObject.Properties){if((Get-FileHash -LiteralPath (Join-Path $source $entry.Name)).Hash-ne$entry.Value){throw 'Immutable source inventory changed'}}
    $ownership=Get-Content -LiteralPath (Join-Path $source 'OWNERSHIP-REPORT.JSON') -Raw|ConvertFrom-Json
    if($ownership.DiscardedInstances-ne0-or$ownership.ToneReductionStates-ne0-or$ownership.DrumReductionStates-ne0){throw 'Unexpected source arbitration discontinuity'}
    $expectedSeeds=if($name-eq'PART2'){2}else{0};if($ownership.ClippedHeldSeeds-ne$expectedSeeds){throw 'Crop seed count differs'}
    $music=[IO.File]::ReadAllBytes((Join-Path $source 'MOVIE.WZM'));$gain=[IO.File]::ReadAllBytes((Join-Path $source 'MOVIE.WZG'))
    $records=[BitConverter]::ToUInt32($music,8);$gainRecords=[BitConverter]::ToUInt32($gain,8);$attacks=[int[]]@(0,0,0,0);$notes=[byte[]]::new(4);$velocities=[byte[]]::new(4);$authoredRest=0
    for($n=0;$n-lt$records;$n++){$at=20+14*$n;$time=[BitConverter]::ToUInt32($music,$at);$wasActive=($notes|Where-Object{$_-ne0}).Count-gt0;$isActive=$false
        foreach($lane in 0..3){$note=$music[$at+4+$lane];$velocity=$music[$at+8+$lane];if($note-and($note-ne$notes[$lane]-or$velocity-ne$velocities[$lane]-or($music[$at+12]-band(1-shl$lane)))){$attacks[$lane]++};$notes[$lane]=$note;$velocities[$lane]=$velocity;if($note){$isActive=$true}}
        if($wasActive-and!$isActive){$authoredRest=$time}
    }
    if(($attacks|Measure-Object -Sum).Sum-ne$ownership.SelectedNotes){throw 'Expected stream attacks do not cover every selected source note'}
    New-Item -ItemType Directory $dir|Out-Null;Copy-Item -Path (Join-Path $source '*') -Destination $dir
    if((Get-FileHash -LiteralPath (Join-Path $dir 'MOVPLAY.EXE')).Hash-ne'504B852BCE5D14F85EB52E3B61F3B85A8D13CFD1E0D150D7C2042747632354A2'){throw 'Unpinned DOS player'}
    # A fresh copy has no /R range sidecar; default PLAY uses the whole container.
    if(Test-Path (Join-Path $dir 'MOVIE.CUE')){throw 'Unexpected range sidecar in immutable full candidate'}
    [IO.File]::WriteAllText((Join-Path $dir 'RUN.BAT'),"@echo off`r`nMOVPLAY`r`necho RETURNED > RETURNED.TXT`r`nexit`r`n",[Text.Encoding]::ASCII)
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
    $cnf=Join-Path $dir 'RUN.CNF';[IO.File]::WriteAllText($cnf,$config,[Text.Encoding]::ASCII)
    $lease=$null;$deadline=[DateTime]::UtcNow.AddSeconds(15)
    while(!$lease){try{$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{if([DateTime]::UtcNow-ge$deadline){throw 'Shared lease busy; no guest started'};Start-Sleep -Milliseconds 200}}
    $watch=[Diagnostics.Stopwatch]::StartNew();$nextProgress=30
    try{
        $p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
        try{while(!$p.WaitForExit(1000)){
            if($watch.Elapsed.TotalSeconds-gt$manifest.duration_ms/1000+30){throw ('Own full segment timed out: '+$name)}
            if($watch.Elapsed.TotalSeconds-ge$nextProgress){Write-Output ($name+' full playback still running: '+[int]$watch.Elapsed.TotalSeconds+'s / '+($manifest.duration_ms/1000)+'s');$nextProgress+=30}
        }}finally{if(!$p.HasExited){$p.Kill()}}
    }finally{$lease.Dispose();Write-Output ($name+' exclusive emulator lease released')}
    $watch.Stop();if(!(Test-Path (Join-Path $dir 'RETURNED.TXT'))){throw 'Full guest did not return'}
    $lines=Get-Content -LiteralPath (Join-Path $dir 'MOVPLAY.LOG');$f=@{};foreach($line in $lines){if($line.Contains('=')){$k,$v=$line.Split('=',2);$f[$k]=$v}}
    if($lines[0]-ne'Complete'-or$f.error-ne'0'-or$f.full_range-ne'1'-or$f.play_start_ms-ne'0'-or[int]$f.play_end_ms-ne$manifest.duration_ms){throw 'Not full-duration completion'}
    if([int]$f.music_events_read-ne$records-or[int]$f.music_events_applied-ne$records-or$f.music_events_skipped-ne'0'-or[int]$f.gain_records-ne$gainRecords-or[int]$f.gain_applied-ne$gainRecords){throw 'Lost music/gain records or terminal EOF'}
    foreach($lane in 0..3){if([int]$f[('voice_'+$lane+'_attacks')]-ne$attacks[$lane]-or$f[('voice_'+$lane+'_extra')]-ne'15'){throw 'Lost source attack or final gain snapshot'}}
    if([int]$f.noise_resets-ne$attacks[3]-or$f.noise_tone_clock_writes-ne'0'){throw 'Lost/restarted/coupled drum attacks'}
    if([int]$f.frames-ne$manifest.frames-or$f.dropped_frames-ne'0'){throw 'Lost source video frames'}
    if($f.sound_mask_after_stop-ne'0'-or$f.speaker_bits_after_stop-ne'0'-or$f.old_mode-ne$f.restored_mode){throw 'Final cleanup failed'}
    if([int]$f.final_rest_target_ms-ne$authoredRest-or[int]$f.final_rest_dispatch_ms-lt$authoredRest-or[int]$f.final_rest_dispatch_ms-$authoredRest-gt110){throw 'Final authored rest target/dispatch differs or exceeds two BIOS ticks'}
    if([int]$f.elapsed_ms-lt$manifest.duration_ms-or[int]$f.elapsed_ms-$manifest.duration_ms-gt110){throw 'Container completion exceeds two BIOS ticks'}
    if([int]$f.last_frame_advance_ms-gt55){throw 'Final frame exceeded documented early-display maximum'}
    $terminal=[int]$f.gain_trace_count-1
    if([int]$f[('gain_'+$terminal+'_time')]-ne$manifest.duration_ms){throw 'Terminal gain group not traced'}
    foreach($lane in 0..3){$endTrace=$f[('gain_'+$terminal+'_lane_'+$lane)].Split(',');if($endTrace[3]-ne'15'-or$endTrace[4]-ne'15'){throw 'Terminal group not already muted before cleanup'}}
    if((Get-FileHash -LiteralPath (Join-Path $source 'MANIFEST.JSON')).Hash-ne$manifestHash-or(Get-FileHash (Join-Path $Handoff 'HANDOFF.json')).Hash-ne$handoffHash){throw 'Immutable handoff modified'}
    $result=@{name=$name;pass=$true;full_wall_seconds=$watch.Elapsed.TotalSeconds;manifest_sha256=$manifestHash;expected_music_records=$records;expected_gain_records=$gainRecords;expected_lane_attacks=$attacks;authored_final_rest_ms=$authoredRest;dispatch_late_ms=[int]$f.final_rest_dispatch_ms-$authoredRest;container_late_ms=[int]$f.elapsed_ms-$manifest.duration_ms;clipped_held_seeds=$ownership.ClippedHeldSeeds;fields=$f;lease_released=$true}
    $results+=$result;$result|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $dir 'RESULTS.json')
    Write-Output ('PASS full '+$name+': '+$records+' music, '+$gainRecords+' gain, '+$attacks[3]+' drums, '+$manifest.frames+' frames; no lost events')
}
@{pass=$true;count=2;tests=$results;runtime_sha256='504B852BCE5D14F85EB52E3B61F3B85A8D13CFD1E0D150D7C2042747632354A2';handoff_sha256=$handoffHash;scope='Two complete capped private DOS movies, fixed3000/8086/640KiB; no host sound or physical-hearing claim; late dispatch reported separately from loss';lease_released=$true}|ConvertTo-Json -Depth 10|Set-Content -LiteralPath (Join-Path $Output 'RESULTS.json')
