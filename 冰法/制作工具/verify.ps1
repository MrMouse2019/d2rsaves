param([Parameter(Mandatory)][string]$SavePath)
. "$PSScriptRoot/common.ps1"
$raw=[IO.File]::ReadAllBytes($SavePath);$v=[IceEdit]::Read($SavePath)
Require ($v.Character.Preview.Name -eq 'BlizzSorc' -and $v.Version -eq 105 -and $v.Character.Level -eq 99 -and $v.Stats.GetStat(12) -eq 99) 'Wrong character/version/level'
Require ([Convert]::ToHexString($raw[0..3]) -eq '55AA55AA' -and [BitConverter]::ToUInt32($raw,8) -eq $raw.Length -and [BitConverter]::ToUInt32($raw,12) -eq [IceEdit]::Sum($raw)) 'Header/length/checksum'
Require (Same ([IceEdit]::Bytes($v)) $raw) 'Roundtrip differs'
Require ((($v.Skills.SkillLevels|Measure-Object -Sum).Sum+$v.Stats.GetStat(5)) -eq 110) 'Skill budget'
foreach($page in @('Inventory','Stash','Cube')){[void](Grid $v $page)}
$res=Resistance $v;$sw=Resistance $v -Switch
Require (($res -join ',') -eq '80,115,79,68' -and ($sw -join ',') -eq '40,75,79,68') 'Recalculate changed resistances'
$inv=@($v.Items|Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Inventory'})
$cold=@($inv|Where-Object {$_.ItemCodeString -eq 'cm1' -and (Value $_ 43) -eq 11});$poison=@($inv|Where-Object {$_.ItemCodeString -eq 'cm1' -and (Value $_ 45) -eq 11})
Require ($cold.Count -eq 4 -and $poison.Count -eq 3 -and @($cold+$poison|Where-Object {(Value $_ 7) -ne 5120}).Count -eq 0) 'Charms changed'
$skillers=@($inv|Where-Object {$_.ItemCodeString -eq 'cm3' -and (Value $_ 188 10) -eq 1});Require ($skillers.Count -eq 6) 'Cold skillers changed'
$mi=@($v.MercItems.Items|Where-Object ItemCodeString -eq '7wc')[0];$mh=@($v.MercItems.Items|Where-Object ItemCodeString -eq 'uh9')[0];$ma=@($v.MercItems.Items|Where-Object ItemCodeString -eq 'utp')[0]
Require ($v.MercItems.Items.Count -eq 3 -and $mi.RunewordId -eq 20568 -and ($mi.Sockets.ItemCodeString -join ',') -eq 'r08,r03,r07,r12' -and (Value $mi 151 120 -RW) -eq 17 -and (Value $mi 17 -RW) -eq 260 -and (Value $mi 119 -RW) -eq 250 -and (Value $mi 97 9 -RW) -eq 6) 'Insight'
Require ($mh.RunewordId -eq 27367 -and ($mh.Sockets.ItemCodeString -join ',') -eq 'r13,r16,r07' -and (Value $mh 151 109 -RW) -eq 1 -and (Value $mh 16 -RW) -eq 100) 'Cure'
Require ($ma.RunewordId -eq 20520 -and (Value $ma 39 -RW) -eq 50 -and (Value $ma 60 -RW) -eq 8 -and (Value $ma 0 -RW) -eq 20 -and ($ma.Sockets.ItemCodeString -join ',') -eq 'r14,r22,r30,r24') 'Chains of Honor'
Require ($v.Character.MercData.HasMerc -and !$v.Character.MercData.IsDead -and $v.Character.MercData.HirelingId -eq 12 -and $v.Character.MercData.Experience -eq 123603480) 'Mercenary identity/level'
$hire=Import-Csv "$PSScriptRoot/hireling.txt" -Delimiter "`t"|Where-Object {$_.Id -eq $v.Character.MercData.HirelingId -and $_.Level -eq 75}
$str=[int][math]::Floor([int]$hire.Str+23*[int]$hire.'Str/Lvl'/8);$dex=[int][math]::Floor([int]$hire.Dex+23*[int]$hire.'Dex/Lvl'/8)
Require ($str -ge 178 -and $dex -ge 130 -and $str -ge 96 -and $str -ge 93) 'Merc equip dependency'
$belt=@($v.Items|Where-Object {$_.Position.Mode -eq 'InBelt'});Require ($belt.Count -eq 16 -and @($belt|Where-Object ItemCodeString -ne 'rvl').Count -eq 0) 'Belt not full purple'
foreach($slot in 0..15){Require (@($belt|Where-Object {$_.Position.InvX -eq $slot -and $_.Position.InvY -eq 0}).Count -eq 1) 'Belt slots'}
function Tree($items){foreach($i in $items){if($null -eq $i){continue};$i;Tree $i.Sockets}}
$tree=@(Tree $v.Items)+@(Tree $v.MercItems.Items);$colossal=@($tree|Where-Object {$_.ItemCodeString -eq 'cjw' -and $_.Quality -eq 'Unique'})
Require ($colossal.Count -eq 1) 'Colossal jewel count'
$sunder=@($inv|Where-Object ItemCodeString -eq 'cs2');Require ($sunder.Count -eq 1 -and $sunder[0].QualityData.FileIndex -eq 427 -and $sunder[0].Stats.Count -eq 7) 'Renewed cold sunder type'
foreach($a in @(@(43,-70),@(335,10),@(7,16640),@(35,10),@(99,24),@(80,25),@(187,300))){Require ((Value $sunder[0] $a[0]) -eq $a[1]) 'Renewed cold sunder stats'}
$stash=@($v.Items|Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Stash'})
Require (@($stash|Where-Object {$_.ItemCodeString -eq 'cm1' -and (Value $_ 39) -eq 5 -and (Value $_ 45) -eq 5 -and (Value $_ 7) -eq 5120}).Count -eq 6) 'Old all-res charms missing'
Require (@($stash|Where-Object RunewordId -eq 20566).Count -eq 1 -and @($stash|Where-Object RunewordId -eq 20547).Count -eq 1 -and @($stash|Where-Object {$_.ItemCodeString -eq 'usk' -and $_.QualityData.FileIndex -eq 345}).Count -eq 1) 'Old merc gear missing'
$pierce=0;foreach($i in $inv+@($v.Items|Where-Object {$_.Position.Mode -eq 'Equipped' -and $_.Position.BodyLocation -notin @('RightHand','LeftHand')})){foreach($n in @(Tree @($i))){$pierce+=Value $n 335;$pierce+=Value $n 335 -RW}}
[ordered]@{Result='PASS';Character='BlizzSorc';Format=105;Bytes=$raw.Length;SHA256=(Get-FileHash $SavePath).Hash;HeaderLengthChecksumAndRoundtrip=$true;InventoryCubeStashBoundsOverlap=$true;MainRawResistance=$res;MainDisplayResistance=@(75,75,75,68);SwitchDisplayResistance=@(40,75,75,68);EquipmentColdPierce=$pierce;ColdLifeCharms=4;PoisonLifeCharms=3;ColdSkillers=6;BeltFullRejuvenation=16;ColossalJewels=$colossal.Count;MercenaryAura=$hire.Skill2;MercenaryHirelingId=$v.Character.MercData.HirelingId;MercenaryLevel=98;MercenaryAllThreeItemsWearable=$true;SkillsSpent=($v.Skills.SkillLevels|Measure-Object -Sum).Sum;Unspent=$v.Stats.GetStat(5);Gold=$v.Stats.GetStat(14);PersonalStashGold=$v.Stats.GetStat(15);OldMercGearAndAllResCharmsPreserved=$true}|ConvertTo-Json -Depth 7
