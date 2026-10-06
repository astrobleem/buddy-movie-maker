param([Parameter(Mandatory=$true)][string]$ToolchainRoot,[Parameter(Mandatory=$true)][string]$Output,
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe')
$ErrorActionPreference='Stop'
$ToolchainRoot=(Resolve-Path -LiteralPath $ToolchainRoot).Path
foreach($required in @('BIN\CL.EXE','BIN\MASM.EXE','INCLUDE\DOS.H','LIB\SLIBCE.LIB','DDK\286\TOOLS\LINK4.EXE')){
    if(!(Test-Path -LiteralPath (Join-Path $ToolchainRoot $required) -PathType Leaf)){throw ('Missing external DOS toolchain file: '+$required)}
}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new output directory.'}
New-Item -ItemType Directory $Output | Out-Null
Copy-Item (Join-Path $PSScriptRoot '..\Runtime\*') $Output
Copy-Item (Join-Path $PSScriptRoot 'NOISEQA.C') $Output
Copy-Item (Join-Path $PSScriptRoot 'STOPKEY.C') (Join-Path $Output 'NOISEKEY.C')
$batch=@'
@echo off
PATH=C:\BIN
SET INCLUDE=C:\INCLUDE
SET LIB=C:\LIB
CL /nologo /c /G0 /AS /W3 /Os NOISEQA.C CAPTION.C INSTR.C > QA-BUILD.LOG
IF ERRORLEVEL 1 GOTO END
MASM /W2 HARDWARE.ASM; >> QA-BUILD.LOG
IF ERRORLEVEL 1 GOTO END
C:\DDK\286\TOOLS\LINK4 /NOE /NOD /STACK:4096 NOISEQA+HARDWARE+CAPTION+INSTR,NOISEQA,,SLIBCE; >> QA-BUILD.LOG
CL /nologo /c /G0 /AS /W3 /Os /DSTOP_MUSIC NOISEKEY.C >> QA-BUILD.LOG
C:\DDK\286\TOOLS\LINK4 /NOE /NOD /STACK:4096 NOISEKEY,NOISEKEY,,SLIBCE; >> QA-BUILD.LOG
:END
EXIT
'@
[IO.File]::WriteAllText((Join-Path $Output 'QABUILD.BAT'),($batch -replace '\r?\n',"`r`n"),[Text.Encoding]::ASCII)
function RunDos([string]$Directory,[string]$Drive,[string]$Command,[int]$Cycles){
 $conf="[dosbox]`r`nmachine=tandy`r`nmemsize=0`r`nmemsizekb=640`r`n[cpu]`r`ncore=normal`r`ncputype=8086_prefetch`r`ncycles=fixed $Cycles`r`n[mixer]`r`nnosound=true`r`n[autoexec]`r`nmount C `"$ToolchainRoot`"`r`nmount D `"$Directory`"`r`n${Drive}:`r`n$Command`r`n"
 $cnf=Join-Path $Directory 'QA.CNF';[IO.File]::WriteAllText($cnf,$conf)
 $p=Start-Process $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
 if(!$p.WaitForExit(30000)){$p.Kill();throw 'Noise engine check timed out.'}
}
RunDos $Output 'D' 'QABUILD.BAT' 200000
if(!(Test-Path (Join-Path $Output 'NOISEQA.EXE')) -or !(Test-Path (Join-Path $Output 'NOISEKEY.EXE'))){throw 'Noise harness build failed.'}
$results=@()
foreach($cycles in @(3000,240)){
 $dir=Join-Path $Output "QA$cycles";New-Item -ItemType Directory $dir | Out-Null
 Copy-Item (Join-Path $Output 'NOISEQA.EXE') $dir
 Copy-Item (Join-Path $PSScriptRoot 'Mml2Contract\REPEAT.WZM') (Join-Path $dir 'MOVIE.WZM')
 Copy-Item (Join-Path $PSScriptRoot 'Mml2Contract\REPEAT.WZI') (Join-Path $dir 'MOVIE.WZI')
 [IO.File]::WriteAllText((Join-Path $dir 'INST.REQ'),'WZI1',[Text.Encoding]::ASCII)
 [IO.File]::WriteAllText((Join-Path $dir 'RUN.BAT'),"@echo off`r`nNOISEQA`r`necho RETURNED > RETURNED.TXT`r`nEXIT`r`n",[Text.Encoding]::ASCII)
 RunDos $dir 'D' 'RUN.BAT' $cycles
 $log=Get-Content (Join-Path $dir 'NOISEQA.LOG')
 if($log[-1] -notmatch '^PASS ' -or @($log | Where-Object {$_ -match '^drum_'}).Count -ne 47 -or !(Test-Path (Join-Path $dir 'RETURNED.TXT'))){throw "Noise engine failed at $cycles cycles: $($log[-1])"}
 $results+=@{cycles=$cycles;pass=$true;maps=47;result=$log[-1]}
 Write-Output "Noise engine $cycles : PASS"
}
@{tests=$results;scope='Production C functions and actual PSG port output in disposable DOSBox Tandy guests; direct event-time catchup calls. No hardware/perceived-audio certification.'}|ConvertTo-Json -Depth 5 | Set-Content (Join-Path $Output 'RESULTS.json')
