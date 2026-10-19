param([string]$PlanPath=(Join-Path $PSScriptRoot '本轮归档来源.json'))
$ErrorActionPreference='Stop'
$repo=Split-Path $PSScriptRoot -Parent
$game=Join-Path $env:USERPROFILE 'Saved Games\Diablo II Resurrected (CN)'
$entries=@(Get-Content -LiteralPath $PlanPath -Raw|ConvertFrom-Json)
# Validate both characters and all companion files before writing either save.
foreach($entry in $entries){
 $names=@(Get-ChildItem -LiteralPath $game -Filter ($entry.Name+'.*') -File|ForEach-Object Name|Sort-Object)
 if(($names -join '|') -ne (($entry.Files.Name|Sort-Object) -join '|')){throw "File list changed: $($entry.Name)"}
 foreach($file in $entry.Files){
  foreach($path in @((Join-Path $game $file.Name),(Join-Path $entry.Snapshot $file.Name))){
   if((Get-FileHash -LiteralPath $path).Hash -ne $file.SHA256){throw "Game or snapshot changed: $($file.Name)"}
  }
 }
 $supply=Get-Content -LiteralPath (Join-Path $entry.Output '补给校验.json') -Raw|ConvertFrom-Json
 if((Get-FileHash -LiteralPath (Join-Path $entry.Output ($entry.Name+'.d2s'))).Hash -ne $supply.SHA256){throw 'Archive output changed'}
}
foreach($entry in $entries){
 $current=Join-Path $repo ($entry.BD+'\实测定稿')
 if($entry.Output -ne $current){
  foreach($file in Get-ChildItem -LiteralPath $entry.Output -File){Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $current $file.Name) -Force}
 }
 $source=Join-Path $current ($entry.Name+'.d2s');$target=Join-Path $game ($entry.Name+'.d2s')
 $expected=(Get-FileHash -LiteralPath $source).Hash
 # Recheck immediately before this particular write, including after the first character.
 foreach($file in $entry.Files){if((Get-FileHash -LiteralPath (Join-Path $game $file.Name)).Hash -ne $file.SHA256){throw "Game changed before write: $($file.Name)"}}
 $previousRecord=Join-Path $repo ($entry.BD+'\国服导入校验.json')
 if(Test-Path -LiteralPath $previousRecord){Copy-Item -LiteralPath $previousRecord -Destination (Join-Path $entry.History '此前国服导入记录.json')}
 Copy-Item -LiteralPath $source -Destination $target -Force
 if((Get-FileHash -LiteralPath $target).Hash -ne $expected -or [Convert]::ToHexString([IO.File]::ReadAllBytes($target)) -ne [Convert]::ToHexString([IO.File]::ReadAllBytes($source))){throw 'Copied character mismatch'}
 foreach($file in $entry.Files|Where-Object Name -notlike '*.d2s'){if((Get-FileHash -LiteralPath (Join-Path $game $file.Name)).Hash -ne $file.SHA256){throw "Companion changed: $($file.Name)"}}
 $record=[ordered]@{Date=(Get-Date).ToString('o');Character=$entry.Name;Source=$source;Destination=$target;Bytes=(Get-Item -LiteralPath $target).Length;SHA256=$expected;PreviousGameSHA256=($entry.Files|Where-Object Name -like '*.d2s').SHA256;BackupDirectory=$entry.History;BackedUpSameNameFiles=$entry.Files.Count;SourceHashesRecheckedBeforeWrite=$true;SourceTargetHashesMatch=$true;ByteForByteMatch=$true;CopiedFiles=@($entry.Name+'.d2s');CompanionFilesUnchanged=$true;SharedStashTouched=$false;Authorization='User requested both characters gold refill, archive and one new PR; existing permission allows sync while these characters are not being played';GameProcessRunning=(@(Get-Process -Name D2R -ErrorAction SilentlyContinue).Count -gt 0)}
 $record|ConvertTo-Json -Depth 5|Set-Content -LiteralPath $previousRecord -Encoding utf8
 $record|ConvertTo-Json -Depth 5
}
