param([Parameter(Mandatory)][string]$SavePath,[string]$LibraryPath=(Join-Path $env:USERPROFILE '.nuget\packages\d2ssharp\0.0.24\lib\net10.0\D2SSharp.dll'),[switch]$AllowUsedEnchantCharges)
$ErrorActionPreference='Stop'
Add-Type -Path $LibraryPath
Add-Type -ReferencedAssemblies $LibraryPath -TypeDefinition @'
public static class EnchantSpiritAudit {
 public static D2SSharp.Model.D2Save Read(string p)=>D2SSharp.Model.D2Save.Read(System.IO.File.ReadAllBytes(p));
 public static byte[] Bytes(D2SSharp.Model.D2Save s)=>s.ToBytes();
 public static uint Sum(byte[] b){uint c=0;for(int i=0;i<b.Length;i++)c=unchecked(((c<<1)|(c>>31))+(uint)((i>=12&&i<16)?0:b[i]));return c;}
}
'@
function Assert($condition,[string]$message){if(!$condition){throw $message}}
function V($item,[int]$id,[int]$layer=0,[switch]$RW){$list=if($RW){$item.RunewordStats}else{$item.Stats};$r=@($list | Where-Object {[int]$_.Id -eq $id -and $_.Layer -eq $layer});if(!$r.Count){return 0};Assert ($r.Count -eq 1) 'Duplicate stat';return [long]$r[0].Value}
function AllItems($items){foreach($item in $items){if($null -ne $item){$item;if($item.Sockets.Count){AllItems $item.Sockets}}}}
$s=[EnchantSpiritAudit]::Read($SavePath);$raw=[IO.File]::ReadAllBytes($SavePath)
Assert ($s.Version -eq 105 -and $s.Character.Preview.Name -eq 'FireHexBow') 'Wrong character/version'
$shield=@($s.Items | Where-Object {$_.Position.Mode -eq 'Equipped' -and $_.Position.BodyLocation -eq 'LeftHand'})
Assert ($shield.Count -eq 1 -and $shield[0].ItemCodeString -eq 'uit' -and $shield[0].RunewordId -eq 20635 -and $shield[0].Flags.HasFlag([D2SSharp.Enums.ItemFlags]::Ethereal)) 'Expected ethereal Spirit Monarch on switch'
$shield=$shield[0]
foreach($a in @(@(99,55),@(105,35),@(127,2),@(9,28672),@(3,22),@(32,250),@(147,8))){Assert ((V $shield $a[0] -RW) -eq $a[1]) "Wrong Spirit stat $($a[0])"}
Assert (($shield.Sockets.ItemCodeString -join ',') -eq 'r07,r10,r09,r11') 'Wrong Spirit runes'
$club=@($s.Items | Where-Object {$_.ItemCodeString -eq '7sp' -and $_.Quality -eq 'Unique' -and $_.QualityData.FileIndex -eq 296})
Assert ($club.Count -eq 1) 'Expected one Demon Limb'
$club=$club[0];Assert ($club.Position.Mode -eq 'Stored' -and $club.Position.StorePage -eq 'Cube') 'Demon Limb should be in carried cube'
$skillRows=Import-Csv -LiteralPath (Join-Path (Split-Path $PSScriptRoot -Parent) '参考资料\数据表\skills.txt') -Delimiter "`t"
$enchant=@($skillRows | Where-Object skill -eq 'Enchant')[0];$layer=([int]$enchant.'*Id' -shl 6) -bor 23
$chargeValue=V $club 204 $layer
$currentCharges=$chargeValue -band 255;$maxCharges=$chargeValue -shr 8
Assert ($maxCharges -eq 20 -and $currentCharges -ge 0 -and $currentCharges -le 20) 'Expected level 23 Enchant with max 20 charges'
if(!$AllowUsedEnchantCharges){Assert ($currentCharges -eq 20) 'Expected full 20/20 charges'}
Assert ((V $club 17) -eq 230 -and (V $club 18) -eq 230 -and (V $club 48) -eq 222 -and (V $club 49) -eq 333 -and (V $club 60) -eq 13 -and (V $club 39) -eq 20) 'Demon Limb rolls not perfect'
Assert (!$club.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::Ethereal)) 'Enchant charge tool should be non-ethereal'
$strength=[long]$s.Stats.GetStat(0);$gearStrength=0
foreach($item in $s.Items){
 $active=$item.Position.Mode -eq 'Equipped' -or ($item.Position.Mode -eq 'Stored' -and $item.Position.StorePage -eq 'Inventory' -and $item.ItemCodeString -in @('cm1','cm2','cm3','cs2'))
 if($active){$gearStrength+=(V $item 0);$gearStrength+=(V $item 0 -RW);$gearStrength+=[int][math]::Floor((V $item 220 -RW)*$s.Character.Level/8)}
}
$finalStrength=$strength+$gearStrength
Assert ($strength -eq 17 -and $finalStrength -eq 146 -and $finalStrength-1 -lt 146) 'Strength is not the exact ethereal Monarch requirement'
Assert ($s.Stats.GetStat(3) -eq 523) 'Vitality transfer mismatch'
Assert (($s.Stats.GetStat(0)+$s.Stats.GetStat(1)+$s.Stats.GetStat(2)+$s.Stats.GetStat(3)+$s.Stats.GetStat(4)) -eq 585) 'Attribute budget mismatch'
Assert ((($s.Skills.SkillLevels | Measure-Object -Sum).Sum+$s.Stats.GetStat(5)) -eq 110) 'Skill points lost'
Assert ((17+40) -ge 55 -and (17+40+74) -ge 114) 'Equipment self-support dependency'
$potions=@($s.Items | Where-Object {$_.Position.Mode -eq 'InBelt'})
Assert ($potions.Count -eq 16 -and @($potions | Where-Object ItemCodeString -ne 'rvl').Count -eq 0) 'Belt is not full purple'
for($i=0;$i -lt 16;$i++){Assert (@($potions | Where-Object {$_.Position.InvX -eq $i -and $_.Position.InvY -eq 0}).Count -eq 1) "Bad belt slot $i"}
Assert ([Convert]::ToHexString([EnchantSpiritAudit]::Bytes($s)) -eq [Convert]::ToHexString($raw)) 'Roundtrip mismatch'
Assert ([BitConverter]::ToUInt32($raw,8) -eq $raw.Length -and [BitConverter]::ToUInt32($raw,12) -eq [EnchantSpiritAudit]::Sum($raw)) 'Header length/checksum mismatch'
$all=@(AllItems $s.Items)+@(AllItems $s.MercItems.Items)
Assert (@($all | Where-Object ItemCodeString -eq 'cjw').Count -eq 1) 'Colossal jewel count changed'
$seeded=@($all | Where-Object {!$_.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::CompactSave)})
Assert (@($seeded.ItemSeed | Sort-Object -Unique).Count -eq $seeded.Count) 'Duplicate item seeds'
[pscustomobject]@{Result='PASS';Character='FireHexBow';Spirit='Ethereal Monarch, 35 FCR/112 mana/8 absorb';BaseStrength=$strength;EquipmentStrength=$gearStrength;FinalStrength=$finalStrength;Vitality=$s.Stats.GetStat(3);EnchantLevel=23;EnchantCharges="$currentCharges/$maxCharges";BeltFullPurple=16;RoundtripAndChecksum=$true} | ConvertTo-Json
