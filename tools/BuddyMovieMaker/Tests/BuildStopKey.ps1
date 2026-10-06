# Build the test-only Escape injector with the repository compiler in DOSBox.
param([Parameter(Mandatory=$true)][string]$ToolchainRoot,[Parameter(Mandatory=$true)][string]$Output,[string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe')
$ErrorActionPreference='Stop'
$ToolchainRoot=(Resolve-Path -LiteralPath $ToolchainRoot).Path
foreach($required in @('BIN\CL.EXE','BIN\MASM.EXE','INCLUDE\DOS.H','LIB\SLIBCE.LIB','DDK\286\TOOLS\LINK4.EXE')){
    if(!(Test-Path -LiteralPath (Join-Path $ToolchainRoot $required) -PathType Leaf)){throw ('Missing external DOS toolchain file: '+$required)}
}
$root=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..'))
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new output directory.'}
New-Item -ItemType Directory $Output | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'STOPKEY.C') $Output
$batch="@echo off`r`nPATH=C:\BIN`r`nSET INCLUDE=C:\INCLUDE`r`nSET LIB=C:\LIB`r`nCL /nologo /c /G0 /AS /W3 /Os STOPKEY.C > BUILD.LOG`r`nIF ERRORLEVEL 1 GOTO END`r`nC:\DDK\286\TOOLS\LINK4 /NOE /NOD /STACK:4096 STOPKEY,STOPKEY,,SLIBCE; >> BUILD.LOG`r`n:END`r`nEXIT`r`n"
[IO.File]::WriteAllText((Join-Path $Output 'BUILD.BAT'),$batch,[Text.Encoding]::ASCII)
$conf="[dosbox]`r`nmachine=tandy`r`n[cpu]`r`ncycles=fixed 200000`r`n[mixer]`r`nnosound=true`r`n[autoexec]`r`nmount C `"$ToolchainRoot`"`r`nmount D `"$Output`"`r`nD:`r`nBUILD.BAT`r`n"
$cnf=Join-Path $Output 'BUILD.CNF';[IO.File]::WriteAllText($cnf,$conf)
$p=Start-Process $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
if(!$p.WaitForExit(30000)){$p.Kill();throw 'Test helper build timed out.'}
if(!(Test-Path (Join-Path $Output 'STOPKEY.EXE'))){throw 'Test helper build failed.'}
Write-Output (Join-Path $Output 'STOPKEY.EXE')
