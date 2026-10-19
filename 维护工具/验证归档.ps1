param([Parameter(Mandatory)][string]$SavePath,[Parameter(Mandatory)][string]$LibraryPath)
$ErrorActionPreference='Stop'
Add-Type -Path $LibraryPath
Add-Type -ReferencedAssemblies $LibraryPath -TypeDefinition @'
public static class FinalArchiveAudit {
 public static D2SSharp.Model.D2Save Read(string p)=>D2SSharp.Model.D2Save.Read(System.IO.File.ReadAllBytes(p));
 public static byte[] Bytes(D2SSharp.Model.D2Save s)=>s.ToBytes();
 public static uint Sum(byte[] b){uint c=0;for(int i=0;i<b.Length;i++)c=unchecked(((c<<1)|(c>>31))+(uint)((i>=12&&i<16)?0:b[i]));return c;}
}
'@
function Require($condition,[string]$message){if(!$condition){throw $message}}
function Flatten($items){foreach($item in $items){if($null -ne $item){$item;if($item.Sockets.Count){Flatten $item.Sockets}}}}
$s=[FinalArchiveAudit]::Read($SavePath);$raw=[IO.File]::ReadAllBytes($SavePath);$name=$s.Character.Preview.Name
Require ($name -in @('FireHexBow','NovaPerfect') -and $s.Character.Level -eq 99 -and $s.Version -eq 105) 'Unexpected character/version/level'
Require ([Convert]::ToHexString($raw[0..3]) -eq '55AA55AA' -and [BitConverter]::ToUInt32($raw,8) -eq $raw.Length -and [BitConverter]::ToUInt32($raw,12) -eq [FinalArchiveAudit]::Sum($raw)) 'Header/checksum mismatch'
Require ([Convert]::ToHexString([FinalArchiveAudit]::Bytes($s)) -eq [Convert]::ToHexString($raw)) 'Roundtrip mismatch'
Require ($s.Stats.GetStat(14) -eq 990000 -and $s.Stats.GetStat(15) -eq 2500000) 'Gold not full'
Require ((($s.Skills.SkillLevels|Measure-Object -Sum).Sum+$s.Stats.GetStat(5)) -eq 110) 'Skill budget mismatch'
$belt=@($s.Items|Where-Object {$_.Position.Mode -eq 'InBelt'})
Require ($belt.Count -eq 16 -and @($belt|Where-Object ItemCodeString -ne 'rvl').Count -eq 0) 'Belt not full purple'
for($slot=0;$slot -lt 16;$slot++){Require (@($belt|Where-Object {$_.Position.InvX -eq $slot -and $_.Position.InvY -eq 0}).Count -eq 1) 'Belt slot mismatch'}
$repo=Split-Path $PSScriptRoot -Parent;$data=Join-Path $repo '火弩术士\参考资料\数据表'
$assembly=[D2SSharp.Model.D2Save].Assembly;$reader=[IO.StreamReader]::new($assembly.GetManifestResourceStream('D2SSharp.Data.Txt._105.misc.txt'))
$misc=@($reader.ReadToEnd()|ConvertFrom-Csv -Delimiter "`t");$reader.Dispose()
$rows=@(Import-Csv -LiteralPath (Join-Path $data 'armor.txt') -Delimiter "`t")+@(Import-Csv -LiteralPath (Join-Path $data 'weapons.txt') -Delimiter "`t")+$misc
$sizes=@{};foreach($row in $rows){$sizes[$row.code]=@([int]$row.invwidth,[int]$row.invheight)}
foreach($page in @('Inventory','Cube','Stash')){
 $grid=@{};$width=if($page -eq 'Cube'){3}else{10};$height=if($page -eq 'Stash'){10}else{4}
 foreach($item in $s.Items|Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq $page}){
  $size=$sizes[$item.ItemCodeString];Require ($null -ne $size -and $size[0] -gt 0 -and $size[1] -gt 0) "Unknown item dimensions: $($item.ItemCodeString)"
  for($dx=0;$dx -lt $size[0];$dx++){for($dy=0;$dy -lt $size[1];$dy++){
   $x=$item.Position.InvX+$dx;$y=$item.Position.InvY+$dy;$key="$x,$y"
   Require ($x -ge 0 -and $y -ge 0 -and $x -lt $width -and $y -lt $height -and !$grid.ContainsKey($key)) "Overlap/bounds: $page $key"
   $grid[$key]=$item.ItemCodeString
  }}
 }
}
$inventory=@($s.Items|Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Inventory'})
foreach($code in @('box','ibk','key')){Require (@($inventory|Where-Object ItemCodeString -eq $code).Count -eq 1) "Missing carried tool: $code"}
foreach($index in @(381,400)){Require (@($inventory|Where-Object {$_.Quality -eq 'Unique' -and $_.QualityData.FileIndex -eq $index}).Count -eq 1) "Missing unique charm $index"}
$isFire=$name -eq 'FireHexBow';$sunderIndex=if($isFire){433}else{434};$layer=if($isFire){57}else{9};$expectedSkillers=if($isFire){7}else{6}
$sunder=@($inventory|Where-Object {$_.Quality -eq 'Unique' -and $_.QualityData.FileIndex -eq $sunderIndex})
Require ($sunder.Count -eq 1 -and $sunder[0].Stats.Count -eq 7) 'Renewed sunder type/roll count mismatch'
$skillers=@($inventory|Where-Object {$_.ItemCodeString -eq 'cm3' -and @($_.Stats|Where-Object {[int]$_.Id -eq 188 -and $_.Layer -eq $layer -and $_.Value -eq 1}).Count -eq 1})
Require ($skillers.Count -eq $expectedSkillers) 'Skiller count mismatch'
foreach($charm in $skillers){Require (@($charm.Stats|Where-Object {[int]$_.Id -eq 7 -and $_.Value -eq 11520}).Count -eq 1) 'Skiller life mismatch'}
$portalBook=@($s.Items|Where-Object ItemCodeString -eq 'tbk');Require ($portalBook.Count -eq 1) 'Missing town portal book'
Require ($portalBook[0].Position.StorePage -eq $(if($isFire){'Stash'}else{'Inventory'})) 'Unexpected portal-book layout'
$all=@(Flatten $s.Items)+@(Flatten $s.MercItems.Items)
Require (@($all|Where-Object ItemCodeString -eq 'cjw').Count -eq 1) 'Colossal jewel count mismatch'
Require ($s.MercItems.Items.Count -eq 3) 'Mercenary equipment count mismatch'
[pscustomobject]@{Result='PASS';Character=$name;Bytes=$raw.Length;SHA256=(Get-FileHash -LiteralPath $SavePath).Hash;Gold=990000;PersonalStashGold=2500000;BeltFullPurple=16;SpentSkills=($s.Skills.SkillLevels|Measure-Object -Sum).Sum;UnspentSkills=$s.Stats.GetStat(5);Skillers=$skillers.Count;RenewedSunderIndex=$sunderIndex;ColossalJewels=1;PortalBookLocation=[string]$portalBook[0].Position.StorePage;InventoryCubeStashBoundsAndOverlap=$true;HeaderChecksumAndRoundtrip=$true}|ConvertTo-Json
