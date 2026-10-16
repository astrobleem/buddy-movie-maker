# Revision1 synthetic reference fixture generator. Not a production exporter.
param([Parameter(Mandatory=$true)][string]$Output)
$ErrorActionPreference='Stop'
$Output=[IO.Path]::GetFullPath($Output);if(Test-Path -LiteralPath $Output){throw 'Use a new proposal directory.'};New-Item -ItemType Directory $Output|Out-Null
function Gain($dir,[int]$duration,$states){
    $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZG')))
    try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZG1'));$w.Write([ushort]20);$w.Write([ushort]8);$w.Write([uint32]$states.Count);$w.Write([uint32]$duration);$w.Write([uint32]0);foreach($s in $states){$w.Write([uint32]$s.t);$w.Write([byte[]]$s.v)}}finally{$w.Dispose()}
}
function Bundle($name,[int]$duration,[int]$flags,$gains){
    $dir=Join-Path $Output $name;New-Item -ItemType Directory $dir|Out-Null
    $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZM')))
    try{$w.Write([Text.Encoding]::ASCII.GetBytes($(if($flags-band2){'WZM3'}else{'WZM1'})));$w.Write([ushort]20);$w.Write([ushort]14);$w.Write([uint32]3);$w.Write([uint32]$duration);$w.Write([uint32]0)
        foreach($s in @(@{t=0;n=@(69,72,76,42);v=@(100,90,80,100);r=15},@{t=[int]($duration/2);n=@(69,72,76,42);v=@(100,90,80,100);r=1},@{t=$duration;n=@(0,0,0,0);v=@(0,0,0,0);r=0})){$w.Write([uint32]$s.t);$w.Write([byte[]]$s.n);$w.Write([byte[]]$s.v);$w.Write([byte]$s.r);$w.Write([byte]0)}}finally{$w.Dispose()}
    $w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZI')))
    try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZI1'));$w.Write([ushort]20);$w.Write([ushort]8);$w.Write([uint32]2);$w.Write([uint32]$duration);$w.Write([ushort]$flags);$w.Write([ushort]258);$w.Write([uint32]0);$w.Write([byte[]]@(16,48,80,0));$w.Write([uint32][int]($duration/2));$w.Write([byte[]]@(80,16,48,0))}finally{$w.Dispose()}
    [IO.File]::WriteAllText((Join-Path $dir 'INST.REQ'),'WZI1',[Text.Encoding]::ASCII)
    if($flags-band2){Gain $dir $duration $gains;[IO.File]::WriteAllText((Join-Path $dir 'GAIN.REQ'),'WZG1',[Text.Encoding]::ASCII)}
    if($flags-band4){$w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZP')));try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZP1'));$w.Write([ushort]1);$w.Write([ushort]0);$w.Write([uint32]$duration);$w.Write([ushort]2);$w.Write([ushort]0);$w.Write([uint32]0);$w.Write([uint32]0);$w.Write([uint32]$duration);$w.Write([uint32]0)}finally{$w.Dispose()};[IO.File]::WriteAllText((Join-Path $dir 'PIT.REQ'),'WZP1',[Text.Encoding]::ASCII)}
    if($duration-eq1000){$w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZV')));try{$w.Write([Text.Encoding]::ASCII.GetBytes($(if($flags-band2){'WZV4'}else{'WZV2'})));$w.Write([ushort]256);$w.Write([ushort]160);$w.Write([ushort]4);$w.Write([ushort]24);$w.Write([uint32]4);$w.Write([uint32]$duration);$w.Write([uint32]20480);$w.Write([byte[]]::new(81920))}finally{$w.Dispose()}}
    return $dir
}
function Clone($name,$excluded=@()){$dir=Join-Path $Output $name;New-Item -ItemType Directory $dir|Out-Null;foreach($f in Get-ChildItem (Join-Path $Output 'SIMULTANEOUS') -File|Where-Object{$_.Name-notin$excluded}){Copy-Item -LiteralPath $f.FullName -Destination $dir};return $dir}
function Change($dir,$file,$offset,[byte[]]$bytes){$path=Join-Path $dir $file;$data=[IO.File]::ReadAllBytes($path);[Array]::Copy($bytes,0,$data,$offset,$bytes.Length);[IO.File]::WriteAllBytes($path,$data)}
$gains=@(@{t=0;v=@(0,0,0,0)},@{t=250;v=@(1,2,3,4)},@{t=500;v=@(2,3,4,5)},@{t=505;v=@(6,7,8,9)},@{t=750;v=@(0,0,0,0)},@{t=1000;v=@(15,15,15,15)})
$cases=[Collections.Generic.List[object]]::new()
function Case($name,$accept,$reason){$cases.Add(@{name=$name;proposed_accept=$accept;reason=$reason})}
[void](Bundle 'SIMULTANEOUS' 1000 2 $gains);Case 'SIMULTANEOUS' $true 'program -> attack -> gain, one flush; held B/C preset snapshots unchanged; expired hat not revived'
[void](Bundle 'VIBRATO_GAIN' 1000 3 $gains);Case 'VIBRATO_GAIN' $true 'Existing vibrato bit0 plus proposed gain bit1'
[void](Bundle 'GAIN_PIT' 1000 6 $gains);Case 'GAIN_PIT' $true 'WZI bit2 explicitly requires WZP1/PIT.REQ even when empty/rest; audio-only'
[void](Bundle 'GAIN_PIT_VIBRATO' 1000 7 $gains);Case 'GAIN_PIT_VIBRATO' $true 'Only bits0..2 allowed in new gain family; audio-only'
[void](Bundle 'LEGACY' 1000 0 @());Case 'LEGACY' $true 'No gain artifacts; old flags/semantics preserved'
[void](Clone 'AUDIO_ONLY' @('MOVIE.WZV'));Case 'AUDIO_ONLY' $true 'WZM3 directly gates audio without a video file'
$max=@();for($i=0;$i-lt9999;$i++){$max+=@{t=$i;v=@(($i%15),0,0,0)}};$max+=@{t=10000;v=@(15,15,15,15)}
[void](Bundle 'COUNT10000' 10000 2 $max);Case 'COUNT10000' $true 'Gain count10,000 independent of WZM/WZI counts; exactly80,020 bytes'
[void](Bundle 'DURATION600000' 600000 2 @(@{t=0;v=@(0,0,0,0)},@{t=599999;v=@(14,0,0,0)},@{t=600000;v=@(15,15,15,15)}));Case 'DURATION600000' $true 'Maximum duration; final gain evaluated then owned output stopped'
foreach($pair in @(@('MISSING_GAIN','MOVIE.WZG'),@('MISSING_MARKER','GAIN.REQ'),@('MISSING_INST_MARKER','INST.REQ'),@('MISSING_INSTRUMENT','MOVIE.WZI'))){[void](Clone $pair[0] @($pair[1]));Case $pair[0] $false 'Required bundle member missing'}
foreach($p in @(@('UNKNOWN_FLAG','MOVIE.WZI',16,[byte[]]@(8,0)),@('FLAG_NOT_SET','MOVIE.WZI',16,[byte[]]@(0,0)),@('RESERVED','MOVIE.WZG',16,[byte[]]@(1,0,0,0)),@('HEADER_SIZE','MOVIE.WZG',4,[byte[]]@(19,0)),@('RECORD_SIZE','MOVIE.WZG',6,[byte[]]@(9,0)),@('DURATION_MISMATCH','MOVIE.WZG',12,[BitConverter]::GetBytes([uint32]999)),@('GAIN16','MOVIE.WZG',24,[byte[]]@(16)),@('FIRST_NOT_ZERO','MOVIE.WZG',20,[BitConverter]::GetBytes([uint32]1)),@('DUPLICATE_TIME','MOVIE.WZG',28,[BitConverter]::GetBytes([uint32]0)),@('FINAL_NOT_MUTE','MOVIE.WZG',64,[byte[]]@(14,15,15,15)),@('UNKNOWN_MAGIC','MOVIE.WZG',0,[Text.Encoding]::ASCII.GetBytes('WZG2')))){$dir=Clone $p[0];Change $dir $p[1] $p[2] $p[3];Case $p[0] $false 'Strict header/time/flag/gain validation'}
foreach($p in @(@('MARKER_NEWLINE',"WZG1`n"),@('MARKER_CASE','wzg1'))){$dir=Clone $p[0];[IO.File]::WriteAllText((Join-Path $dir 'GAIN.REQ'),$p[1],[Text.Encoding]::ASCII);Case $p[0] $false 'Marker exactly four ASCII bytes'}
$dir=Clone 'TRAILING';$b=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZG'));[IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZG'),[byte[]]($b+0));Case 'TRAILING' $false 'Exact stream length'
$dir=Clone 'TRUNCATED';$b=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZG'));[IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZG'),$b[0..($b.Length-2)]);Case 'TRUNCATED' $false 'Exact stream length'
$dir=Clone 'COUNT10001';$too=@();for($i=0;$i-lt10000;$i++){$too+=@{t=$i;v=@(0,0,0,0)}};$too+=@{t=10001;v=@(15,15,15,15)};Gain $dir 10001 $too;Case 'COUNT10001' $false 'Gain count beyond independent10,000 limit'
$dir=Clone 'SECOND_BASENAME';Copy-Item -LiteralPath (Join-Path $dir 'MOVIE.WZG') -Destination (Join-Path $dir 'OTHER.WZG');Case 'SECOND_BASENAME' $false 'One marked bundle basename'
foreach($name in @('PIT_BOTH_STRIPPED','PIT_MARKER_STRIPPED','PIT_STREAM_STRIPPED')){$dir=Join-Path $Output $name;New-Item -ItemType Directory $dir|Out-Null;$excluded=switch($name){PIT_BOTH_STRIPPED{@('MOVIE.WZP','PIT.REQ')};PIT_MARKER_STRIPPED{@('PIT.REQ')};PIT_STREAM_STRIPPED{@('MOVIE.WZP')}};foreach($f in Get-ChildItem (Join-Path $Output 'GAIN_PIT') -File|Where-Object{$_.Name-notin$excluded}){Copy-Item -LiteralPath $f.FullName -Destination $dir};Case $name $false 'Explicit WZI PIT requirement survives artifact stripping'}
$dir=Clone 'PIT_UNDECLARED';foreach($f in Get-ChildItem (Join-Path $Output 'GAIN_PIT') -File|Where-Object{$_.Name-in@('MOVIE.WZP','PIT.REQ')}){Copy-Item -LiteralPath $f.FullName -Destination $dir};Case 'PIT_UNDECLARED' $false 'PIT artifacts without declared flag4'
$dir=Clone 'MIXED_WZM1';Change $dir 'MOVIE.WZM' 3 ([byte[]]@(49));Case 'MIXED_WZM1' $false 'Gain family must consume WZM3, never WZM1/WZM2'
$dir=Clone 'MIXED_WZV2';Change $dir 'MOVIE.WZV' 3 ([byte[]]@(50));Case 'MIXED_WZV2' $false 'Included gain video must be WZV4'
[void](Clone 'MISSING_MUSIC' @('MOVIE.WZM'));Case 'MISSING_MUSIC' $false 'WZV4 never falls back to silent video-only when music is removed'
[void](Clone 'ALL_SIDECARS_STRIPPED' @('MOVIE.WZI','INST.REQ','MOVIE.WZG','GAIN.REQ'));Case 'ALL_SIDECARS_STRIPPED' $false 'Direct WZM3/WZV4 gates survive complete sidecar stripping'
$dir=Clone 'CROPPED_GAIN';Gain $dir 1000 @(@{t=0;v=@(4,3,2,1)},@{t=1000;v=@(15,15,15,15)});Case 'CROPPED_GAIN' $true 'First time0 snapshot evaluates source gain at cropped origin; not necessarily all0'
$dir=Clone 'OLD_FLAG4';Change $dir 'MOVIE.WZM' 3 ([byte[]]@(49));Change $dir 'MOVIE.WZV' 3 ([byte[]]@(50));Change $dir 'MOVIE.WZI' 16 ([byte[]]@(4,0));Case 'OLD_FLAG4' $false 'Old family mask remains1'
$dir=Clone 'COUNT1';Gain $dir 1000 @(@{t=0;v=@(15,15,15,15)});Case 'COUNT1' $false 'At least two records'
[void](Bundle 'DURATION600001' 600001 2 @(@{t=0;v=@(0,0,0,0)},@{t=600001;v=@(15,15,15,15)}));Case 'DURATION600001' $false '600s limit unchanged'
$dir=Clone 'MUSIC_FINAL_NOT_REST';$b=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZM'));$b[$b.Length-10]=69;$b[$b.Length-6]=100;[IO.File]::WriteAllBytes((Join-Path $dir 'MOVIE.WZM'),$b);Case 'MUSIC_FINAL_NOT_REST' $false 'Gain terminal15 cannot replace final logical rest'
$dir=Clone 'OWNER_AUDIO' @('MOVIE.WZV');$duration=235000
$w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZM')))
try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZM3'));$w.Write([ushort]20);$w.Write([ushort]14);$w.Write([uint32]4);$w.Write([uint32]$duration);$w.Write([uint32]0);foreach($s in @(@{t=0;n=69;v=100;r=1},@{t=233836;n=69;v=100;r=1},@{t=234000;n=69;v=100;r=0},@{t=235000;n=0;v=0;r=0})){$w.Write([uint32]$s.t);$w.Write([byte[]]@($s.n,0,0,0,$s.v,0,0,0,$s.r,0))}}finally{$w.Dispose()}
$w=[IO.BinaryWriter]::new([IO.File]::Create((Join-Path $dir 'MOVIE.WZI')));try{$w.Write([Text.Encoding]::ASCII.GetBytes('WZI1'));$w.Write([ushort]20);$w.Write([ushort]8);$w.Write([uint32]1);$w.Write([uint32]$duration);$w.Write([ushort]2);$w.Write([ushort]258);$w.Write([uint32]0);$w.Write([byte[]]@(16,0,0,0))}finally{$w.Dispose()}
$ownerAudio=$dir
Gain $ownerAudio $duration @(@{t=0;v=@(0,0,0,0)},@{t=228000;v=@(1,0,0,0)},@{t=230600;v=@(2,0,0,0)},@{t=233836;v=@(0,0,0,0)},@{t=234000;v=@(0,0,0,0)},@{t=235000;v=@(15,15,15,15)})
Case 'OWNER_AUDIO' $true 'Cue04 same-note/velocity handover retriggers, resets selected owner gain; cue03 scoped off leaves cue04'
function Need($ok,$why){if(!$ok){throw [IO.InvalidDataException]::new($why)}}
function Validate($dir){
    $ip=Join-Path $dir 'MOVIE.WZI';Need (Test-Path $ip) 'missing WZI';$i=[IO.File]::ReadAllBytes($ip);Need ($i.Length-ge20-and[Text.Encoding]::ASCII.GetString($i,0,4)-ceq'WZI1') 'WZI header'
    $flags=[BitConverter]::ToUInt16($i,16);$duration=[BitConverter]::ToUInt32($i,12);Need ([BitConverter]::ToUInt16($i,18)-eq258-and$duration-ge1-and$duration-le600000) 'engine/duration'
    Need (Test-Path (Join-Path $dir 'MOVIE.WZM')) 'missing mandatory music';$music=[IO.File]::ReadAllBytes((Join-Path $dir 'MOVIE.WZM'));$family=[Text.Encoding]::ASCII.GetString($music,0,4);$gainFamily=$family-ceq'WZM3';Need ($(if($gainFamily){($flags-band65528)-eq0-and($flags-band2)-ne0}else{($flags-band65534)-eq0})) 'unknown flag/family'
    $video=Join-Path $dir 'MOVIE.WZV';if(Test-Path $video){$v=[IO.File]::ReadAllBytes($video);Need ([Text.Encoding]::ASCII.GetString($v,0,4)-ceq$(if($gainFamily){'WZV4'}else{'WZV2'})-and[BitConverter]::ToUInt32($v,16)-eq$duration) 'video family/duration'}
    $marker=Join-Path $dir 'GAIN.REQ';$path=Join-Path $dir 'MOVIE.WZG';$required=($flags-band2)-ne0
    if(!$required){Need (!$gainFamily-and!(Test-Path $marker)-and!(Test-Path $path)) 'gain without flag';return}
    Need $gainFamily 'gain requires WZM3'
    Need ((Test-Path $marker)-and(Test-Path $path)-and(Test-Path (Join-Path $dir 'INST.REQ'))) 'missing required member'
    Need ([Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($marker))-ceq'WZG1'-and[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes((Join-Path $dir 'INST.REQ')))-ceq'WZI1') 'marker bytes'
    foreach($f in Get-ChildItem $dir -File){if($f.Extension.ToUpperInvariant().StartsWith('.WZ')){Need ($f.BaseName-ieq'MOVIE'-and$f.Extension.ToUpperInvariant()-in@('.WZM','.WZI','.WZG','.WZV','.WZP')) 'basename/unknown WZ'}}
    Need ([BitConverter]::ToUInt32($music,12)-eq$duration-and[BitConverter]::ToUInt32($music,16)-eq0) 'music duration/reserved'
    $mn=[BitConverter]::ToUInt32($music,8);Need ($mn-ge2-and$mn-le10000-and$music.Length-eq20+14*$mn-and[BitConverter]::ToUInt16($music,4)-eq20-and[BitConverter]::ToUInt16($music,6)-eq14) 'music count/layout'
    $mt=-1L;for($n=0;$n-lt$mn;$n++){$at=20+14*$n;$t=[BitConverter]::ToUInt32($music,$at);Need ($t-gt$mt-and$t-le$duration-and($n-ne0-or$t-eq0)-and($music[$at+12]-band240)-eq0-and$music[$at+13]-eq0) 'music times/flags';$mt=$t;for($lane=0;$lane-lt4;$lane++){$note=$music[$at+4+$lane];$vel=$music[$at+8+$lane];Need ($vel-le127-and(($note-eq0-and$vel-eq0)-or($vel-gt0-and$note-ge$(if($lane-eq3){35}else{45})-and$note-le$(if($lane-eq3){81}else{96})))) 'music note/velocity'}};Need ($mt-eq$duration-and!($music[($music.Length-10)..($music.Length-1)]|Where-Object{$_-ne0})) 'music final logical rest'
    $ic=[BitConverter]::ToUInt32($i,8);Need ($ic-ge1-and$ic-le10000-and$i.Length-eq20+8*$ic-and[BitConverter]::ToUInt16($i,4)-eq20-and[BitConverter]::ToUInt16($i,6)-eq8) 'instrument layout';$it=-1L;for($n=0;$n-lt$ic;$n++){$at=20+8*$n;$t=[BitConverter]::ToUInt32($i,$at);Need ($t-gt$it-and$t-le$duration-and($n-ne0-or$t-eq0)-and$i[$at+7]-eq0) 'instrument times/reserved';$it=$t;foreach($p in $i[($at+4)..($at+6)]){Need ($p-in@(0,16,32,48,64,80,96,112)) 'instrument program'}}
    $pit=Join-Path $dir 'MOVIE.WZP';$pitMarker=Join-Path $dir 'PIT.REQ';if($flags-band4){Need ((Test-Path $pit)-and(Test-Path $pitMarker)) 'declared PIT missing';$p=[IO.File]::ReadAllBytes($pit);Need ($p.Length-eq32-and[Text.Encoding]::ASCII.GetString($p,0,4)-ceq'WZP1'-and[BitConverter]::ToUInt32($p,8)-eq$duration-and[Text.Encoding]::ASCII.GetString([IO.File]::ReadAllBytes($pitMarker))-ceq'WZP1') 'PIT pairing'}else{Need (!(Test-Path $pit)-and!(Test-Path $pitMarker)) 'PIT undeclared'}
    $b=[IO.File]::ReadAllBytes($path);Need ($b.Length-ge20-and[Text.Encoding]::ASCII.GetString($b,0,4)-ceq'WZG1'-and[BitConverter]::ToUInt16($b,4)-eq20-and[BitConverter]::ToUInt16($b,6)-eq8-and[BitConverter]::ToUInt32($b,16)-eq0) 'gain header'
    $count=[BitConverter]::ToUInt32($b,8);Need ($count-ge2-and$count-le10000-and$b.Length-eq20+8*$count-and[BitConverter]::ToUInt32($b,12)-eq$duration) 'gain count/length/duration'
    $last=-1L;for($n=0;$n-lt$count;$n++){$at=20+8*$n;$t=[BitConverter]::ToUInt32($b,$at);Need ($t-gt$last-and$t-le$duration-and($n-ne0-or$t-eq0)) 'gain times';$last=$t;foreach($v in $b[($at+4)..($at+7)]){Need ($v-le15) 'gain step'}}
    Need ($last-eq$duration-and!($b[($b.Length-4)..($b.Length-1)]|Where-Object{$_-ne15})) 'gain final mute'
}
foreach($case in $cases){$accept=$true;try{Validate (Join-Path $Output $case.name)}catch [IO.InvalidDataException]{$accept=$false};if($accept-ne$case.proposed_accept){throw ('Reference mismatch: '+$case.name)}}
$queries=@();foreach($t in @(0,249,250,499,500,501,504,505,506,749,750,999,1000)){$g=$gains|Where-Object{$_.t-le$t}|Select-Object -Last 1;$queries+=@{time_ms=$t;extra_steps=$g.v;attack_ms=@($(if($t-ge500){500}else{0}),0,0,0);attack_presets=@($(if($t-ge500){5}else{1}),3,5,10);attack_velocities=@(100,90,80,100);hat_envelope_expired=($t-ge165);terminal=($t-eq1000);flushes_at_timestamp=1;gain_bypasses_envelope_quantum_cache=$true;extra_added_once_to_InstRead=$true}}
$queries|ConvertTo-Json -Depth 5|Set-Content (Join-Path $Output 'ORDERING-QUERIES.json')
$ownerQueries=@(@{time_ms=233835;owner='c03';note=69;velocity=100;attack_ms=0;extra=2},@{time_ms=233836;owner='c04';note=69;velocity=100;attack_ms=233836;extra=0;retrigger=1},@{time_ms=234000;owner='c04';note=69;velocity=100;attack_ms=233836;extra=0;retrigger=0},@{time_ms=235000;owner='none';note=0;velocity=0;extra=15})
$ownerQueries|ConvertTo-Json -Depth 5|Set-Content (Join-Path $Output 'OWNER-QUERIES.json')
Copy-Item -LiteralPath (Join-Path (Split-Path $PSScriptRoot) 'WZG1.md') -Destination (Join-Path $Output 'WZG1.md')
$files=@();foreach($f in Get-ChildItem $Output -Recurse -File){$files+=@{path=[IO.Path]::GetRelativePath($Output,$f.FullName);bytes=$f.Length;sha256=(Get-FileHash $f.FullName).Hash}}
@{status='REVISION1 REFERENCE CONTRACT; agreed identifiers/semantics; runtime qualification separate; no production gain emission';spec_sha256=(Get-FileHash (Join-Path $Output 'WZG1.md')).Hash;family='WZM3 required; included video must be WZV4; old families unchanged';layout='WZG1/20/8/u32count/u32duration/u32reserved0; timestamp u32 + four u8 PSG extra steps';flags='In gain family WZI bit0 vibrato, bit1 gain-required, bit2 PIT-required; outside gain family old rules unchanged';marker='GAIN.REQ exactly WZG1; INST.REQ exactly WZI1; flag4 also exact PIT.REQ=WZP1 plus WZP1';cases=$cases;files=$files;reference_pass=$true}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $Output 'MANIFEST.json')
Write-Output ('PASS proposal reference: '+$cases.Count+' exact synthetic bundle decisions; no production gain export')
