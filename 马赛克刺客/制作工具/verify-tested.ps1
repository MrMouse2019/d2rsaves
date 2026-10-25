param([string]$SavePath="$PSScriptRoot/../实测定稿/Mosaic.d2s")
. "$PSScriptRoot/../../冰法/制作工具/common.ps1"
$source=Get-Content "$repo/马赛克刺客/评测回存来源.json" -Raw|ConvertFrom-Json
$s=[IceEdit]::Read($SavePath);$raw=[IO.File]::ReadAllBytes($SavePath)
Require ($s.Version -eq 105 -and $s.Character.Preview.Name -eq 'Mosaic' -and $s.Character.Level -eq 99 -and $s.Stats.GetStat(12) -eq 99 -and [int]$s.Skills.CharacterClass -eq 6) 'Wrong character/version'
Require ([Convert]::ToHexString($raw[0..3]) -eq '55AA55AA' -and [BitConverter]::ToUInt32($raw,8) -eq $raw.Length -and [BitConverter]::ToUInt32($raw,12) -eq [IceEdit]::Sum($raw)) 'Header length checksum'
Require (Same ([IceEdit]::Bytes($s)) $raw) 'Written roundtrip'
Require (Same $raw ([IO.File]::ReadAllBytes((Join-Path $repo "$($source.Snapshot)/Mosaic.d2s")))) 'Latest game snapshot differs'
foreach($page in @('Inventory','Cube','Stash')){[void](Grid $s $page)}
$spent=($s.Skills.SkillLevels|Measure-Object -Sum).Sum;$unspent=$s.Stats.GetStat(5)
Require ($spent -eq 109 -and $unspent -eq 1 -and $spent+$unspent -eq 110) 'Latest skill allocation mismatch'
$tokens=@($s.Items|Where-Object {$_.ItemCodeString -eq 'toa' -and $_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Stash'})
Require ($tokens.Count -eq 19) 'Expected 19 remaining tokens'
foreach($i in $tokens){Require ($i.Quality -eq 'Normal' -and !$i.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::CompactSave) -and $i.Stats.Count -eq 0) 'Malformed token'}
$belt=@($s.Items|Where-Object {$_.Position.Mode -eq 'InBelt'});Require ($belt.Count -eq 16 -and @($belt|Where-Object ItemCodeString -ne rvl).Count -eq 0) 'Belt not full rejuvenation'
foreach($x in 0..15){Require (@($belt|Where-Object {$_.Position.InvX -eq $x -and $_.Position.InvY -eq 0}).Count -eq 1) 'Belt slot mismatch'}
$v=$s
$mh=@($v.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq 'Head'})[0];$ma=@($v.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq 'Torso'})[0];$mw=@($v.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq 'RightArm'})[0]
Require ($mh.ItemCodeString -eq 'uh9' -and $mh.RunewordId -eq 27367 -and ($mh.Sockets.ItemCodeString -join ',') -eq 'r13,r16,r07' -and (Value $mh 151 109 -RW) -eq 1 -and (Value $mh 16 -RW) -eq 100 -and (Value $mh 45 -RW) -eq 30) 'Cure mismatch'
Require ($ma.ItemCodeString -eq 'utp' -and $ma.RunewordId -eq 20520 -and ($ma.Sockets.ItemCodeString -join ',') -eq 'r14,r22,r30,r24' -and (Value $ma 0 -RW) -eq 20 -and (Value $ma 60 -RW) -eq 8 -and (Value $ma 127 -RW) -eq 2 -and (Value $ma 16 -RW) -eq 70) 'Chains of Honor mismatch'
foreach($id in @(39,41,43,45)){Require ((Value $ma $id -RW) -eq 50) 'CoH all resistance'}
foreach($i in @($mh,$ma)){Require ($i.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::Ethereal) -and (Value $i 16) -eq 15 -and (Value $i 75) -eq 15) 'Perfect ethereal superior base'}
Require ($mw.RunewordId -eq 20566 -and ($mw.Sockets.ItemCodeString -join ',') -eq 'r30,r23,r30,r24') 'Infinity missing'
$hire=@(Import-Csv "$repo/冰法/制作工具/hireling.txt" -Delimiter "`t"|Where-Object {$_.Id -eq $v.Character.MercData.HirelingId -and $_.Level -eq '75'})
Require ($hire.Count -eq 1 -and $v.Character.MercData.HasMerc -and !$v.Character.MercData.IsDead) 'Mercenary missing/dead'
$hire=$hire[0];$lvl=1;while($lvl -lt 99 -and [long]$hire.'Exp/Lvl'*($lvl+1)*($lvl+1)*($lvl+2) -le $v.Character.MercData.Experience){$lvl++}
Require ($lvl -eq 98) 'Recalculate mercenary level'
$strength=[int][math]::Floor([int]$hire.Str+($lvl-75)*[int]$hire.'Str/Lvl'/8);$dex=[int][math]::Floor([int]$hire.Dex+($lvl-75)*[int]$hire.'Dex/Lvl'/8)
foreach($i in @($mh,$ma,$mw)){
 $row=@($armor+$weapons|Where-Object code -eq $i.ItemCodeString)[0];$eth=if($i.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::Ethereal)){10}else{0}
 Require ($strength -ge ([int]$row.reqstr-$eth) -and $dex -ge ([int]$row.reqdex-$eth) -and $lvl -ge [int]$row.levelreq) 'Merc cannot equip base without old helm'
}
Require ($lvl -ge 83) 'Merc rune level requirements'
$belt=@($v.Items|Where-Object {$_.Position.Mode -eq 'InBelt'});Require ($belt.Count -eq 16 -and @($belt|Where-Object ItemCodeString -ne rvl).Count -eq 0) 'Belt must contain 16 full rejuvenations'
foreach($x in 0..15){Require (@($belt|Where-Object {$_.Position.InvX -eq $x -and $_.Position.InvY -eq 0}).Count -eq 1) 'Belt layout'}
function Tree($items){foreach($i in $items){if($null -eq $i){continue};$i;Tree $i.Sockets}}
$tree=@(Tree $v.Items)+@(Tree $v.MercItems.Items)
$jewels=@($tree|Where-Object {$_.Quality -eq 'Unique' -and $_.ItemCodeString -eq 'cjw' -and $_.QualityData.FileIndex -ge 420 -and $_.QualityData.FileIndex -le 429});Require ($jewels.Count -le 1) 'Colossal jewel limit'
$sunder=@($v.Items|Where-Object ItemCodeString -eq cs2);Require ($sunder.Count -eq 1 -and $sunder[0].QualityData.FileIndex -eq 434 -and $sunder[0].Stats.Count -eq 7 -and (Value $sunder[0] 41) -eq -70 -and (Value $sunder[0] 334) -eq 10 -and (Value $sunder[0] 7) -eq 16640 -and (Value $sunder[0] 35) -eq 10 -and (Value $sunder[0] 99) -eq 24 -and (Value $sunder[0] 80) -eq 25 -and (Value $sunder[0] 190) -eq 300) 'Source sunder changed/malformed'
$inv=@($s.Items|Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Inventory'})
foreach($code in @('box','ibk','tbk')){Require (@($inv|Where-Object ItemCodeString -eq $code).Count -eq 1) "Missing inventory tool $code"}
foreach($index in @(381,400)){Require (@($inv|Where-Object {$_.Quality -eq 'Unique' -and $_.QualityData.FileIndex -eq $index}).Count -eq 1) 'Missing Torch/Annihilus'}
Require (@($s.Items|Where-Object {$_.Position.Mode -eq 'Equipped' -and $_.RunewordId -eq 27362}).Count -eq 2) 'Mosaic claws missing'
$stash=@($s.Items|Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Stash'})
Require (@($stash|Where-Object {$_.ItemCodeString -eq 'usk' -and $_.QualityData.FileIndex -eq 345}).Count -eq 1 -and @($stash|Where-Object RunewordId -eq 20547).Count -eq 1) 'Old mercenary gear not retained'
foreach($f in $source.Files){Require ((Get-FileHash -LiteralPath (Join-Path $repo "$($source.Snapshot)/$($f.Name)" )).Hash -eq $f.SHA256) 'Snapshot hash mismatch'}
[ordered]@{Result='PASS';Character='Mosaic';Level=99;Format=105;Bytes=$raw.Length;SHA256=(Get-FileHash -LiteralPath $SavePath).Hash;HeaderLengthChecksum=$true;WrittenRoundtrip=$true;LatestGameSnapshotByteIdentical=$true;AllStorageBoundsAndOverlap=$true;SkillsSpent=$spent;SkillsUnspent=$unspent;TokensRemaining=$tokens.Count;BeltFullRejuvenation=$belt.Count;Mercenary=@{Level=$lvl;Aura=$hire.Skill2;HirelingId=$v.Character.MercData.HirelingId;AllThreeItemsWearable=$true;Weapon='无限';Helm='治愈';Armor='荣耀之链';OldHeadAndArmorRetained=$true};RenewedLightningSunderTypeAndSevenStats=$true;ColossalJewels=$jewels.Count;Gold=$s.Stats.GetStat(14);PersonalStashGold=$s.Stats.GetStat(15);SourceBackupFilesVerified=$source.Files.Count}|ConvertTo-Json -Depth 8
