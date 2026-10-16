# Version-gate experiment only. Does not change the producer/runtime/accepted spec.
param([Parameter(Mandatory=$true)][string]$Proposal,[Parameter(Mandatory=$true)][string]$Legacy,[Parameter(Mandatory=$true)][string]$Mml3,[Parameter(Mandatory=$true)][string]$Output,
 [string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),[string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe')
$ErrorActionPreference='Stop';$Proposal=(Resolve-Path $Proposal).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path $Output){throw 'Use a new old-player matrix directory'};New-Item -ItemType Directory $Output|Out-Null
$players=@(@{name='LEGACY';path=(Resolve-Path $Legacy).Path},@{name='MML3';path=(Resolve-Path $Mml3).Path});$results=@()
$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{foreach($player in $players){foreach($case in @('FULL','STRIPPED','HEADERS','VIDEO_ONLY_STRIPPED','MUSIC_ONLY_STRIPPED')){foreach($mode in @('DEFAULT','A','V','B')){
 $dir=Join-Path $Output ($player.name+'-'+$case+'-'+$mode);New-Item -ItemType Directory $dir|Out-Null
 foreach($file in Get-ChildItem (Join-Path $Proposal 'SIMULTANEOUS') -File){if($case-eq'FULL'-or($file.Name-eq'MOVIE.WZM'-and$case-ne'VIDEO_ONLY_STRIPPED')){Copy-Item -LiteralPath $file.FullName -Destination $dir}}
 if($case-ne'VIDEO_ONLY_STRIPPED'){$path=Join-Path $dir 'MOVIE.WZM';$b=[IO.File]::ReadAllBytes($path);$b[3]=[byte][char]'3';$b[16]=0;[IO.File]::WriteAllBytes($path,$(if($case-eq'HEADERS'){$b[0..19]}else{$b}))}
 if($case-ne'MUSIC_ONLY_STRIPPED'){$w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZV')));try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZV4'));$w.Write([ushort]256);$w.Write([ushort]160);$w.Write([ushort]4);$w.Write([ushort]24);$w.Write([uint32]4);$w.Write([uint32]1000);$w.Write([uint32]20480);if($case-ne'HEADERS'){$w.Write([byte[]]::new(81920))}}finally{$w.Dispose()}}
 Copy-Item -LiteralPath $player.path -Destination (Join-Path $dir 'MOVPLAY.EXE')
 $switch=if($mode-eq'DEFAULT'){''}else{'/'+$mode+' /F'}
 [IO.File]::WriteAllText((Join-Path $dir 'RUN.BAT'),"@echo off`r`nMOVPLAY $switch`r`necho RETURNED > RETURNED.TXT`r`nexit`r`n",[Text.Encoding]::ASCII)
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
 $p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
 try{if(!$p.WaitForExit(10000)){$p.Kill();throw 'Own old-player matrix guest timeout'}}finally{if(!$p.HasExited){$p.Kill()}}
 if(!(Test-Path (Join-Path $dir 'RETURNED.TXT'))){throw 'Old player did not return'}
 $lines=Get-Content (Join-Path $dir 'MOVPLAY.LOG');$f=@{};foreach($line in $lines){if($line.Contains('=')){$key,$value=$line.Split('=',2);$f[$key]=$value}}
 if($lines[0]-ne'Error'-or$f.error-eq'0'-or$f.frames-ne'0'-or$f.speaker_bits_after_stop-ne'0'-or$f.old_mode-ne$f.restored_mode){throw ('Old version gate failed: '+$dir)}
 if($player.name-eq'MML3'-and$f.psg_writes-ne'0'){throw 'Sound-owned old player wrote PSG on gate refusal'}
 $results+=@{player=$player.name;sha256=(Get-FileHash $player.path).Hash;case=$case;entry=$mode;pass=$true;fields=$f}
}};Write-Output ('PASS old DOS '+$player.name+' 20 entry/payload refusals')}}finally{$lease.Dispose()}
@{pass=$true;count=$results.Count;results=$results;scope='Actual hashed DOS binaries only; Win16/x64 matrices still required. Legacy pre-parser mute writes recorded, not mislabeled zero-I/O. No accepted formats/emission changed.'}|ConvertTo-Json -Depth 7|Set-Content (Join-Path $Output 'RESULTS.json')
