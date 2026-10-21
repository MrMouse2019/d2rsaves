$ErrorActionPreference='Stop'
. "$PSScriptRoot/common.ps1"
$source=Get-Content "$repo/冰法/评测回存来源.json" -Raw|ConvertFrom-Json
$snap=Join-Path $repo $source.Snapshot
$out="$repo/冰法/实测定稿"
Require (!(Test-Path $out)) 'Preserve existing template first'
New-Item -ItemType Directory -Path $out|Out-Null
foreach($f in $source.Files){Require ((Get-FileHash (Join-Path $snap $f.Name)).Hash -eq $f.SHA256) 'Snapshot changed';Copy-Item -LiteralPath (Join-Path $snap $f.Name) -Destination $out}
$p=Join-Path $out 'BlizzSorc.d2s';$s=[IceEdit]::Read($p);$raw=[IO.File]::ReadAllBytes($p)
Require (Same ([IceEdit]::Bytes($s)) $raw) 'Source roundtrip'
$old=@{};foreach($i in $s.Items|Where-Object {$_.Position.Mode -eq 'InBelt'}){$old[$s.Items.IndexOf($i)]=$i.ItemCodeString;$i.ItemCodeString='rvl'}
Require ($old.Count -eq 16) 'Unexpected belt capacity; inspect source'
[IO.File]::WriteAllBytes($p,[IceEdit]::Bytes($s))
$undo=[IceEdit]::Read($p);foreach($n in $old.Keys){$undo.Items[[int]$n].ItemCodeString=$old[$n]}
Require (Same ([IceEdit]::Bytes($undo)) $raw) 'Non-belt data changed'
& "$PSScriptRoot/verify.ps1" -SavePath $p|Set-Content "$out/文件验证.json" -Encoding utf8
$audit=Get-Content "$out/文件验证.json" -Raw|ConvertFrom-Json
$manifest=[ordered]@{Date=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time').ToString('o');Status='用户实测认可归档；适合低人数刷图，8PP效率不如新星；PR待审核';Character='BlizzSorc';SHA256=$audit.SHA256;Bytes=$audit.Bytes;SourceSnapshot=$source.Snapshot;SourceSHA256=(Get-FileHash (Join-Path $snap 'BlizzSorc.d2s')).Hash;Files=@(Get-ChildItem $out -Filter 'BlizzSorc.*'|ForEach-Object {[ordered]@{Name=$_.Name;Bytes=$_.Length;SHA256=(Get-FileHash $_.FullName).Hash}});Validation=$audit;OnlyBeltChangedFromLatestGameSource=$true;BeltBefore=@($old.Values);BeltAfter='16 rvl';SharedStashTouched=$false}
$manifest|ConvertTo-Json -Depth 10|Set-Content "$out/校验清单.json" -Encoding utf8
$manifest|ConvertTo-Json -Depth 10
