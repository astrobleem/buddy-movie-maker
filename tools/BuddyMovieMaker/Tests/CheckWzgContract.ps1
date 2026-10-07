# Read-only verification of frozen synthetic revision1 bytes and bundle decisions.
param([string]$Corpus=(Join-Path $PSScriptRoot 'WzgContract/v1'))
$ErrorActionPreference='Stop'
$Corpus=[IO.Path]::GetFullPath($Corpus)
$manifest=Get-Content -LiteralPath (Join-Path $Corpus 'MANIFEST.json') -Raw|ConvertFrom-Json
if(!$manifest.reference_pass-or$manifest.cases.Count-ne43){throw 'Reference manifest status/count'}
foreach($f in $manifest.files){$path=[IO.Path]::GetFullPath((Join-Path $Corpus $f.path));if(!$path.StartsWith($Corpus+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)){throw 'Manifest path outside corpus'};$item=Get-Item -LiteralPath $path;if($item.Length-ne$f.bytes-or(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash-cne$f.sha256){throw ('Changed reference bytes: '+$f.path)}}
$actual=@(Get-ChildItem -LiteralPath $Corpus -Recurse -File)
if($actual.Count-ne$manifest.files.Count+1){throw 'Unlisted corpus file'}
if((Get-FileHash -LiteralPath (Join-Path $Corpus 'WZG1.md')).Hash-cne$manifest.spec_sha256){throw 'Spec identity'}
if((Get-FileHash -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'WZG1.md')).Hash-cne$manifest.spec_sha256){throw 'Canonical spec differs'}
# Load only the two reference-check functions from our checked-in generator.
# Do not invoke its fixture generation or output mutations.
$parseTokens=$null;$parseErrors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'WzgProposal.ps1'),[ref]$parseTokens,[ref]$parseErrors)
if($parseErrors.Count){throw 'Reference source parse error'}
foreach($name in @('Need','Validate')){$fn=$ast.Find({param($node)$node-is[Management.Automation.Language.FunctionDefinitionAst]-and$node.Name-eq$name},$true);if(!$fn){throw 'Missing reference checker'};. ([scriptblock]::Create($fn.Extent.Text))}
foreach($case in $manifest.cases){$accept=$true;try{Validate (Join-Path $Corpus $case.name)}catch [IO.InvalidDataException]{$accept=$false};if($accept-ne$case.proposed_accept){throw ('Reference decision changed: '+$case.name)}}
Write-Output ('PASS frozen WZG1: '+$manifest.cases.Count+' decisions; '+$manifest.files.Count+' exact files; spec '+$manifest.spec_sha256)