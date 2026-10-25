$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$source=Get-Content "$repo/马赛克刺客/本轮来源.json" -Raw|ConvertFrom-Json
$archive="$repo/马赛克刺客/制作版本/v1-佣兵与洗点补给"
$report=Get-Content "$archive/校验清单.json" -Raw|ConvertFrom-Json
if(!$report.Validation.UndoChangesReproducesSourceBytes -or !$report.Validation.MercenaryAllThreeItemsWearable){throw 'Candidate not verified'}
$cn=Join-Path $env:USERPROFILE 'Saved Games/Diablo II Resurrected (CN)'
$expected=@($source.Files.Name|Sort-Object);$actual=@(Get-ChildItem -LiteralPath $cn -File|Where-Object BaseName -eq Mosaic|Select-Object -ExpandProperty Name|Sort-Object)
if(($expected -join '|') -ne ($actual -join '|')){throw 'Source companion file set changed'}
foreach($f in $source.Files){if((Get-FileHash -LiteralPath (Join-Path $cn $f.Name)).Hash -ne $f.SHA256){throw "Source changed; take a fresh snapshot: $($f.Name)"}}
$p=Join-Path $archive 'Mosaic.d2s';if((Get-FileHash -LiteralPath $p).Hash -ne $report.SHA256){throw 'Candidate hash mismatch'}
$destination=Join-Path $cn 'Mosaic.d2s'
Copy-Item -LiteralPath $p -Destination $destination
if((Get-FileHash -LiteralPath $destination).Hash -ne $report.SHA256 -or [Convert]::ToHexString([IO.File]::ReadAllBytes($destination)) -ne [Convert]::ToHexString([IO.File]::ReadAllBytes($p))){throw 'Copied save differs'}
foreach($f in $source.Files|Where-Object Name -ne 'Mosaic.d2s'){if((Get-FileHash -LiteralPath (Join-Path $cn $f.Name)).Hash -ne $f.SHA256){throw 'Companion file changed'}}
$delivery=[ordered]@{Date=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time').ToString('o');Character='Mosaic';Source='马赛克刺客/制作版本/v1-佣兵与洗点补给/Mosaic.d2s';Destination=$destination;SHA256=$report.SHA256;Bytes=$report.Bytes;PreWriteAllSameNameHashesMatch=$true;SourceTargetSHA256AndBytesMatch=$true;WrittenFiles=@('Mosaic.d2s');CompanionFilesUnchanged=$true;SharedStashTouched=$false;Backup=$source.Snapshot;Authorization='按AGENTS.md既有约定：修改时同步归档和国服，目标人物未使用'}
$delivery|ConvertTo-Json -Depth 6|Set-Content "$repo/马赛克刺客/国服同步校验.json" -Encoding utf8
$delivery|ConvertTo-Json -Depth 6
