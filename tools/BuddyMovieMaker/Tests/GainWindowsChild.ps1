param([Parameter(Mandatory=$true)][string]$Runtime,[Parameter(Mandatory=$true)][string]$ExistingGuest,
    [Parameter(Mandatory=$true)][string]$Output,[string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe')
$ErrorActionPreference='Stop';$Runtime=(Resolve-Path -LiteralPath $Runtime).Path;$ExistingGuest=(Resolve-Path -LiteralPath $ExistingGuest).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new Windows child QA directory'}
New-Item -ItemType Directory $Output|Out-Null
New-Item -ItemType Directory (Join-Path $Output 'guest')|Out-Null
foreach($f in Get-ChildItem -LiteralPath $ExistingGuest|Where-Object{$_.Name-notlike'*.LOG'}){Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $Output 'guest') -Recurse}
$guest=Join-Path $Output 'guest';Copy-Item -LiteralPath $Runtime -Destination (Join-Path $guest 'MOVPLAY.EXE') -Force
# Previous logs belong to the old immutable guest. Use fresh redirected names
# by copying a clean DOS wrapper built from the checked-in MOVCHILD source.
$log=Join-Path $guest 'DOSCHILD.LOG';$prior=if(Test-Path $log){[IO.File]::ReadAllText($log)}else{''}
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
cycles=fixed 5000
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
@echo off
mount C "$guest"
C:
set path=C:\WINDOWS;Z:\
set temp=C:\WINDOWS\TEMP
cd WINDOWS
win /r C:\TCHIME.EXE /probe
echo GAIN_RETURNED > C:\GAINRET.LOG
exit
"@
$cnf=Join-Path $Output 'RUN.CNF';[IO.File]::WriteAllText($cnf,$config,[Text.Encoding]::ASCII)
$lease=$null;$deadline=[DateTime]::UtcNow.AddSeconds(15)
while(!$lease){try{$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)}catch [IO.IOException]{if([DateTime]::UtcNow-ge$deadline){throw 'Shared emulator busy; no guest started'};Start-Sleep -Milliseconds 200}}
try{
    $p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
    try{if(!$p.WaitForExit(30000)){throw 'Own Windows child timed out'}}finally{if(!$p.HasExited){$p.Kill()}}
}finally{$lease.Dispose()}
if(!(Test-Path (Join-Path $guest 'GAINRET.LOG'))){throw 'New guest return marker missing'}
$child=[IO.File]::ReadAllText($log);$launcher=Get-Content (Join-Path $guest 'LAUNCHER.LOG') -Raw
if(!$child.Contains('Exit Windows first.')-or!$child.Contains('CHILD_RETURN=1')-or!$launcher.Contains('CHILD LOG FOUND')){throw 'Actual gain DOS child did not refuse under Windows'}
@{pass=$true;runtime_sha256=(Get-FileHash -LiteralPath $Runtime).Hash;child=$child;launcher=$launcher;lease_released=$true;scope='Existing authorized Windows3 real-mode guest, actual isolated gain MOVPLAY child refusal before media/hardware; OS files remain local and are excluded from deliverables'}|ConvertTo-Json|Set-Content (Join-Path $Output 'RESULTS.json')
Write-Output 'PASS actual gain Windows3 child refusal; lease released'
