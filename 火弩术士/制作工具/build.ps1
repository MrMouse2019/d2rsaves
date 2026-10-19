param(
 [string]$LibraryPath=(Join-Path $env:USERPROFILE '.nuget\packages\d2ssharp\0.0.24\lib\net10.0\D2SSharp.dll'),
 [string]$OutputPath
)
$ErrorActionPreference='Stop'
$bdRoot=Split-Path $PSScriptRoot -Parent
$repoRoot=Split-Path $bdRoot -Parent
$dataRoot=Join-Path $bdRoot '参考资料\数据表'
$sourcePath=Join-Path $bdRoot '参考资料\格式与通用装备供体.d2s'
$outPath=if($OutputPath){$OutputPath}else{Join-Path $bdRoot '制作版本\v1\FireHexBow.d2s'}
if(Test-Path -LiteralPath $outPath){throw 'Output already exists. Preserve that version and supply a new -OutputPath.'}
Add-Type -Path $LibraryPath
Add-Type -ReferencedAssemblies $LibraryPath -TypeDefinition @'
using System;
using System.IO;
using D2SSharp.Model;
public static class BowBridge {
 public static D2Save Load(string p) => D2Save.Read(File.ReadAllBytes(p));
 public static byte[] Bytes(D2Save s) => s.ToBytes();
}
'@
function Require($condition,[string]$message) {if(!$condition){throw $message}}
function Table([string]$name) {return @(Import-Csv -LiteralPath (Join-Path $dataRoot $name) -Delimiter "`t")}
$statRows=Table 'itemstatcost.txt'; $propRows=Table 'properties.txt'
$uniqueRows=Table 'uniqueitems.txt'; $setRows=Table 'setitems.txt'
$skillRows=Table 'skills.txt'; $prefixRows=Table 'magicprefix.txt'; $suffixRows=Table 'magicsuffix.txt'
$armorRows=Table 'armor.txt'; $weaponRows=Table 'weapons.txt'
$asm=[D2SSharp.Model.D2Save].Assembly
$reader=[IO.StreamReader]::new($asm.GetManifestResourceStream('D2SSharp.Data.Txt._105.misc.txt'))
$miscRows=@($reader.ReadToEnd() | ConvertFrom-Csv -Delimiter "`t");$reader.Dispose()
$statMap=@{};foreach($r in $statRows){$statMap[$r.Stat]=$r}
$propMap=@{};foreach($r in $propRows){$propMap[$r.code]=$r}
function NewSeed {return [BitConverter]::ToUInt32([Security.Cryptography.RandomNumberGenerator]::GetBytes(4),0)}
function AddStat($list,[string]$name,[long]$value,[int]$layer=0) {
 $row=$statMap[$name];Require ($null -ne $row) "Unknown stat $name"
 if($row.ValShift){$value=$value -shl [int]$row.ValShift}
 $id=[int]$row.'*ID'
 $existing=@($list | Where-Object {[int]$_.Id -eq $id -and $_.Layer -eq $layer})
 if($existing.Count){$existing[0].Value+=$value;return}
 $s=[D2SSharp.Model.Stat]::new();$s.Id=[D2SSharp.Enums.StatId]$id;$s.Layer=$layer;$s.Value=$value;$list.Add($s)
}
function SkillId([string]$value) {
 $n=0;if([int]::TryParse($value,[ref]$n)){return $n}
 $r=@($skillRows | Where-Object skill -eq $value);Require ($r.Count -eq 1) "Unknown skill $value";return [int]$r[0].'*Id'
}
function Property($list,[string]$code,[string]$param,[long]$min,[long]$max) {
 if(!$code){return}
 $r=$propMap[$code];Require ($null -ne $r) "Unknown property $code"
 if($code -eq 'dmg%'){AddStat $list 'item_maxdamage_percent' $max;AddStat $list 'item_mindamage_percent' $max;return}
 if($code -eq 'dmg-max'){AddStat $list 'maxdamage' $max;return}
 if($code -eq 'randclassskill'){AddStat $list 'item_addclassskills' 3 7;return}
 if($code -eq 'charged'){AddStat $list $r.stat1 (($min -shl 8) -bor $min) (((SkillId $param) -shl 6) -bor $max);return}
 for($i=1;$i -le 7;$i++) {
  $fn=[int]$r."func$i";if(!$fn){continue};$st=$r."stat$i";$v=$max;$layer=0
  switch($fn) {
   1 {};2 {};3 {};8 {}
   10 {$p=[int]$param;$layer=([math]::Floor($p/3)*8)+($p%3)}
   11 {$layer=((SkillId $param) -shl 6) -bor $max;$v=$min}
   15 {$v=$min}
   16 {$v=$max}
   17 {$v=if($param){[long]$param}else{$max}}
   21 {$layer=[int]$r."val$i"}
   22 {$layer=SkillId $param}
   default {throw "Unsupported property function $code/$fn"}
  }
  AddStat $list $st $v $layer
 }
}
function Place($item,[string]$mode,[string]$page,[int]$x,[int]$y,[string]$body='None') {
 $item.Position=[D2SSharp.Model.ItemPosition]::new()
 $item.Position.Mode=[D2SSharp.Enums.ItemMode]::$mode;$item.Position.StorePage=[D2SSharp.Enums.StorePage]::$page
 $item.Position.BodyLocation=[D2SSharp.Enums.BodyLocation]::$body;$item.Position.InvX=$x;$item.Position.InvY=$y
}
function BaseItem([string]$code,[string]$quality='Normal') {
 $item=[D2SSharp.Model.Item]::new();$item.ItemCodeString=$code;$item.ItemSeed=NewSeed;$item.ItemLevel=99;$item.Version=101
 $item.Flags=[D2SSharp.Enums.ItemFlags]::Identified -bor [D2SSharp.Enums.ItemFlags]::JustSaved
 $item.Quality=[D2SSharp.Enums.ItemQuality]::$quality
 $misc=@($miscRows | Where-Object code -eq $code)
 if($misc.Count -and $misc[0].compactsave -eq '1'){$item.Flags=$item.Flags -bor [D2SSharp.Enums.ItemFlags]::CompactSave}
 $base=@($armorRows | Where-Object code -eq $code)
 if($base.Count){$item.Defense=[int]$base[0].maxac;$item.MaxDurability=[int]$base[0].durability;$item.Durability=$item.MaxDurability}
 else {$base=@($weaponRows | Where-Object code -eq $code);if($base.Count){$item.MaxDurability=[int]$base[0].durability;$item.Durability=$item.MaxDurability}}
 return $item
}
function UniqueItem([string]$name) {
 $r=@($uniqueRows | Where-Object index -eq $name);Require ($r.Count -eq 1) "Unique missing $name";$r=$r[0]
 $item=BaseItem $r.code 'Unique';$item.QualityData=[D2SSharp.Model.SetUniqueQualityData]::new();$item.QualityData.SetUniqueFileIndex=[int]$r.'*ID'
 if([int]$r.lvl -gt 99){$item.ItemLevel=[int]$r.lvl}
 for($i=1;$i -le 12;$i++){Property $item.Stats $r."prop$i" $r."par$i" ([long]$r."min$i") ([long]$r."max$i")}
 if($null -ne $item.Defense -and @($item.Stats | Where-Object {[int]$_.Id -eq 16}).Count){$item.Defense++}
 return $item
}
function Equip($save,$item,[string]$body) {Place $item 'Equipped' 'Null' 0 0 $body;$save.Items.Add($item)}
function Store($save,$item,[int]$x,[int]$y,[string]$page='Inventory') {Place $item 'Stored' $page $x $y;$save.Items.Add($item)}
function Socket($parent,$jewel) {$parent.Flags=$parent.Flags -bor [D2SSharp.Enums.ItemFlags]::Socketed;Place $jewel 'Socketed' 'Null' 0 0;$parent.Sockets.Add($jewel)}
function CloneItem([string]$code,[switch]$Merc) {
 $s=[BowBridge]::Load($sourcePath);$list=if($Merc){$s.MercItems.Items}else{$s.Items}
 $match=@($list | Where-Object ItemCodeString -eq $code);Require ($match.Count -ge 1 -and ($match.Count -eq 1 -or $code -eq 'rvl')) "Donor item ambiguous $code"
 $item=$match[0];ReSeed $item;return $item
}
function ReSeed($item) {$item.ItemSeed=NewSeed;foreach($socket in $item.Sockets){if($null -ne $socket){ReSeed $socket}}}
function MagicCharm([string]$code,[int]$prefix,[int]$suffix) {
 $item=BaseItem $code 'Magic';$item.QualityData=[D2SSharp.Model.MagicQualityData]::new();$item.QualityData.PrefixId=$prefix;$item.QualityData.SuffixId=$suffix
 foreach($r in @($prefixRows[$prefix],$suffixRows[$suffix])) {for($i=1;$i -le 3;$i++){Property $item.Stats $r."mod${i}code" $r."mod${i}param" ([long]$r."mod${i}min") ([long]$r."mod${i}max")}}
 return $item
}
function RareJewelry([string]$code,[int[]]$prefixes,[int[]]$suffixes,[switch]$Craft) {
 $quality=if($Craft){'Craft'}else{'Rare'};$item=BaseItem $code $quality
 $q=[D2SSharp.Model.RareCraftQualityData]::new();$q.RarePrefixId=197;$q.RareSuffixId=133
 for($i=0;$i -lt $prefixes.Count;$i++){$q.Prefixes[$i]=$prefixes[$i]};for($i=0;$i -lt $suffixes.Count;$i++){$q.Suffixes[$i]=$suffixes[$i]};$item.QualityData=$q
 foreach($idx in $prefixes){$r=$prefixRows[$idx];Property $item.Stats $r.mod1code $r.mod1param ([long]$r.mod1min) ([long]$r.mod1max)}
 foreach($idx in $suffixes){$r=$suffixRows[$idx];Property $item.Stats $r.mod1code $r.mod1param ([long]$r.mod1min) ([long]$r.mod1max)}
 return $item
}
# Use the verified archive only for the v105 header layout and reusable equipment.
# Rebuild class, name, attributes, skills, inventory, preview and summons explicitly.
Require (Test-Path -LiteralPath $sourcePath) 'Missing frozen donor snapshot'
$sourceManifest=Get-Content -LiteralPath (Join-Path $bdRoot '参考资料\供体快照校验.json') -Raw | ConvertFrom-Json
Require ((Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash -eq $sourceManifest.SHA256) 'Frozen donor hash changed'
$save=[BowBridge]::Load($sourcePath)
Require ([Convert]::ToHexString([BowBridge]::Bytes($save)) -eq [Convert]::ToHexString([IO.File]::ReadAllBytes($sourcePath))) 'Donor roundtrip differs'
$save.Character.Class=[D2SSharp.Enums.CharacterClass]::Warlock
$save.Character.Preview.Name='FireHexBow';$save.Character.Name='FireHexBow';$save.Character.Level=99;$save.Character.WeaponSwitch=0
$save.Character.CreateTime=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds();$save.Character.LastSaveTime=$save.Character.CreateTime;$save.Character.PlayTime=0
$save.Character.MapSeed=NewSeed
$save.Character.MercData=[D2SSharp.Model.MercData]::new()
$save.Character.SkillHotkeys=New-Object 'D2SSharp.Model.Skill[]' 16
for($i=0;$i -lt 16;$i++){$s=[D2SSharp.Model.Skill]::new();$s.SkillId=65535;$s.ItemIndex=65535;$save.Character.SkillHotkeys[$i]=$s}
foreach($name in @('LeftSkill','RightSkill','SwitchLeftSkill','SwitchRightSkill')){$save.Character.$name=[D2SSharp.Model.Skill]::new()}
$save.Character.RightSkill.SkillId=54;$save.Character.SwitchRightSkill.SkillId=149
$save.Corpses=[D2SSharp.Model.CorpseSection]::new();$save.Demon=[D2SSharp.Model.DemonSection]::new();$save.IronGolem=[D2SSharp.Model.IronGolemSection]::new()
$save.TrailingData=[byte[]]@();$save.Items.Clear();$save.MercItems.Items.Clear()
$save.Stats.Clear()
# 490 level points + 15 quest points; only 5 additional dexterity is needed.
$values=@(15,20,25,525,0,9,(1811*256),(1811*256),(167*256),(167*256),(684*256),(684*256),99,3520485254,0,2500000)
for($i=0;$i -lt 16;$i++){$save.Stats.SetStat([D2SSharp.Enums.StatId]$i,[long]$values[$i])}
$save.Skills.CharacterClass=[D2SSharp.Enums.CharacterClass]::Warlock;$save.Skills.SkillLevels=New-Object byte[] 30
$points=@{373=1;374=10;376=1;377=1;378=1;381=20;383=1;384=1;385=20;387=1;388=1;389=20;390=1;391=1;392=20;393=1}
foreach($pair in $points.GetEnumerator()){$save.Skills.SkillLevels[[int]$pair.Key-373]=[byte]$pair.Value}
Require (($save.Skills.SkillLevels | Measure-Object -Sum).Sum -eq 101) 'Skill total differs'
# Main equipment matches the supplied screenshot. The sole colossal jewel is magic.
$head=UniqueItem 'Unique Warlock Helm';Socket $head (UniqueItem "Guardian's Light");Equip $save $head 'Head'
$bow=UniqueItem 'Demon Machine'
$facet=CloneItem 'uea';$facet=$facet.Sockets[0];ReSeed $facet;$facet.Stats.Clear();$facet.Sockets.Clear();$facet.QualityData.SetUniqueFileIndex=394
Property $facet.Stats 'extra-fire' '' 5 5;Property $facet.Stats 'pierce-fire' '' 5 5;Property $facet.Stats 'dmg-fire' '' 17 45
Property $facet.Stats 'death-skill' 'Meteor' 100 31
Socket $bow $facet;Equip $save $bow 'RightArm'
$bolts=BaseItem 'cqv';$bolts.Quantity=500;Equip $save $bolts 'LeftArm'
$gloves=UniqueItem 'Magefist';Equip $save $gloves 'Gloves'
$belt=UniqueItem 'Razortail';Equip $save $belt 'Belt'
$bootsRow=@($setRows | Where-Object index -eq "Horazon's Legacy")[0]
$boots=BaseItem $bootsRow.item 'Set';$boots.QualityData=[D2SSharp.Model.SetUniqueQualityData]::new();$boots.QualityData.SetUniqueFileIndex=[int]$bootsRow.'*ID';$boots.SetItemMask=1
for($i=1;$i -le 9;$i++){Property $boots.Stats $bootsRow."prop$i" $bootsRow."par$i" ([long]$bootsRow."min$i") ([long]$bootsRow."max$i")}
$bonus=[Collections.Generic.List[D2SSharp.Model.Stat]]::new();Property $bonus 'move2' '' 10 10;$boots.SetBonusStats.Add($bonus);Equip $save $boots 'Feet'
$sling=UniqueItem 'Sling';Equip $save $sling 'RightRing'
$ring=RareJewelry 'rin' @(312,334,372) @(174,747,331);Equip $save $ring 'LeftRing'
$amu=RareJewelry 'amu' @(713,331) @(174,318) -Craft
Property $amu.Stats 'cast1' '' 10 10;Property $amu.Stats 'mana' '' 20 20;Property $amu.Stats 'regen-mana' '' 10 10;Equip $save $amu 'Neck'
# Enigma: 15% superior Mage Plate. Rune contributions remain in socket children.
$enigma=BaseItem 'xtp' 'Superior';$enigma.QualityData=[D2SSharp.Model.SuperiorQualityData]::new();$enigma.QualityData.SuperiorFileIndex=0;$enigma.Defense++
Property $enigma.Stats 'ac%' '' 15 15
$enigma.RunewordId=20539;$enigma.Flags=$enigma.Flags -bor [D2SSharp.Enums.ItemFlags]::Runeword;$enigma.RunewordStats=[Collections.Generic.List[D2SSharp.Model.Stat]]::new()
foreach($code in @('r31','r06','r30')){Socket $enigma (BaseItem $code)}
$rwRows=Table 'runes.txt';$rw=@($rwRows | Where-Object {$_.'*Rune Name' -eq 'Enigma'})[0]
for($i=1;$i -le 7;$i++){Property $enigma.RunewordStats $rw."T1Code$i" $rw."T1Param$i" ([long]$rw."T1Min$i") ([long]$rw."T1Max$i")}
Equip $save $enigma 'Torso'
Equip $save (CloneItem 'crs') 'RightHand';Equip $save (CloneItem 'xsh') 'LeftHand'
# Six legal +1 Eldritch / 45 life skillers. Correct tab encoding is class*8+tab.
for($i=0;$i -lt 6;$i++){Store $save (MagicCharm 'cm3' 701 339) $i 0}
$sunder=BaseItem 'cs2' 'Unique';$sunder.QualityData=[D2SSharp.Model.SetUniqueQualityData]::new();$sunder.QualityData.SetUniqueFileIndex=433
foreach($a in @(@('pierce-immunity-fire',300),@('res-fire',-70),@('pierce-fire',10),@('mag%',25),@('hp',65),@('balance1',24),@('red-dmg',10))){Property $sunder.Stats $a[0] '' $a[1] $a[1]}
Store $save $sunder 6 0
Store $save (UniqueItem 'Hellfire Torch') 7 0;Store $save (UniqueItem 'Annihilus') 7 2
$cube=CloneItem 'box';Store $save $cube 8 0
foreach($a in @(@('tbk',8),@('ibk',9))){$book=CloneItem $a[0];$book.Quantity=20;Store $save $book $a[1] 2}
for($i=0;$i -lt 3;$i++){Store $save (MagicCharm 'cm1' 322 267) $i 3}
for($i=3;$i -lt 7;$i++){Store $save (MagicCharm 'cm1' 369 349) $i 3}
for($i=0;$i -lt 16;$i++){$p=CloneItem 'rvl';Place $p 'InBelt' 'Null' $i 0;$save.Items.Add($p)}
# Two spare full bolt stacks fit inside the cube, which remains available for loot.
for($i=0;$i -lt 2;$i++){$p=BaseItem 'cqv';$p.Quantity=500;Store $save $p $i 0 'Cube'}
$merc=$save.Character.MercData;$merc.Flags=0;$merc.Seed=NewSeed;$merc.NameIndex=0;$merc.HirelingId=6;$merc.Experience=[uint32](110*98*98*99)
$insight=CloneItem '7wc' -Merc;$cure=CloneItem 'uh9' -Merc
foreach($a in @(@($insight,'RightArm'),@($cure,'Head'))){Place $a[0] 'Equipped' 'Null' 0 0 $a[1];$save.MercItems.Items.Add($a[0])}
# Fortitude in an ethereal 15% superior Archon Plate, 30 all resist / 1.5 life per level.
$fort=BaseItem 'utp' 'Superior';$fort.QualityData=[D2SSharp.Model.SuperiorQualityData]::new();$fort.QualityData.SuperiorFileIndex=0;$fort.Flags=$fort.Flags -bor [D2SSharp.Enums.ItemFlags]::Ethereal -bor [D2SSharp.Enums.ItemFlags]::Runeword
$fort.Defense=[int][math]::Floor(($fort.Defense+1)*1.5);$fort.MaxDurability=[int][math]::Floor($fort.MaxDurability/2)+1;$fort.Durability=$fort.MaxDurability
Property $fort.Stats 'ac%' '' 15 15;$fort.RunewordId=20547;$fort.RunewordStats=[Collections.Generic.List[D2SSharp.Model.Stat]]::new()
foreach($code in @('r01','r12','r14','r28')){Socket $fort (BaseItem $code)}
$rw=@($rwRows | Where-Object {$_.'*Rune Name' -eq 'Fortitude'})[0]
for($i=1;$i -le 7;$i++){Property $fort.RunewordStats $rw."T1Code$i" $rw."T1Param$i" ([long]$rw."T1Min$i") ([long]$rw."T1Max$i")}
Place $fort 'Equipped' 'Null' 0 0 'Torso';$save.MercItems.Items.Add($fort)
# Rebuild visible selection-screen equipment, rather than keeping the sorceress preview.
foreach($a in @(@('Head',$head),@('Torso',$enigma),@('LeftHand',$bow),@('RightHand',$bolts))){$p=[D2SSharp.Model.PreviewItem]::new();$p.Code=$a[1].ItemCode;$p.Quality=$a[1].Quality;$p.FileIndex=if($a[1].QualityData.FileIndex){$a[1].QualityData.FileIndex}else{0};$p.Transform=255;$save.Character.Preview.($a[0])=$p}
$save.Character.AppearanceGraphics=[byte[]](255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255)
$save.Character.AppearanceTints=[byte[]](255,255,255,255,255,255,255,255,255,255,255,255,255,255,255,255)
New-Item -ItemType Directory -Path (Split-Path $outPath -Parent) -Force | Out-Null
[IO.File]::WriteAllBytes($outPath,[BowBridge]::Bytes($save))
$check=[BowBridge]::Load($outPath)
Require ([Convert]::ToHexString([BowBridge]::Bytes($check)) -eq [Convert]::ToHexString([IO.File]::ReadAllBytes($outPath))) 'Final roundtrip differs'
[pscustomobject]@{Character=$check.Character.Preview.Name;Class=$check.Character.Class.ToString();Version=$check.Version;Items=$check.Items.Count;MercItems=$check.MercItems.Items.Count;Skills=($check.Skills.SkillLevels | Measure-Object -Sum).Sum;Output=$outPath;SHA256=(Get-FileHash -LiteralPath $outPath -Algorithm SHA256).Hash} | ConvertTo-Json
