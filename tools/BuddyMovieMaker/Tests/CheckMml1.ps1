param([Parameter(Mandatory=$true)][string]$Fixtures)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $Fixtures).Path
$baseline=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Mml1-Baseline.json') -Raw | ConvertFrom-Json
foreach($entry in $baseline.files){
    $path=Join-Path $root $entry.name
    if(!(Test-Path -LiteralPath $path -PathType Leaf)){throw ('Missing MML1 fixture: '+$entry.name)}
    if((Get-Item -LiteralPath $path).Length -ne $entry.size){throw ('MML1 fixture length changed: '+$entry.name)}
    $inputStream=[IO.File]::OpenRead($path)
    try {
        $sha=[Security.Cryptography.SHA256]::Create()
        try {$hash=([BitConverter]::ToString($sha.ComputeHash($inputStream))).Replace('-','')}
        finally {$sha.Dispose()}
    } finally {$inputStream.Dispose()}
    if($hash -ne $entry.sha256){throw ('MML1 fixture bytes changed: '+$entry.name)}
}
Write-Output ('PASS: '+$baseline.files.Count+' MML1 fixture files match pinned '+$baseline.source_commit)
