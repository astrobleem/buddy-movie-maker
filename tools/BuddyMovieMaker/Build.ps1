param(
    [Parameter(Mandatory=$true)][string]$ToolchainRoot,
    [string]$Output = '',
    [string]$Dotnet = 'dotnet',
    [string]$Dosbox = 'C:\Program Files\DOSBox-X\dosbox-x.exe',
    [string]$EmulatorLock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Mml3Qualification=(Join-Path $PSScriptRoot 'Tests\QualifiedMml3Runtime.json')
)
$ErrorActionPreference='Stop'
$ToolchainRoot=(Resolve-Path -LiteralPath $ToolchainRoot).Path
foreach($required in @('BIN\CL.EXE','BIN\MASM.EXE','INCLUDE\DOS.H','LIB\SLIBCE.LIB','DDK\286\TOOLS\LINK4.EXE')){
    if(!(Test-Path -LiteralPath (Join-Path $ToolchainRoot $required) -PathType Leaf)){throw ('Missing external DOS toolchain file: '+$required)}
}
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (!$Output) { $Output=Join-Path $root 'MakerArtifacts\Build' }
$Output=[IO.Path]::GetFullPath($Output)
if (Test-Path -LiteralPath $Output) { throw 'Use a new build directory.' }
New-Item -ItemType Directory -Path $Output | Out-Null
$runtime=Join-Path $Output 'dos-build';New-Item -ItemType Directory $runtime | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'Runtime\*.C'),(Join-Path $PSScriptRoot 'Runtime\*.H'),(Join-Path $PSScriptRoot 'Runtime\*.ASM'),(Join-Path $PSScriptRoot 'Runtime\BUILD.BAT') $runtime
$conf=@"
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
mount D "$runtime"
D:
BUILD.BAT
"@
$cnf=Join-Path $Output 'BUILD.CNF';[IO.File]::WriteAllText($cnf,$conf)
$lease=[IO.File]::Open($EmulatorLock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    $p=Start-Process $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$cnf+'"')) -WindowStyle Hidden -PassThru
    if (!$p.WaitForExit(30000)) { $p.Kill();throw 'DOS build timed out.' }
}finally{$lease.Dispose()}
if (!(Test-Path (Join-Path $runtime 'MOVPLAY.EXE')) -or !(Select-String -Path (Join-Path $runtime 'BUILD.LOG') -Pattern '^PASS$')) { throw 'DOS build failed.' }
$mml3=Join-Path $Output 'dos-mml3'
& (Join-Path $PSScriptRoot 'Tests\BuildMml3Runtime.ps1') -ToolchainRoot $ToolchainRoot -Output $mml3 -Lock $EmulatorLock -Dosbox $Dosbox
$app=Join-Path $Output 'BuddyMovieMaker'
$buildEnvironment=@{}
foreach ($name in @('DOTNET_CLI_HOME','DOTNET_CLI_TELEMETRY_OPTOUT','DOTNET_GENERATE_ASPNET_CERTIFICATE','DOTNET_SKIP_FIRST_TIME_EXPERIENCE')) {
    $buildEnvironment[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
}
try {
    $env:DOTNET_CLI_HOME=Join-Path $Output '.dotnet-cli'
    $env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
    $env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
    $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1'
    & $Dotnet publish (Join-Path $PSScriptRoot 'App') -c Release -r win-x64 --self-contained true -o $app
} finally {
    foreach ($name in $buildEnvironment.Keys) {
        [Environment]::SetEnvironmentVariable($name,$buildEnvironment[$name],'Process')
    }
}
if ($LASTEXITCODE -ne 0) { throw 'Windows publish failed.' }
New-Item -ItemType Directory (Join-Path $app 'runtime') | Out-Null
Copy-Item (Join-Path $runtime 'MOVPLAY.EXE') (Join-Path $app 'runtime')
New-Item -ItemType Directory (Join-Path $app 'runtime-mml3')|Out-Null
Copy-Item -LiteralPath (Join-Path $mml3 'MOVPLAY.EXE') -Destination (Join-Path $app 'runtime-mml3')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'RuntimeMml3\ADAPTER.md') -Destination (Join-Path $app 'runtime-mml3')
if(Test-Path -LiteralPath $Mml3Qualification){
    $receipt=Get-Content -LiteralPath $Mml3Qualification -Raw|ConvertFrom-Json
    if($receipt.runtime_mml3_sha256-ne(Get-FileHash -LiteralPath (Join-Path $mml3 'MOVPLAY.EXE')).Hash -or
       $receipt.native_corpus_checks-ne224 -or $receipt.advanced_checks-ne9 -or !$receipt.windows_child_pass){
        throw 'MML3 qualification receipt does not match this rebuilt runtime. PIT export remains disabled.'
    }
    [IO.File]::WriteAllText((Join-Path $app 'runtime-mml3\MML3.CAP'),'WZP1',[Text.Encoding]::ASCII)
    Copy-Item -LiteralPath $Mml3Qualification -Destination (Join-Path $app 'runtime-mml3\QUALIFICATION.json')
}
Copy-Item (Join-Path $root 'LICENSE') (Join-Path $app 'LICENSE.txt')
$packages = if ($env:NUGET_PACKAGES) {$env:NUGET_PACKAGES} else {Join-Path $env:USERPROFILE '.nuget\packages'}
[xml]$project=Get-Content (Join-Path $PSScriptRoot 'App\BuddyMovieMaker.csproj')
$version=$project.Project.PropertyGroup.RuntimeFrameworkVersion
Copy-Item (Join-Path $packages "microsoft.netcore.app.runtime.win-x64\$version\LICENSE.TXT") (Join-Path $app 'DOTNET-LICENSE.txt')
Copy-Item (Join-Path $packages "microsoft.netcore.app.runtime.win-x64\$version\THIRD-PARTY-NOTICES.TXT") (Join-Path $app 'DOTNET-THIRD-PARTY-NOTICES.txt')
Copy-Item (Join-Path $packages "microsoft.windowsdesktop.app.runtime.win-x64\$version\LICENSE") (Join-Path $app 'WPF-LICENSE.txt')
Copy-Item (Join-Path $PSScriptRoot 'README.md'),(Join-Path $PSScriptRoot 'DEPENDENCIES.md'),(Join-Path $PSScriptRoot 'MML1.md'),(Join-Path $PSScriptRoot 'MML2.md'),(Join-Path $PSScriptRoot 'MML3.md') $app
Copy-Item (Join-Path $PSScriptRoot 'Tests\Mml2Contract') (Join-Path $app 'test-contract') -Recurse
Write-Output "Windows app built: $app. Select your existing FFmpeg folder in the app."
