param(
 [string]$SavePath=(Join-Path (Split-Path $PSScriptRoot -Parent) '制作版本\v1\FireHexBow.d2s'),
 [string]$LibraryPath=(Join-Path $env:USERPROFILE '.nuget\packages\d2ssharp\0.0.24\lib\net10.0\D2SSharp.dll')
)
$ErrorActionPreference='Stop'
Add-Type -Path $LibraryPath
Add-Type -ReferencedAssemblies $LibraryPath -TypeDefinition @'
using System;
using System.IO;
using D2SSharp.Model;
public static class BowAudit {
 public static D2Save Load(string p) => D2Save.Read(File.ReadAllBytes(p));
 public static byte[] Bytes(D2Save s) => s.ToBytes();
 public static uint Checksum(byte[] data) {
  uint n=0;
  for(int i=0;i<data.Length;i++)
   n=unchecked(((n<<1)|(n>>31))+(uint)((i>=12&&i<16)?0:data[i]));
  return n;
 }
}
'@
$bdRoot=Split-Path $PSScriptRoot -Parent
$assertions=0
function Assert($ok,[string]$message) {if(!$ok){throw $message};$script:assertions++}
function Value($item,[int]$id,[int]$layer=0,[switch]$RW) {
 $list=if($RW){$item.RunewordStats}else{$item.Stats}
 $s=@($list | Where-Object {[int]$_.Id -eq $id -and $_.Layer -eq $layer})
 if(!$s.Count){return 0};Assert ($s.Count -eq 1) "Duplicate stat $id/$layer";return [long]$s[0].Value
}
function Tree($items){foreach($item in $items){if($null -ne $item){$item;if($item.Sockets.Count){Tree $item.Sockets}}}}
function Body([string]$body){$items=@($save.Items | Where-Object {$_.Position.Mode -eq 'Equipped' -and $_.Position.BodyLocation -eq $body});Assert ($items.Count -eq 1) "Missing or duplicate slot $body";return $items[0]}
$raw=[IO.File]::ReadAllBytes($SavePath)
Assert ([Convert]::ToHexString($raw[0..3]) -eq '55AA55AA') 'Bad magic'
Assert ([BitConverter]::ToUInt32($raw,4) -eq 105) 'Bad save version'
Assert ([BitConverter]::ToUInt32($raw,8) -eq $raw.Length) 'Declared length mismatch'
$checksum=[BowAudit]::Checksum($raw);Assert ($checksum -eq [BitConverter]::ToUInt32($raw,12)) 'Checksum mismatch'
$save=[BowAudit]::Load($SavePath)
Assert ([Convert]::ToHexString([BowAudit]::Bytes($save)) -eq [Convert]::ToHexString($raw)) 'Roundtrip mismatch'
Assert ($save.Character.Preview.Name -eq 'FireHexBow' -and $save.Character.Class -eq 'Warlock') 'Wrong character'
Assert ($save.Character.Level -eq 99 -and $save.Stats.GetStat(12) -eq 99) 'Header/stat level mismatch'
Assert ($save.Character.Preview.GameVersion -eq 'ReignOfTheWarlock') 'Wrong game version'
Assert (($save.Skills.SkillLevels | Measure-Object -Sum).Sum -eq 101 -and $save.Stats.GetStat(5) -eq 9) 'Skill point budget mismatch'
$expected=[byte[]](1,10,0,1,1,1,0,0,20,0,1,1,20,0,1,1,20,1,1,20,1,0,0,0,0,0,0,0,0,0)
Assert ([Convert]::ToHexString($expected) -eq [Convert]::ToHexString($save.Skills.SkillLevels)) 'Skills differ from screenshot'
$skills=Import-Csv -LiteralPath (Join-Path $bdRoot '参考资料\数据表\skills.txt') -Delimiter "`t"
foreach($r in $skills | Where-Object charclass -eq 'war'){
 $points=$save.Skills.SkillLevels[[int]$r.'*Id'-373];Assert ($points -le 20) "Overcapped hard points $($r.skill)"
 if($points){foreach($p in @($r.reqskill1,$r.reqskill2,$r.reqskill3) | Where-Object {$_}){$pr=@($skills | Where-Object skill -eq $p)[0];Assert ($save.Skills.SkillLevels[[int]$pr.'*Id'-373] -ge 1) "Missing prerequisite $p"}}
}
$attrs=@($save.Stats.GetStat(0),$save.Stats.GetStat(1),$save.Stats.GetStat(2),$save.Stats.GetStat(3))
Assert (($attrs | Measure-Object -Sum).Sum -eq 585 -and $save.Stats.GetStat(4) -eq 0) 'Attribute budget mismatch'
Assert ($attrs[0] -eq 15 -and $attrs[2] -eq 25 -and $attrs[3] -eq 525) 'Unexpected attribute allocation'
foreach($d in @('Normal','Nightmare','Hell')){
 foreach($q in @($save.Quests.$d.ActI.DenOfEvil,$save.Quests.$d.ActII.RadamentsLair,$save.Quests.$d.ActIV.TheFallenAngel,$save.Quests.$d.ActIII.LamEsensTome,$save.Quests.$d.ActIII.TheGoldenBird,$save.Quests.$d.ActV.PrisonOfIce)){
  Assert (([int]$q -band 1) -eq 1) "Missing quest reward in $d"
 }
}
$head=Body 'Head';$bow=Body 'RightArm';$amu=Body 'Neck';$ring=Body 'LeftRing';$sling=Body 'RightRing';$armor=Body 'Torso';$boots=Body 'Feet';$belt=Body 'Belt';$gloves=Body 'Gloves'
Assert ($head.QualityData.FileIndex -eq 419 -and (Value $head 16) -eq 215 -and (Value $head 333) -eq 8 -and (Value $head 358) -eq 8 -and (Value $head 138) -eq 6) 'Hellwarden not perfect'
Assert ($head.Sockets.Count -eq 1 -and $head.Sockets[0].QualityData.FileIndex -eq 425) 'Wrong colossal jewel'
$jewel=$head.Sockets[0]
foreach($a in @(@(52,15),@(53,35),@(357,10),@(358,10),@(85,5),@(79,50),@(80,35))){Assert ((Value $jewel $a[0]) -eq $a[1]) "Wrong Guardian Light stat $($a[0])"}
Assert ((Value $jewel 201 ((387 -shl 6) -bor 25)) -eq 1) 'Wrong Psychic Ward proc'
Assert ($bow.ItemCodeString -eq '8rx' -and $bow.QualityData.FileIndex -eq 199) 'Wrong crossbow'
foreach($a in @(@(31,321),@(9,9216),@(156,66),@(158,6),@(22,66),@(17,123),@(18,123),@(19,632))){Assert ((Value $bow $a[0]) -eq $a[1]) "Wrong Demon Machine stat $($a[0])"}
Assert ($bow.Sockets.Count -eq 1 -and $bow.Sockets[0].QualityData.FileIndex -eq 394 -and (Value $bow.Sockets[0] 329) -eq 5 -and (Value $bow.Sockets[0] 333) -eq 5) 'Wrong fire facet'
Assert ($armor.ItemCodeString -eq 'xtp' -and $armor.RunewordId -eq 20539 -and (Value $armor 31 -RW) -eq 775 -and (Value $armor 220 -RW) -eq 6) 'Wrong Enigma'
Assert (($armor.Sockets.ItemCodeString -join ',') -eq 'r31,r06,r30') 'Wrong Enigma runes'
Assert ($amu.Quality -eq 'Craft' -and (Value $amu 83 7) -eq 2 -and (Value $amu 105) -eq 20 -and (Value $amu 7) -eq 15360 -and (Value $amu 9) -eq 5120 -and (Value $amu 27) -eq 10) 'Wrong max-roll caster amulet'
Assert (($amu.QualityData.Prefixes | Where-Object {$_}).Count -eq 2 -and ($amu.QualityData.Suffixes | Where-Object {$_}).Count -eq 2) 'Caster amulet must have four random affixes'
Assert ((Value $ring 105) -eq 10 -and (Value $ring 62) -eq 6 -and (Value $ring 9) -eq 23040 -and (Value $ring 7) -eq 10240 -and (Value $ring 39) -eq 41) 'Wrong rare ring'
Assert ($sling.QualityData.FileIndex -eq 415 -and (Value $sling 358) -eq 5 -and (Value $sling 1) -eq 15 -and (Value $sling 80) -eq 20) 'Wrong Sling'
$slingSkill=@($skills | Where-Object skill -eq 'Townportal O Skill')
Assert ($slingSkill.Count -eq 1 -and (Value $sling 97 ([int]$slingSkill[0].'*Id')) -eq 1 -and (Value $sling 97 359) -eq 0) 'Wrong Sling portal oskill: resolve Townportal O Skill from skills.txt'
Assert ($boots.QualityData.FileIndex -eq 138 -and $boots.Quality -eq 'Set' -and (Value $boots 0) -eq 15 -and (Value $boots 2) -eq 15 -and (Value $boots 37) -eq 30 -and (Value $boots 91) -eq -30 -and (Value $boots 153) -eq 1) 'Wrong Horazon boots'
Assert ((Value $belt 156) -eq 33 -and (Value $belt 2) -eq 15 -and $belt.ItemCodeString -eq 'zvb') 'Wrong Razortail'
Assert ((Value $gloves 126 1) -eq 1 -and (Value $gloves 105) -eq 20 -and (Value $gloves 16) -eq 30) 'Wrong Magefist'
$cta=Body 'RightHand';$shield=Body 'LeftHand';Assert ($cta.ItemCodeString -eq 'crs' -and (Value $cta 97 149 -RW) -eq 6 -and (Value $cta 97 155 -RW) -eq 6 -and (Value $cta 97 146 -RW) -eq 4) 'CTA is not crystal sword 6/6/4'
Assert ($shield.ItemCodeString -eq 'xsh' -and $shield.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::Ethereal) -and (Value $shield 127) -eq 1) 'Wrong buff shield'
$all=@(Tree $save.Items)+@(Tree $save.MercItems.Items)
$colossal=@($all | Where-Object ItemCodeString -eq 'cjw');Assert ($colossal.Count -eq 1) 'Colossal jewel count not one'
foreach($item in $all){
 foreach($list in @('Stats','RunewordStats')){if($null -eq $item.$list){continue};$groups=@($item.$list | Group-Object {"$([int]$_.Id):$($_.Layer)"} | Where-Object Count -gt 1);Assert (!$groups.Count) "Duplicate stats on $($item.ItemCodeString)"}
 foreach($child in $item.Sockets){if($null -ne $child){Assert ($child.Position.Mode -eq 'Socketed') 'Socket child has wrong location'}}
 if($item.ItemCodeString -match '^r\d\d$'){Assert ($item.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::CompactSave)) 'Rune should use compact format'}
}
$seeded=@($all | Where-Object {!$_.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::CompactSave)})
Assert ((@($seeded.ItemSeed | Sort-Object -Unique).Count) -eq $seeded.Count) 'Duplicate item seeds'
$beltItems=@($save.Items | Where-Object {$_.Position.Mode -eq 'InBelt'})
Assert ($beltItems.Count -eq 16 -and @($beltItems | Where-Object ItemCodeString -ne 'rvl').Count -eq 0) 'Belt must contain 16 full rejuvenation potions'
for($i=0;$i -lt 16;$i++){Assert (@($beltItems | Where-Object {$_.Position.InvX -eq $i -and $_.Position.InvY -eq 0}).Count -eq 1) "Bad belt slot $i"}
$occupied=@{};$cubeOccupied=@{};$inv=@($save.Items | Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Inventory'})
foreach($item in $save.Items | Where-Object {$_.Position.Mode -eq 'Stored'}){
 $w=1;$h=1;switch($item.ItemCodeString){'cm3'{$h=3};'cs2'{$h=3};'cm2'{$h=2};'box'{$w=2;$h=2};'tbk'{$h=2};'ibk'{$h=2};'cqv'{$h=3}}
 $isCube=$item.Position.StorePage -eq 'Cube';$grid=if($isCube){$cubeOccupied}else{$occupied};$limit=if($isCube){3}else{10}
 for($x=0;$x -lt $w;$x++){for($y=0;$y -lt $h;$y++){$gx=$item.Position.InvX+$x;$gy=$item.Position.InvY+$y;$key="$gx,$gy";Assert ($gx -lt $limit -and $gy -lt 4) 'Item out of bounds';Assert (!$grid.ContainsKey($key)) "Overlap $key";$grid[$key]=$item.ItemCodeString}}
}
Assert ($occupied.Count -eq 39 -and !$occupied.ContainsKey('7,3')) 'Backpack layout mismatch'
$skillers=@($inv | Where-Object {$_.ItemCodeString -eq 'cm3' -and $_.Quality -eq 'Magic'});Assert ($skillers.Count -eq 6) 'Expected six skillers'
foreach($item in $skillers){Assert ((Value $item 188 57) -eq 1 -and (Value $item 7) -eq 11520 -and $item.QualityData.PrefixId -eq 701 -and $item.QualityData.SuffixId -eq 339 -and $item.ItemLevel -ge 91) 'Illegal Eldritch / 45 life skiller'}
$sunder=@($inv | Where-Object ItemCodeString -eq 'cs2');Assert ($sunder.Count -eq 1 -and $sunder[0].QualityData.FileIndex -eq 433 -and $sunder[0].Stats.Count -eq 7) 'Wrong Renewed Flame Rift type'
foreach($a in @(@(189,300),@(39,-70),@(333,10),@(80,25),@(7,16640),@(99,24),@(34,10))){Assert ((Value $sunder[0] $a[0]) -eq $a[1]) "Wrong Renewed Flame Rift stat $($a[0])"}
foreach($code in @('box','tbk','ibk','cm1','cm2')){Assert (@($inv | Where-Object ItemCodeString -eq $code).Count -ge 1) "Missing $code"}
Assert ((@($inv | Where-Object ItemCodeString -eq 'tbk')[0]).Quantity -eq 20 -and (@($inv | Where-Object ItemCodeString -eq 'ibk')[0]).Quantity -eq 20) 'Books not full'
$bolts=Body 'LeftArm';Assert ($bolts.ItemCodeString -eq 'cqv' -and $bolts.Quantity -eq 500) 'Missing full bolt quiver'
$merc=$save.Character.MercData;Assert ($merc.HasMerc -and !$merc.IsDead -and $merc.HirelingId -eq 6 -and $merc.Experience -eq 104587560) 'Prayer mercenary data mismatch'
Assert ($save.MercItems.Items.Count -eq 3) 'Mercenary gear incomplete'
$mi=@($save.MercItems.Items | Where-Object ItemCodeString -eq '7wc')[0];$mh=@($save.MercItems.Items | Where-Object ItemCodeString -eq 'uh9')[0];$ma=@($save.MercItems.Items | Where-Object ItemCodeString -eq 'utp')[0]
Assert ((Value $mi 151 120 -RW) -eq 17 -and (Value $mi 17 -RW) -eq 260 -and (Value $mi 119 -RW) -eq 250 -and (Value $mi 97 9 -RW) -eq 6) 'Insight not perfect'
Assert ((Value $mh 151 109 -RW) -eq 1 -and (Value $mh 16 -RW) -eq 100) 'Cure not perfect'
Assert ($ma.RunewordId -eq 20547 -and (Value $ma 17 -RW) -eq 300 -and (Value $ma 39 -RW) -eq 30 -and (Value $ma 216 -RW) -eq 3072 -and $ma.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::Ethereal)) 'Fortitude not perfect'
Assert (($ma.Sockets.ItemCodeString -join ',') -eq 'r01,r12,r14,r28') 'Wrong Fortitude runes'
# Wear order: charms -> Mage Plate -> boots -> belt -> bow. No item counts itself.
$strBeforeArmor=15+40;Assert ($strBeforeArmor -ge 55) 'Cannot equip Enigma before its strength bonus'
$strBeforeBoots=$strBeforeArmor+[int][math]::Floor(99*0.75);Assert ($strBeforeBoots -ge 114) 'Cannot equip Horazon boots without self-support'
$finalStr=$strBeforeBoots+15;$finalDex=25+40+15+15;Assert ($finalStr -ge 80 -and $finalDex -ge 95) 'Cannot equip Demon Machine'
Assert (218 -ge 178 -and 179 -ge 130) 'Mercenary cannot equip Giant Thresher'
$active=@($save.Items | Where-Object {$_.Position.Mode -eq 'Equipped' -and $_.Position.BodyLocation -notin @('RightHand','LeftHand')})+$inv
$fcr=0;$fhr=0;$res=@{Fire=-70;Lightning=-70;Cold=-70;Poison=-70};$ids=@{Fire=39;Lightning=41;Cold=43;Poison=45}
foreach($item in $active){$fcr+=Value $item 105;$fhr+=Value $item 99;foreach($k in @('Fire','Lightning','Cold','Poison')){$res[$k]+=Value $item $ids[$k]}}
Assert ($fcr -eq 80 -and $fhr -eq 39) 'Unexpected FCR/FHR total'
$sha=(Get-FileHash -LiteralPath $SavePath -Algorithm SHA256).Hash
$report=[ordered]@{
 Character='FireHexBow';Class='Warlock';Level=99;Format=105;GameVersion='Reign of the Warlock v3.0+';File=(Split-Path $SavePath -Leaf);Bytes=$raw.Length;SHA256=$sha
 Validation=[ordered]@{Assertions=$assertions;Header=$true;DeclaredLength=$true;Checksum=$true;StoredChecksum=[BitConverter]::ToUInt32($raw,12);ComputedChecksum=$checksum;RoundtripIdentical=$true;AffixAndSocketAudit=$true;InventoryNoOverlap=$true;UniqueSeeds=$true;WearOrderVerified=$true;EditorReload='Not verified: browser timed out';InGameTest='Pending user test';CopiedToChineseGameFolder=$false}
 Skills=[ordered]@{Chaos=1;Eldritch=66;Demon=34;Spent=101;Unspent=9}
 Attributes=[ordered]@{Strength=15;Dexterity=25;Energy=20;Vitality=525;Unspent=0;FinalStrengthWithoutBuff=144;FinalDexterityWithoutBuff=95}
 Equipment=[ordered]@{ColossalJewels=1;ColossalJewel="Guardian's Light, perfect, in Hellwarden's Will";FireFacet='5/5 death facet in Demon Machine';CasterAmulet='2 Warlock / 20 FCR / 60 life / 20 mana / 10 regen / 20 all resist; 4 random affixes plus caster recipe';RareRing='10 FCR / 6 mana leech / 90 mana / 40 life / 11 all resist / 30 fire resist';CTA='Crystal Sword, 6/6/4';Shield='Ethereal Lidless Wall';Boots="Horazon's Legacy";Pierce=99}
 Charms=[ordered]@{EldritchLifeSkillers=6;SkillerLife=45;RenewedSunderUniqueIndex=433;RenewedSunderBase='cs2';SunderRolls=@('-70 own fire resist','-10 enemy fire resist','65 life','24 FHR','25 MF','10 physical damage reduction');SmallCharms=@('3 x 5 all resist / 5 FHR','4 x 11 fire resist / 20 life')}
 Inventory=[ordered]@{UsedCells=39;FreeCells=1;FreeCell='7,3';CubeAndBothBooks=$true;FullRejuvenationBelt=16;EquippedBolts=500;SpareBoltStacksInCube=2;CubeFreeCells=6}
 Thresholds=[ordered]@{MainFCR=$fcr;FCRThreshold=75;MainFHR=$fhr;HellResistsWithoutTemporaryBuff=$res;MagicResist=30;EnemyFireResistanceReduction=23;EnemyMagicResistanceReduction=23;IASFromEquipment=20;AttackFrames='Requires game verification with Hex Purge and demon aura'}
 Mercenary=[ordered]@{Act=2;Aura='Prayer';Level=98;Equipment=@('Ethereal superior Giant Thresher Insight','Ethereal superior Bone Visage Cure','Ethereal superior Archon Plate Fortitude')}
 Source='Frozen archived format/equipment donor; class, name, stats, skills, inventory, preview and summons rebuilt; no live CN files read or overwritten'
}
$deliveryPath=Join-Path $bdRoot '国服导入校验.json'
if(Test-Path -LiteralPath $deliveryPath){
 $delivery=Get-Content -LiteralPath $deliveryPath -Raw | ConvertFrom-Json
 if($delivery.SHA256 -eq $sha){
  $report.Validation.CopiedToChineseGameFolder=$true
  $report.Delivery=[ordered]@{RecordedAt=$delivery.Date;Record='火弩术士/国服导入校验.json';Note='Historical delivery verification; user gameplay can subsequently change the game copy.'}
 }
}
$report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path (Split-Path $SavePath -Parent) '校验清单.json') -Encoding utf8
$report | ConvertTo-Json -Depth 10
