param(
    [Parameter(Mandatory=$true)][string]$Assembly,
    [Parameter(Mandatory=$true)][string]$Runtime,
    [Parameter(Mandatory=$true)][string]$Speech,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe',
    [int]$Cycles=3000
)
$ErrorActionPreference='Stop'
$Runtime=(Resolve-Path -LiteralPath $Runtime).Path;$Speech=(Resolve-Path -LiteralPath $Speech).Path
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new full-length QA directory.'}
Add-Type -Path (Resolve-Path -LiteralPath $Assembly).Path
New-Item -ItemType Directory $Output|Out-Null
$rest='[[R1 R1]8]8 [[R1 R1]8]8 [R1]8 [R1]8 [R1]8 [R1]8 [R1]8 R1 R2 R1 '
# Each part: 1s opening, 597s rests, 2s final passage. Speech is inside the late rest.
$source="MML3`n[A]`nT120 C4 D4 ${rest}@LEAD C4 D4 E4 F4`n[B]`nT120 E2 ${rest}E1`n[C]`nT120 G2 ${rest}G1`n[N]`nT120 N38/4 R4 ${rest}[N42/4]4`n[P]`nT120 G4 A4 ${rest}E4 F4 G4 A4`n"
$score=[BuddyMovieMaker.MmlScore]::Compile($source,600000,0,$true)
if($score.ScoreMs-ne600000){throw 'Full-length score duration differs.'}
[IO.File]::WriteAllText((Join-Path $Output 'SCORE.MML'),$source,[Text.Encoding]::ASCII)
[IO.File]::WriteAllBytes((Join-Path $Output 'MOVIE.WZM'),$score.Music)
[IO.File]::WriteAllBytes((Join-Path $Output 'MOVIE.WZI'),$score.Instruments)
[IO.File]::WriteAllBytes((Join-Path $Output 'MOVIE.WZP'),$score.Pit)
[IO.File]::WriteAllText((Join-Path $Output 'INST.REQ'),'WZI1',[Text.Encoding]::ASCII)
[IO.File]::WriteAllText((Join-Path $Output 'PIT.REQ'),'WZP1',[Text.Encoding]::ASCII)
$pcm=[IO.File]::ReadAllBytes($Speech)
if($pcm.Length-ne2420 -or [Text.Encoding]::ASCII.GetString($pcm,0,4)-ne'SPC1' -or [BitConverter]::ToUInt16($pcm,4)-ne1){throw 'Expected one qualified 400ms/2400-sample speech fixture.'}
[Array]::Copy([BitConverter]::GetBytes([int]596300),0,$pcm,8,4)
[Array]::Copy([BitConverter]::GetBytes([int]596700),0,$pcm,12,4)
[BuddyMovieMaker.SpeechAudio]::ValidateMusicWindow($score.Music,596300,596700,600000)
[BuddyMovieMaker.SpeechAudio]::ValidatePitWindow($score.Pit,596300,596700,600000)
[IO.File]::WriteAllBytes((Join-Path $Output 'SPEECH.PCM'),$pcm)
$w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $Output 'MOVIE.WZV')))
try{
    $w.Write([Text.Encoding]::ASCII.GetBytes('WZV3'));$w.Write([ushort]256);$w.Write([ushort]160);$w.Write([ushort]4);$w.Write([ushort]24);$w.Write([uint32]2400);$w.Write([uint32]600000);$w.Write([uint32]20480)
    for($frame=0;$frame-lt2400;$frame++){$pixels=[byte[]]::new(20480);[Array]::Fill($pixels,[byte](($frame%16)*17));$w.Write($pixels)}
}finally{$w.Dispose()}
[IO.File]::WriteAllText((Join-Path $Output 'MOVIE.LRC'),"0|FULL TEN MINUTE FIXTURE`r`n595000|LATE SPEECH AND PIT NEXT`r`n598000|FINAL PSG AND PIT PASSAGE`r`n",[Text.Encoding]::ASCII)
Copy-Item -LiteralPath $Runtime -Destination (Join-Path $Output 'MOVPLAY.EXE')
[IO.File]::WriteAllText((Join-Path $Output 'RUN.BAT'),"@echo off`r`nMOVPLAY /P`r`necho RETURNED > RETURNED.TXT`r`nexit`r`n",[Text.Encoding]::ASCII)
$config=@"
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
mount C "$Output"
C:
RUN.BAT
"@
$cnf=Join-Path $Output 'RUN.CNF';[IO.File]::WriteAllText($cnf,$config,[Text.Encoding]::ASCII)
$hashes=@{};foreach($file in Get-ChildItem -LiteralPath $Output -File){$hashes[$file.Name]=(Get-FileHash -LiteralPath $file.FullName).Hash}
$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$p=$null
try{
    $started=[DateTime]::UtcNow;$watch=[Diagnostics.Stopwatch]::StartNew()
    $p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
    Write-Output ('START full 600s wall-clock run: '+$started.ToString('o')+'; fixed '+$Cycles+' cycles; shared lock held.')
    $next=45
    while(!$p.WaitForExit(1000)){
        if($watch.Elapsed.TotalSeconds-ge750){$p.Kill();throw 'Own full-length emulator run exceeded 750-second bound.'}
        if($watch.Elapsed.TotalSeconds-ge$next){Write-Output ('RUNNING '+[int]$watch.Elapsed.TotalSeconds+' wall seconds; own emulator PID '+$p.Id);$next+=45}
    }
    $watch.Stop()
    if(!(Test-Path -LiteralPath (Join-Path $Output 'RETURNED.TXT'))){throw 'Full-length player did not return to DOS.'}
    $lines=Get-Content -LiteralPath (Join-Path $Output 'MOVPLAY.LOG');$fields=@{}
    foreach($line in $lines){if($line.Contains('=')){$k,$v=$line.Split('=',2);$fields[$k]=$v}}
    if($lines[0]-ne'Complete'||$fields.error-ne'0'||$fields.duration_ms-ne'600000'||$fields.play_start_ms-ne'0'||$fields.play_end_ms-ne'600000'||$fields.frames-ne'2400'||$fields.old_mode-ne$fields.restored_mode||$fields.sound_mask_after_stop-ne'0'||$fields.speaker_bits_after_stop-ne'0'){throw 'Full-length playback/completion/cleanup failed.'}
    if([int]$fields.elapsed_ms-lt600000 -or [int]$fields.elapsed_ms-gt600110 -or $watch.Elapsed.TotalSeconds-lt590 -or $watch.Elapsed.TotalSeconds-gt650){throw 'Full-length movie clock disagrees with the bounded wall-clock run.'}
    if($fields.speech_completed-ne'1'||[int]$fields.speech_samples-le0||$fields.speech_avoided_music-ne'0'||[int]$fields.pit_records-ne[BitConverter]::ToUInt16($score.Pit,12)||$fields.noise_tone_clock_writes-ne'0'){throw 'Late speech/PIT/noise validation failed.'}
    if([int]$fields.pit_applied-lt8||$fields.pit_skipped-ne'0'||[int]$fields.music_events_read-ne[BitConverter]::ToUInt32($score.Music,8)||[int]$fields.music_events_applied-lt7||$fields.music_events_skipped-ne'0'||$fields.caption_updates-ne'3'||([int]$fields.speech_samples+[int]$fields.speech_head_skipped_samples)-ne2400){throw 'Full-length final notes, captions or speech accounting failed.'}
    @{pass=$true;duration_ms=600000;wall_seconds=$watch.Elapsed.TotalSeconds;started_utc=$started.ToString('o');completed_utc=[DateTime]::UtcNow.ToString('o');cycle_budget=$Cycles;cpu='8086_prefetch';core='normal';memory_kib=640;emulator_sha256=(Get-FileHash -LiteralPath $Dosbox).Hash;runtime_sha256=(Get-FileHash -LiteralPath $Runtime).Hash;config_sha256=$hashes['RUN.CNF'];input_hashes=$hashes;fields=$fields;scope='Actual full ten-minute wall-clock synthetic run; changing RGBI frames, early/final PSG+PIT, speech at 596.3s, final cleanup; emulated cycles are not a calibrated 4.77MHz hardware claim; audio capture/hearing/physical hardware excluded'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Output 'RESULTS.json')
    Write-Output ('PASS full-length: '+$watch.Elapsed.TotalSeconds+' wall seconds; elapsed '+$fields.elapsed_ms+'ms; frames '+$fields.frames+'; dropped '+$fields.dropped_frames+'; speech samples '+$fields.speech_samples)
}finally{if($p-and!$p.HasExited){$p.Kill()};$lease.Dispose()}
