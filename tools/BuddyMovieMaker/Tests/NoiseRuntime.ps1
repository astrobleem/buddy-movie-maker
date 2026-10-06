param([Parameter(Mandatory=$true)][string]$Fixtures,
 [Parameter(Mandatory=$true)][string]$Output,
 [Parameter(Mandatory=$true)][string]$StopKey,
 [Parameter(Mandatory=$true)][string]$NoiseKey,
 [int]$Cycles=3000,
 [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe')
$ErrorActionPreference='Stop'
$Fixtures=(Resolve-Path $Fixtures).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new output directory.'}
New-Item -ItemType Directory $Output | Out-Null
$cases=@('ALLDRUM','BEAT40','BEAT120','BEAT240','REPEAT','HELD','NOISESP','ESCAPE','PCSTOP','REPLAY','BADCODE','BADTRIG','BADVER','MISSING')
$results=@()
foreach($case in $cases){
 $dir=Join-Path $Output $case;New-Item -ItemType Directory $dir | Out-Null
 $expectedError='0';$reason='Complete';$mode='/A /F'
 if($case -in @('NOISESP','PCSTOP','REPLAY')){
  Copy-Item (Join-Path $Fixtures 'NOISESP\*') $dir;$mode=''
 }else{
  $name=if($case -in @('ESCAPE','BADCODE','BADTRIG','BADVER','MISSING')){'BEAT40'}else{$case}
  Copy-Item (Join-Path $Fixtures 'DRUMS\MOVPLAY.EXE') $dir
  Copy-Item (Join-Path $PSScriptRoot "Mml2Contract\$name.WZM") (Join-Path $dir 'MOVIE.WZM')
  Copy-Item (Join-Path $PSScriptRoot "Mml2Contract\$name.WZI") (Join-Path $dir 'MOVIE.WZI')
  [IO.File]::WriteAllText((Join-Path $dir 'INST.REQ'),'WZI1',[Text.Encoding]::ASCII)
  $m=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZM'));$duration=[BitConverter]::ToInt32($m,12)
  $w=New-Object IO.BinaryWriter([IO.File]::Create((Join-Path $dir 'MOVIE.CUE')))
  try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZC1'));$w.Write([int]$duration);$w.Write([int]0);$w.Write([int]$duration)}finally{$w.Dispose()}
 }
 if($case -in @('BADCODE','BADTRIG')){
  $path=Join-Path $dir 'MOVIE.WZM';$m=[IO.File]::ReadAllBytes($path)
  if($case -eq 'BADCODE'){$m[27]=34;$expectedError='25'}else{$m[32]=128;$expectedError='24'}
  [IO.File]::WriteAllBytes($path,$m)
 }
 if($case -eq 'BADVER'){$path=Join-Path $dir 'MOVIE.WZI';$m=[IO.File]::ReadAllBytes($path);$m[18]=3;[IO.File]::WriteAllBytes($path,$m);$expectedError='71'}
 if($case -eq 'MISSING'){Remove-Item -LiteralPath (Join-Path $dir 'MOVIE.WZI');$expectedError='70'}
 $batch="@echo off`r`n"
 if($case -eq 'ESCAPE'){Copy-Item -LiteralPath $NoiseKey -Destination (Join-Path $dir 'NOISEKEY.EXE');$batch+="NOISEKEY`r`n";$reason='Stopped'}
 if($case -eq 'PCSTOP'){Copy-Item -LiteralPath $StopKey -Destination (Join-Path $dir 'STOPKEY.EXE');$batch+="STOPKEY`r`n";$reason='Stopped'}
 $batch+="MOVPLAY $mode`r`n"
 if($case -eq 'REPLAY'){$batch+="copy MOVPLAY.LOG FIRST.LOG`r`nMOVPLAY`r`n"}
 $batch+="echo RETURNED > RETURNED.TXT`r`nexit`r`n"
 [IO.File]::WriteAllText((Join-Path $dir 'START.BAT'),$batch,[Text.Encoding]::ASCII)
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
 if(!(Test-Path (Join-Path $dir 'RETURNED.TXT'))){throw "$case did not return to DOS"}
 $log=Get-Content (Join-Path $dir 'MOVPLAY.LOG');$fields=@{}
 foreach($line in $log){if($line.Contains('=')){$k,$v=$line.Split('=',2);$fields[$k]=$v}}
 if($fields.error -ne $expectedError -or $fields.old_mode -ne $fields.restored_mode -or $fields.sound_mask_after_stop -ne '0' -or $fields.speaker_bits_after_stop -ne '0' -or $fields.noise_tone_clock_writes -ne '0'){throw "$case error/cleanup/coupling mismatch"}
 if($expectedError -eq '0'){
  if($log[0] -ne $reason -or $fields.expressive -ne '1' -or [int]$fields.noise_resets -lt 1){throw "$case noise playback mismatch"}
  if($case -eq 'ALLDRUM' -and ($fields.noise_e2 -ne '2' -or $fields.noise_e4 -ne '3' -or $fields.noise_e5 -ne '2' -or $fields.noise_e6 -ne '40')){throw 'All47 drum hardware controls mismatch'}
  if($case -eq 'REPEAT' -and $fields.noise_resets -ne '5'){throw 'Repeated equal hits did not retrigger'}
  if($case -in @('NOISESP','REPLAY') -and ($fields.speech_clips -ne '1' -or $fields.speech_avoided_music -ne '0' -or [int]$fields.speech_samples -eq 0)){throw 'Speech rest did not play safely'}
  if($case -eq 'PCSTOP' -and $fields.clip_0_target -notmatch 'reason=1$'){throw 'Escape did not interrupt PWM'}
  if($case -eq 'REPLAY' -and (Get-Content (Join-Path $dir 'FIRST.LOG'))[0] -ne 'Complete'){throw 'First playback failed'}
 }
 $results+=@{case=$case;cycles=$Cycles;pass=$true;fields=$fields};Write-Output "$case : PASS"
}
@{count=$results.Count;tests=$results;scope='Actual exported MOVPLAY with shared WZM/WZI fixtures and generated speech/video in Tandy/8086_prefetch640KiB DOSBox-X. No physical/perceived-audio certification.'}|ConvertTo-Json -Depth 8 | Set-Content (Join-Path $Output 'RESULTS.json')
