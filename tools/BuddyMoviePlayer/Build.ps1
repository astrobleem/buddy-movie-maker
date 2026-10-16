param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
$target=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $target){throw 'Choose a new output directory.'}
$taskCli=Join-Path $env:TEMP ('buddy-player-cli-'+[Guid]::NewGuid())
$names=@('DOTNET_CLI_HOME','DOTNET_CLI_TELEMETRY_OPTOUT','DOTNET_GENERATE_ASPNET_CERTIFICATE','DOTNET_SKIP_FIRST_TIME_EXPERIENCE')
$previous=@{}
foreach($name in $names){$previous[$name]=[Environment]::GetEnvironmentVariable($name,'Process')}
try {
 $env:DOTNET_CLI_HOME=$taskCli
 $env:DOTNET_CLI_TELEMETRY_OPTOUT='1'
 $env:DOTNET_GENERATE_ASPNET_CERTIFICATE='false'
 $env:DOTNET_SKIP_FIRST_TIME_EXPERIENCE='1'
 dotnet publish $PSScriptRoot -c Release -r win-x64 --self-contained true -o $target
 if($LASTEXITCODE -ne 0){throw 'Publish failed.'}
}finally{foreach($name in $names){[Environment]::SetEnvironmentVariable($name,$previous[$name],'Process')}}
$packages=if($env:NUGET_PACKAGES){$env:NUGET_PACKAGES}else{Join-Path $env:USERPROFILE '.nuget\packages'}
Copy-Item -LiteralPath (Join-Path $PSScriptRoot '..\..\LICENSE') -Destination (Join-Path $target 'LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'README.md') -Destination $target
Copy-Item -LiteralPath (Join-Path $packages 'microsoft.netcore.app.runtime.win-x64\8.0.31\LICENSE.TXT') -Destination (Join-Path $target 'DOTNET-LICENSE.txt')
Copy-Item -LiteralPath (Join-Path $packages 'microsoft.netcore.app.runtime.win-x64\8.0.31\THIRD-PARTY-NOTICES.TXT') -Destination (Join-Path $target 'DOTNET-THIRD-PARTY-NOTICES.txt')
Copy-Item -LiteralPath (Join-Path $packages 'microsoft.windowsdesktop.app.runtime.win-x64\8.0.31\LICENSE') -Destination (Join-Path $target 'WINDOWSDESKTOP-LICENSE.txt')
Write-Output $target
