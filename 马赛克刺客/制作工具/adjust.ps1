param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$OutputPath)
. "$PSScriptRoot/../../冰法/制作工具/common.ps1"
Require (!(Test-Path -LiteralPath $OutputPath)) 'Output exists'
$raw=[IO.File]::ReadAllBytes($SourcePath);$s=[IceEdit]::Read($SourcePath)
Require ($s.Version -eq 105 -and $s.Character.Preview.Name -eq 'Mosaic' -and $s.Character.Level -eq 99 -and $s.Stats.GetStat(12) -eq 99 -and [int]$s.Skills.CharacterClass -eq 6) 'Wrong source'
Require (Same ([IceEdit]::Bytes($s)) $raw) 'Source roundtrip'
$count=$s.Items.Count
$donorPath="$repo/新星电法/实测定稿/NovaPerfect.d2s";$donor=[IceEdit]::Read($donorPath)
$slots=@('Head','Torso');$moved=@()
foreach($body in $slots){
 $old=@($s.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq $body});$new=@($donor.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq $body})
 Require ($old.Count -eq 1 -and $new.Count -eq 1) 'Merc slot count'
 $old=$old[0];$new=$new[0];Reseed $new;$new.Position=$old.Position
 $s.MercItems.Items[$s.MercItems.Items.IndexOf($old)]=$new
 Stash $s $old;$s.Items.Add($old)
 $moved+=@{Slot=$body;Code=$old.ItemCodeString;X=$old.Position.InvX;Y=$old.Position.InvY}
}
$token=@($misc|Where-Object code -eq 'toa');Require ($token.Count -eq 1 -and $token[0].name -eq 'Token of Absolution' -and $token[0].compactsave -eq '0' -and $token[0].invwidth -eq '1' -and $token[0].invheight -eq '1') 'Token data table mismatch'
for($n=0;$n -lt 20;$n++){
 $i=[D2SSharp.Model.Item]::new();$i.ItemCodeString=$token[0].code;$i.Version=101;$i.ItemLevel=99;$i.ItemSeed=Seed
 $i.Flags=[D2SSharp.Enums.ItemFlags]::Identified -bor [D2SSharp.Enums.ItemFlags]::JustSaved
 $i.Quality=[D2SSharp.Enums.ItemQuality]::Normal
 Stash $s $i;$s.Items.Add($i)
}
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force|Out-Null
[IO.File]::WriteAllBytes($OutputPath,[IceEdit]::Bytes($s))
$v=[IceEdit]::Read($OutputPath);$bytes=[IO.File]::ReadAllBytes($OutputPath)
Require ([Convert]::ToHexString($bytes[0..3]) -eq '55AA55AA' -and [BitConverter]::ToUInt32($bytes,8) -eq $bytes.Length -and [BitConverter]::ToUInt32($bytes,12) -eq [IceEdit]::Sum($bytes)) 'Header length checksum'
Require (Same ([IceEdit]::Bytes($v)) $bytes) 'Written roundtrip'
foreach($page in @('Inventory','Cube','Stash')){[void](Grid $v $page)}
$tokens=@($v.Items|Where-Object {$_.ItemCodeString -eq 'toa' -and $_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Stash'})
Require ($tokens.Count -eq 20 -and $v.Items.Count -eq $count+22) 'Token count or added item count'
foreach($i in $tokens){Require ($i.Quality -eq 'Normal' -and !$i.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::CompactSave) -and $i.Stats.Count -eq 0) 'Malformed token'}
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
$original=[IceEdit]::Read($SourcePath);$undo=[IceEdit]::Read($OutputPath)
for($n=0;$n -lt 2;$n++){
 $body=$slots[$n];$old=$undo.Items[$count+$n];$originalSlot=@($original.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq $body})[0]
 $old.Position=$originalSlot.Position;$current=@($undo.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq $body})[0];$undo.MercItems.Items[$undo.MercItems.Items.IndexOf($current)]=$old
}
while($undo.Items.Count -gt $count){$undo.Items.RemoveAt($undo.Items.Count-1)}
Require (Same ([IceEdit]::Bytes($undo)) $raw) 'Unrelated data changed'
$newSeeds=@($tree|Where-Object {$_.ItemSeed -ne 0 -and $_.ItemSeed -notin @((Tree $original.Items).ItemSeed+(Tree $original.MercItems.Items).ItemSeed)})
Require (@($newSeeds.ItemSeed|Sort-Object -Unique).Count -eq $newSeeds.Count) 'Duplicate new item seeds'
$report=[ordered]@{Date=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time').ToString('o');Character='Mosaic';Level=99;Format=105;Bytes=$bytes.Length;SHA256=(Get-FileHash $OutputPath).Hash;SourceSHA256=(Get-FileHash $SourcePath).Hash;DonorSHA256=(Get-FileHash $donorPath).Hash;LibrarySHA256=(Get-FileHash $lib).Hash;Status='本次佣兵调整与洗点补给待游戏实测';Mercenary=@{Level=$lvl;Aura=$hire.Skill2;HirelingId=$v.Character.MercData.HirelingId;BaseStrength=$strength;BaseDexterity=$dex;Weapon='原无限原样保留';Helm='满变量无形超强骸骨面罩治愈';Armor='无形超强执政官铠甲荣耀之链';OldGearRetainedInStash=$moved};TokensAdded=20;TokenCode=$token[0].code;BeltFullRejuvenation=16;SkillsSpent=($v.Skills.SkillLevels|Measure-Object -Sum).Sum;Unspent=$v.Stats.GetStat(5);Validation=@{HeaderLengthChecksum=$true;WrittenRoundtrip=$true;UndoChangesReproducesSourceBytes=$true;AllStorageBoundsAndOverlap=$true;MercenaryAllThreeItemsWearable=$true;NewSeedsUnique=$true;RenewedSunderTypeAndSevenStats=$true;ColossalJewels=$jewels.Count;SkillsStatsGoldProgressInfinityAndExistingItemsPreserved=$true;InGameRetestPending=$true}}
$report|ConvertTo-Json -Depth 9|Set-Content (Join-Path (Split-Path $OutputPath -Parent) '校验清单.json') -Encoding utf8
$report|ConvertTo-Json -Depth 9
