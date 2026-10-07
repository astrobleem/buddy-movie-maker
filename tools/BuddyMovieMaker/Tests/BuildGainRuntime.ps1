param(
    [Parameter(Mandatory=$true)][string]$ToolchainRoot,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe'
)
$ErrorActionPreference='Stop'
$ToolchainRoot=(Resolve-Path -LiteralPath $ToolchainRoot).Path
$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new runtime build directory.'}
$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    New-Item -ItemType Directory -Path $Output|Out-Null
    Copy-Item -Path (Join-Path $PSScriptRoot '..\RuntimeGain\*') -Destination $Output -Recurse
    $config=@"
[sdl]
fullscreen=false
output=surface
[dosbox]
machine=tandy
[cpu]
core=normal
cputype=8086_prefetch
cycles=fixed 200000
[mixer]
nosound=true
[autoexec]
mount C "$ToolchainRoot"
mount D "$Output"
D:
BUILD.BAT
"@
    $path=Join-Path $Output 'BUILD.CNF';[IO.File]::WriteAllText($path,$config,[Text.Encoding]::ASCII)
    $p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$path+'"')) -WindowStyle Hidden -PassThru
    if(!$p.WaitForExit(30000)){$p.Kill();throw 'Own DOS build timed out.'}
    if(!(Test-Path -LiteralPath (Join-Path $Output 'MOVPLAY.EXE')) -or !(Select-String -LiteralPath (Join-Path $Output 'BUILD.LOG') -Pattern '^PASS$')){
        Get-Content -LiteralPath (Join-Path $Output 'BUILD.LOG');throw 'Gain DOS build failed.'
    }
    Get-Content -LiteralPath (Join-Path $Output 'BUILD.LOG')
}finally{$lease.Dispose()}
