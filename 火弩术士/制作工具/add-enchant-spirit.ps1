param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$OutputPath,[string]$LibraryPath=(Join-Path $env:USERPROFILE '.nuget\packages\d2ssharp\0.0.24\lib\net10.0\D2SSharp.dll'))
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputPath){throw 'Preserve existing version; choose a new OutputPath'}
$bd=Split-Path $PSScriptRoot -Parent;$repo=Split-Path $bd -Parent;$data=Join-Path $bd '参考资料\数据表'
Add-Type -Path $LibraryPath
Add-Type -ReferencedAssemblies $LibraryPath -TypeDefinition @'
public static class EnchantSpiritEdit {
 public static D2SSharp.Model.D2Save Read(string p)=>D2SSharp.Model.D2Save.Read(System.IO.File.ReadAllBytes(p));
 public static byte[] Bytes(D2SSharp.Model.D2Save s)=>s.ToBytes();
}
'@
function Require($c,[string]$m){if(!$c){throw $m}}
function Seed {return [BitConverter]::ToUInt32([Security.Cryptography.RandomNumberGenerator]::GetBytes(4),0)}
function Reseed($i){$i.ItemSeed=Seed;foreach($child in $i.Sockets){if($null -ne $child){Reseed $child}}}
function Pos([string]$mode,[string]$page,[int]$x,[int]$y,[string]$body='None'){$p=[D2SSharp.Model.ItemPosition]::new();$p.Mode=[D2SSharp.Enums.ItemMode]::$mode;$p.StorePage=[D2SSharp.Enums.StorePage]::$page;$p.BodyLocation=[D2SSharp.Enums.BodyLocation]::$body;$p.InvX=$x;$p.InvY=$y;return $p}
function Value($i,[int]$id,[int]$layer=0,[switch]$RW){$list=if($RW){$i.RunewordStats}else{$i.Stats};$a=@($list | Where-Object {[int]$_.Id -eq $id -and $_.Layer -eq $layer});if(!$a.Count){return 0};Require ($a.Count -eq 1) 'Duplicate stat';return [long]$a[0].Value}
$statMap=@{};Import-Csv -LiteralPath (Join-Path $data 'itemstatcost.txt') -Delimiter "`t" | ForEach-Object {$statMap[$_.Stat]=$_}
function AddStat($list,[string]$name,[long]$value,[int]$layer=0){$r=$statMap[$name];Require ($null -ne $r) "Unknown stat $name";if($r.ValShift){$value=$value -shl [int]$r.ValShift};$v=[D2SSharp.Model.Stat]::new();$v.Id=[D2SSharp.Enums.StatId][int]$r.'*ID';$v.Value=$value;$v.Layer=$layer;$list.Add($v)}
$asm=[D2SSharp.Model.D2Save].Assembly;$reader=[IO.StreamReader]::new($asm.GetManifestResourceStream('D2SSharp.Data.Txt._105.misc.txt'));$misc=@($reader.ReadToEnd() | ConvertFrom-Csv -Delimiter "`t");$reader.Dispose()
$rows=@(Import-Csv -LiteralPath (Join-Path $data 'armor.txt') -Delimiter "`t")+@(Import-Csv -LiteralPath (Join-Path $data 'weapons.txt') -Delimiter "`t")+$misc
$sizes=@{};foreach($r in $rows){$sizes[$r.code]=@([int]$r.invwidth,[int]$r.invheight)}
function Grid($model,[string]$page){$g=@{};foreach($i in $model.Items | Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq $page}){$size=$sizes[$i.ItemCodeString];Require ($null -ne $size -and $size[0] -gt 0 -and $size[1] -gt 0) "Unknown size $($i.ItemCodeString)";for($x=0;$x -lt $size[0];$x++){for($y=0;$y -lt $size[1];$y++){$gx=$i.Position.InvX+$x;$gy=$i.Position.InvY+$y;$w=if($page -eq 'Cube'){3}else{10};$h=if($page -eq 'Stash'){10}else{4};Require ($gx -lt $w -and $gy -lt $h -and !$g.ContainsKey("$gx,$gy")) "Overlap/bounds $page $gx,$gy";$g["$gx,$gy"]=$i.ItemCodeString}}};return ,$g}
function Free($model,[string]$page,[int]$width,[int]$height){$g=Grid $model $page;$w=if($page -eq 'Cube'){3}else{10};$h=if($page -eq 'Stash'){10}else{4};for($y=0;$y -le $h-$height;$y++){for($x=0;$x -le $w-$width;$x++){$ok=$true;for($dx=0;$dx -lt $width;$dx++){for($dy=0;$dy -lt $height;$dy++){if($g.ContainsKey("$($x+$dx),$($y+$dy)")){$ok=$false}}};if($ok){return @($x,$y)}}};throw "No free $width x $height region in $page"}
$sourceBytes=[IO.File]::ReadAllBytes($SourcePath);$s=[EnchantSpiritEdit]::Read($SourcePath)
Require ([Convert]::ToHexString([EnchantSpiritEdit]::Bytes($s)) -eq [Convert]::ToHexString($sourceBytes)) 'Source roundtrip differs'
Require ($s.Version -eq 105 -and $s.Character.Class -eq 'Warlock' -and $s.Character.Preview.Name -eq 'FireHexBow') 'Unexpected source character'
$oldShield=@($s.Items | Where-Object {$_.Position.Mode -eq 'Equipped' -and $_.Position.BodyLocation -eq 'LeftHand'})
Require ($oldShield.Count -eq 1 -and $oldShield[0].ItemCodeString -eq 'xsh') 'Expected current Lidless Wall'
$oldShield=$oldShield[0];$oldPosition=$oldShield.Position
$spiritReference=Join-Path $repo '新星电法\制作版本\v1\NovaPerfect.d2s'
$referenceSave=[EnchantSpiritEdit]::Read($spiritReference);$spirit=@($referenceSave.Items | Where-Object {$_.ItemCodeString -eq 'uit' -and $_.RunewordId -eq 20635})
Require ($spirit.Count -eq 1) 'Verified Spirit reference missing';$spirit=$spirit[0]
Require (($spirit.Sockets.ItemCodeString -join ',') -eq 'r07,r10,r09,r11' -and (Value $spirit 105 -RW) -eq 35 -and (Value $spirit 9 -RW) -eq 28672 -and (Value $spirit 147 -RW) -eq 8) 'Spirit donor is not perfect'
Reseed $spirit;$spirit.ItemLevel=99;$spirit.Flags=$spirit.Flags -bor [D2SSharp.Enums.ItemFlags]::Ethereal
$spirit.Defense=[int][math]::Floor(149*1.5);$spirit.MaxDurability=44;$spirit.Durability=44
$spirit.Position=Pos 'Equipped' 'Null' $oldPosition.InvX $oldPosition.InvY 'LeftHand'
$size=$sizes[$oldShield.ItemCodeString];$slot=Free $s 'Stash' $size[0] $size[1];$oldShield.Position=Pos 'Stored' 'Stash' $slot[0] $slot[1]
$s.Items.Add($spirit)
$skills=Import-Csv -LiteralPath (Join-Path $data 'skills.txt') -Delimiter "`t";$enchant=@($skills | Where-Object skill -eq 'Enchant');Require ($enchant.Count -eq 1) 'Ambiguous Enchant skill'
$club=[D2SSharp.Model.Item]::new();$club.ItemCodeString='7sp';$club.Version=101;$club.ItemSeed=Seed;$club.ItemLevel=99;$club.Flags=[D2SSharp.Enums.ItemFlags]::Identified -bor [D2SSharp.Enums.ItemFlags]::JustSaved
$club.Quality=[D2SSharp.Enums.ItemQuality]::Unique;$club.QualityData=[D2SSharp.Model.SetUniqueQualityData]::new();$club.QualityData.SetUniqueFileIndex=296;$club.MaxDurability=65;$club.Durability=65
AddStat $club.Stats 'item_maxdamage_percent' 230;AddStat $club.Stats 'item_mindamage_percent' 230
AddStat $club.Stats 'firemindam' 222;AddStat $club.Stats 'firemaxdam' 333;AddStat $club.Stats 'lifedrainmindam' 13
AddStat $club.Stats 'item_charged_skill' 5140 (([int]$enchant[0].'*Id' -shl 6) -bor 23)
AddStat $club.Stats 'item_replenish_durability' 5;AddStat $club.Stats 'item_demondamage_percent' 123;AddStat $club.Stats 'fireresist' 20
$slot=Free $s 'Cube' 1 3;$club.Position=Pos 'Stored' 'Cube' $slot[0] $slot[1];$s.Items.Add($club)
# Count only currently equipped strength and active backpack charms. Spirit gives no strength.
$equipmentStrength=0
foreach($i in $s.Items){$active=$i.Position.Mode -eq 'Equipped' -or ($i.Position.Mode -eq 'Stored' -and $i.Position.StorePage -eq 'Inventory' -and $i.ItemCodeString -in @('cm1','cm2','cm3','cs2'));if($active){$equipmentStrength+=Value $i 0;$equipmentStrength+=Value $i 0 -RW;$equipmentStrength+=[int][math]::Floor((Value $i 220 -RW)*$s.Character.Level/8)}}
$oldStats=@{};foreach($id in @(0,3,6,7,10,11)){$oldStats[$id]=$s.Stats.GetStat([D2SSharp.Enums.StatId]$id)}
$requiredBase=[math]::Max(15,146-$equipmentStrength);$transfer=[long]$requiredBase-$oldStats[0]
Require ($requiredBase -eq 17 -and $transfer -eq 2 -and $oldStats[3]-$transfer -ge 25) 'Source strength differs; recalculate stat allocation before editing'
$s.Stats.SetStat(0,$requiredBase);$s.Stats.SetStat(3,$oldStats[3]-$transfer)
foreach($id in @(6,7)){$s.Stats.SetStat([D2SSharp.Enums.StatId]$id,[math]::Max(256,$oldStats[$id]-$transfer*3*256))}
foreach($id in @(10,11)){$s.Stats.SetStat([D2SSharp.Enums.StatId]$id,[math]::Max(0,$oldStats[$id]-$transfer*256))}
$belt=@($s.Items | Where-Object {$_.Position.Mode -eq 'InBelt'});Require (@($belt | Where-Object ItemCodeString -ne 'rvl').Count -eq 0) 'Inspect non-purple belt potions first'
$addedSlots=@(0..15 | Where-Object {$_ -notin @($belt.Position.InvX)})
foreach($slot in $addedSlots){$p=[D2SSharp.Model.Item]::new();$p.ItemCodeString='rvl';$p.Version=101;$p.Flags=[D2SSharp.Enums.ItemFlags]::Identified -bor [D2SSharp.Enums.ItemFlags]::CompactSave -bor [D2SSharp.Enums.ItemFlags]::JustSaved;$p.Position=Pos 'InBelt' 'Null' $slot 0;$s.Items.Add($p)}
foreach($page in @('Inventory','Stash','Cube')){[void](Grid $s $page)}
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
[IO.File]::WriteAllBytes($OutputPath,[EnchantSpiritEdit]::Bytes($s))
$check=[EnchantSpiritEdit]::Read($OutputPath);Require ([Convert]::ToHexString([EnchantSpiritEdit]::Bytes($check)) -eq [Convert]::ToHexString([IO.File]::ReadAllBytes($OutputPath))) 'Output roundtrip differs'
# Undo every requested modification and require exact reproduction of the source snapshot.
foreach($id in @(0,3,6,7,10,11)){$check.Stats.SetStat([D2SSharp.Enums.StatId]$id,$oldStats[$id])}
foreach($i in @($check.Items | Where-Object {$_.ItemSeed -eq $spirit.ItemSeed -or $_.ItemSeed -eq $club.ItemSeed})){[void]$check.Items.Remove($i)}
foreach($p in @($check.Items | Where-Object {$_.Position.Mode -eq 'InBelt' -and $_.Position.InvX -in $addedSlots})){[void]$check.Items.Remove($p)}
$restored=@($check.Items | Where-Object ItemSeed -eq $oldShield.ItemSeed)[0];$restored.Position=$oldPosition
Require ([Convert]::ToHexString([EnchantSpiritEdit]::Bytes($check)) -eq [Convert]::ToHexString($sourceBytes)) 'Unrelated changes detected'
$r=[ordered]@{Character='FireHexBow';Level=99;Format=105;SourceSHA256=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash;File=(Split-Path $OutputPath -Leaf);Bytes=(Get-Item -LiteralPath $OutputPath).Length;SHA256=(Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash
 Changes=[ordered]@{Spirit=[ordered]@{Seed=$spirit.ItemSeed;Base='Ethereal superior Monarch';RunewordId=20635;StrengthRequirement=146;FCR=35;Mana=112;MagicAbsorb=8;Reference='新星电法/制作版本/v1/NovaPerfect.d2s';ReferenceSHA256=(Get-FileHash -LiteralPath $spiritReference -Algorithm SHA256).Hash};OldLidless=[ordered]@{Seed=$oldShield.ItemSeed;RetainedIn='Personal stash';X=$oldShield.Position.InvX;Y=$oldShield.Position.InvY};DemonLimb=[ordered]@{Seed=$club.ItemSeed;Code='7sp';UniqueIndex=296;EnchantSkillId=[int]$enchant[0].'*Id';EnchantLevel=23;Charges='20/20';Location='Carried cube';X=$club.Position.InvX;Y=$club.Position.InvY;NonEthereal=$true};Attributes=[ordered]@{OldBaseStrength=$oldStats[0];NewBaseStrength=$requiredBase;EquipmentStrength=$equipmentStrength;FinalStrength=146;OldVitality=$oldStats[3];NewVitality=$oldStats[3]-$transfer;TransferredPoints=$transfer;BaseLifeDecrease=6;BaseStaminaDecrease=2};Belt=[ordered]@{Before=$belt.Count;After=16;Added=$addedSlots.Count}}
 Validation=[ordered]@{RoundtripIdentical=$true;UndoAllChangesReproducesSourceExactly=$true;InventoryStashCubeBoundsAndOverlap=$true;SkillsAndUserInventoryArrangementPreserved=$true;CopiedToChineseGameFolder=$false;InGameTest='New switch shield and Enchant charges pending user test'}
 UserTest=[ordered]@{PlayerCount=8;Damage='Sufficient';Weakness='Low resistances; easily killed by packs of Gloams';FullBuildApproved=$false}
 Preserved=[ordered]@{SkillsSpent=($s.Skills.SkillLevels | Measure-Object -Sum).Sum;UnspentSkills=$s.Stats.GetStat(5);OriginalItemSeeds=$true;CurrentHotkeysAndProgress=$true}}
$r | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path (Split-Path $OutputPath -Parent) '校验清单.json') -Encoding utf8
$r | ConvertTo-Json -Depth 10
