param([switch]$Tested)
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$source=Get-Content $(if($Tested){"$repo/冰法/评测回存来源.json"}else{"$repo/冰法/本轮来源.json"}) -Raw|ConvertFrom-Json
$archive=if($Tested){"$repo/冰法/实测定稿"}else{"$repo/冰法/实测回存调整"}
$report=Get-Content "$archive/校验清单.json" -Raw|ConvertFrom-Json
if(!$report.Validation.MercenaryAllThreeItemsWearable){throw 'All three mercenary items must pass requirement checks before sync'}
$cn=Join-Path $env:USERPROFILE 'Saved Games/Diablo II Resurrected (CN)'
# Any newer game progress invalidates this candidate; never overwrite it.
foreach($f in $source.Files){if((Get-FileHash -LiteralPath (Join-Path $cn $f.Name)).Hash -ne $f.SHA256){throw "Game source changed: $($f.Name); take a fresh snapshot"}}
$p=Join-Path $archive 'BlizzSorc.d2s'
if((Get-FileHash -LiteralPath $p).Hash -ne $report.SHA256){throw 'Archive hash mismatch'}
$destination=Join-Path $cn 'BlizzSorc.d2s'
Copy-Item -LiteralPath $p -Destination $destination
if((Get-FileHash -LiteralPath $destination).Hash -ne $report.SHA256 -or [Convert]::ToHexString([IO.File]::ReadAllBytes($destination)) -ne [Convert]::ToHexString([IO.File]::ReadAllBytes($p))){throw 'Copied file differs'}
foreach($f in $source.Files|Where-Object Name -ne 'BlizzSorc.d2s'){if((Get-FileHash -LiteralPath (Join-Path $cn $f.Name)).Hash -ne $f.SHA256){throw 'Companion file changed'}}
$delivery=[ordered]@{Date=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time').ToString('o');Character='BlizzSorc';Source=$(if($Tested){'冰法/实测定稿/BlizzSorc.d2s'}else{'冰法/实测回存调整/BlizzSorc.d2s'});Destination=$destination;SHA256=$report.SHA256;Bytes=(Get-Item $destination).Length;PreWriteAllSameNameHashesMatch=$true;SourceTargetSHA256AndBytesMatch=$true;WrittenFiles=@('BlizzSorc.d2s');CompanionFilesUnchanged=$true;SharedStashTouched=$false;Backup=$source.Snapshot;Authorization='用户要求修改并同步国服与归档；已有目标人物未使用时可同步约定'}
$delivery|ConvertTo-Json -Depth 5|Set-Content $(if($Tested){"$repo/冰法/实测回存同步校验.json"}else{"$repo/冰法/国服同步校验.json"}) -Encoding utf8
$delivery|ConvertTo-Json -Depth 5
