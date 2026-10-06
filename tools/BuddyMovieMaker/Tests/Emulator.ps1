param(
    [Parameter(Mandatory=$true)][string]$Fixtures,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Dosbox = 'C:\Program Files\DOSBox-X\dosbox-x.exe'
)
$ErrorActionPreference = 'Stop'
$Fixtures = (Resolve-Path -LiteralPath $Fixtures).Path
$Output = [IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) { throw 'Use a new emulator output directory.' }
New-Item -ItemType Directory -Path $Output | Out-Null
$results = @()
foreach ($case in @('SILENT','SCORED','TRUNCATED','BADCAP','MISMATCH','REPLAY')) {
    $guest = Join-Path $Output $case
    New-Item -ItemType Directory -Path $guest | Out-Null
    $source = if ($case -eq 'SILENT') {'SILENT'} else {'SCORED'}
    Copy-Item -LiteralPath (Join-Path $Fixtures $source) -Destination (Join-Path $guest 'MOVIE') -Recurse
    $guest = Join-Path $guest 'MOVIE'
    if ($case -eq 'TRUNCATED') {
        $path = Join-Path $guest 'MOVIE.WZV'
        $file = [IO.File]::OpenWrite($path); $file.SetLength($file.Length-1); $file.Close()
    }
    if ($case -eq 'BADCAP') { [IO.File]::WriteAllText((Join-Path $guest 'MOVIE.LRC'),'bad caption') }
    if ($case -eq 'MISMATCH') {
        $path = Join-Path $guest 'MOVIE.WZM'; $bytes = [IO.File]::ReadAllBytes($path)
        [Array]::Copy([BitConverter]::GetBytes(3000),0,$bytes,12,4);[IO.File]::WriteAllBytes($path,$bytes)
    }
    $commands = "@echo off`r`nMOVPLAY`r`n"
    if ($case -eq 'REPLAY') { $commands += "copy MOVPLAY.LOG FIRST.LOG`r`nMOVPLAY`r`n" }
    $commands += "echo RETURNED > RETURNED.TXT`r`nexit`r`n"
    [IO.File]::WriteAllText((Join-Path $guest 'START.BAT'),$commands,[Text.Encoding]::ASCII)
    $conf = @"
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
mount C "$guest"
C:
START.BAT
"@
    $configPath = Join-Path (Split-Path $guest) 'RUN.CNF'
    [IO.File]::WriteAllText($configPath,$conf,[Text.Encoding]::ASCII)
    $process = Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$configPath+'"')) -WindowStyle Hidden -PassThru
    if (!$process.WaitForExit(30000)) { $process.Kill(); throw "$case emulator timed out." }
    if (!(Test-Path -LiteralPath (Join-Path $guest 'RETURNED.TXT'))) { throw "$case did not return to DOS." }
    $log = Get-Content -LiteralPath (Join-Path $guest 'MOVPLAY.LOG')
    $fields = @{}; foreach ($line in $log) { if ($line.Contains('=')) { $k,$v=$line.Split('=',2);$fields[$k]=$v } }
    $expected = switch ($case) {'TRUNCATED' {'14'} 'MISMATCH' {'26'} default {'0'}}
    if ($fields.error -ne $expected -or $fields.restored_mode -ne $fields.old_mode -or $fields.sound_mask_after_stop -ne '0' -or $fields.speaker_bits_after_stop -ne '0') { throw "$case runtime safety validation failed." }
    if ($case -in @('SILENT','SCORED','BADCAP','REPLAY')) {
        if ($log[0] -ne 'Complete' -or $fields.frames -ne '8' -or $fields.dropped_frames -ne '0') { throw "$case incomplete or dropped frames." }
    }
    if ($case -eq 'SCORED' -and ($fields.caption_updates -ne '3' -or $fields.music_events_applied -ne '2')) { throw 'Score/caption events missing.' }
    if ($case -eq 'BADCAP' -and $fields.caption_status -ne '-1') { throw 'Malformed caption fallback failed.' }
    if ($case -eq 'REPLAY' -and !(Get-Content (Join-Path $guest 'FIRST.LOG'))[0].StartsWith('Complete')) { throw 'First replay failed.' }
    $results += @{case=$case;pass=$true;fields=$fields}
}
@{tests=$results;count=$results.Count;scope='DOSBox-X 8086_prefetch, Tandy, 640 KiB, 3000 cycles. Not hardware or perceived-sound certification.'} | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Output 'RESULTS.json')
$results | ForEach-Object { Write-Output ($_.case + ': PASS') }
