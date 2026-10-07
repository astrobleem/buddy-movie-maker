param(
    [Parameter(Mandatory=$true)][string]$Runtime,
    [Parameter(Mandatory=$true)][string]$Output,
    [string]$Lock=(Join-Path ([IO.Path]::GetTempPath()) 'BuddyMovieMaker-emulator.lock'),
    [string]$Dosbox='C:\Program Files\DOSBox-X\dosbox-x.exe'
)
$ErrorActionPreference='Stop'
$Runtime=(Resolve-Path -LiteralPath $Runtime).Path;$Output=[IO.Path]::GetFullPath($Output)
if(Test-Path -LiteralPath $Output){throw 'Use a new runtime QA directory.'}
$root=Join-Path $PSScriptRoot 'Mml3Contract\v1'
& (Join-Path $PSScriptRoot 'CheckMml3Contract.ps1') -Fixtures $root
$manifest=Get-Content -LiteralPath (Join-Path $root 'MANIFEST.json') -Raw|ConvertFrom-Json
$lease=[IO.File]::Open($Lock,[IO.FileMode]::OpenOrCreate,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
try{
    New-Item -ItemType Directory -Path $Output|Out-Null
    $results=@();$variants=@('ONMOV','ONAUD','OFFMOV','OFFAUD')
    foreach($variant in $variants){
        $base=Join-Path $Output $variant;New-Item -ItemType Directory $base|Out-Null
        $batch="@echo off`r`n"
        foreach($case in $manifest.cases){
            $dir=Join-Path $base $case.name;New-Item -ItemType Directory $dir|Out-Null
            Copy-Item -Path (Join-Path $root ($case.name+'\*')) -Destination $dir
            Copy-Item -LiteralPath $Runtime -Destination (Join-Path $dir 'MOVPLAY.EXE')
            $flags=if($variant -like '*AUD'){' /A'}else{''};if($variant -like 'ON*'){$flags+=' /P'}
            $batch+="cd \$variant\$($case.name)`r`nMOVPLAY$flags`r`n"
        }
        $batch+="echo RETURNED > C:\$variant\RETURNED.TXT`r`nexit`r`n"
        [IO.File]::WriteAllText((Join-Path $base 'RUN.BAT'),$batch,[Text.Encoding]::ASCII)
        $config=@"
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
cycles=fixed 3000
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
mount C "$Output"
C:
cd \$variant
RUN.BAT
"@
        $path=Join-Path $base 'RUN.CNF';[IO.File]::WriteAllText($path,$config,[Text.Encoding]::ASCII)
        $p=Start-Process -FilePath $Dosbox -ArgumentList @('-nopromptfolder','-conf',('"'+$path+'"')) -WindowStyle Hidden -PassThru
        if(!$p.WaitForExit(60000)){$p.Kill();throw ($variant+' own runtime batch timed out.')}
        if(!(Test-Path -LiteralPath (Join-Path $base 'RETURNED.TXT'))){throw ($variant+' did not return to DOS.')}
        foreach($case in $manifest.cases){
            $dir=Join-Path $base $case.name;$lines=Get-Content -LiteralPath (Join-Path $dir 'MOVPLAY.LOG');$fields=@{}
            foreach($line in $lines){if($line.Contains('=')){$k,$v=$line.Split('=',2);$fields[$k]=$v}}
            $expected=if($variant -like '*AUD'){$case.audio_accept}else{$case.movie_accept}
            if($variant -like 'OFF*' -and $case.pit_required){$expected=$false}
            if(($fields.error-eq'0')-ne$expected){throw ($variant+'/'+$case.name+' acceptance differs: '+$fields.error)}
            if(!$expected -and ($fields.psg_writes-ne'0' -or (Test-Path -LiteralPath (Join-Path $dir 'DOSSTART.LOG')))){throw ($variant+'/'+$case.name+' refusal wrote sound or changed video.')}
            if($fields.old_mode-ne$fields.restored_mode -or $fields.sound_mask_after_stop-ne'0' -or $fields.speaker_bits_after_stop-ne'0'){throw ($variant+'/'+$case.name+' cleanup failed.')}
            if($expected){
                if($lines[0]-ne'Complete'){throw ($variant+'/'+$case.name+' incomplete.')}
                if($case.pit_required){$expectedRecords=[BitConverter]::ToUInt16([IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZP')),12);if([int]$fields.pit_records-ne$expectedRecords){throw ($variant+'/'+$case.name+' did not read all PIT records.')}}
                if($variant -like '*MOV'){$expectedFrames=[BitConverter]::ToUInt32([IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZV')),12);if([int]$fields.frames-ne$expectedFrames){throw ($variant+'/'+$case.name+' frame count differs.')}}
            }
            $results+=@{variant=$variant;case=$case.name;expected_accept=$expected;pass=$true;fields=$fields}
        }
        Write-Output ($variant+': PASS '+$manifest.cases.Count+' frozen cases.')
    }
    @{tests=$results;count=$results.Count;runtime_sha256=(Get-FileHash -LiteralPath $Runtime).Hash;scope='Actual DOSBox-X 8086_prefetch Tandy 640 KiB/3000 cycles; frozen reader and enabled/disabled movie/audio checks; no physical hardware claim'}|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $Output 'RESULTS.json')
}finally{$lease.Dispose()}
