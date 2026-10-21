$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$lib="$repo/冰法/工具依赖/d2ssharp/lib/net10.0/D2SSharp.dll"
if((Get-FileHash $lib).Hash -ne '333C325929D3970FACBC646E0479A7B5BCECCB98AB71D8D41B8EF7ED6C127860'){throw 'Unexpected library'}
Add-Type -Path $lib
Add-Type -ReferencedAssemblies $lib -TypeDefinition @'
public static class IceEdit {
 public static D2SSharp.Model.D2Save Read(string p)=>D2SSharp.Model.D2Save.Read(System.IO.File.ReadAllBytes(p));
 public static byte[] Bytes(D2SSharp.Model.D2Save s)=>s.ToBytes();
 public static uint Sum(byte[] b){uint c=0;for(int i=0;i<b.Length;i++)c=unchecked(((c<<1)|(c>>31))+(uint)((i>=12&&i<16)?0:b[i]));return c;}
}
'@
function Require($c,[string]$m){if(!$c){throw $m}}
function Same($a,$b){return [Convert]::ToHexString($a) -eq [Convert]::ToHexString($b)}
function Seed {return [BitConverter]::ToUInt32([Security.Cryptography.RandomNumberGenerator]::GetBytes(4),0)}
function Reseed($i){$i.ItemSeed=Seed;foreach($c in $i.Sockets){if($null -ne $c){Reseed $c}}}
function Pos($mode,$page,$x,$y,$body='None'){$p=[D2SSharp.Model.ItemPosition]::new();$p.Mode=[D2SSharp.Enums.ItemMode]::$mode;$p.StorePage=[D2SSharp.Enums.StorePage]::$page;$p.BodyLocation=[D2SSharp.Enums.BodyLocation]::$body;$p.InvX=$x;$p.InvY=$y;return $p}
function Value($i,$id,$layer=0,[switch]$RW){$list=if($RW){$i.RunewordStats}else{$i.Stats};$v=@($list|Where-Object {[int]$_.Id -eq $id -and $_.Layer -eq $layer});if(!$v.Count){return 0};Require ($v.Count -eq 1) 'Duplicate stat';return [long]$v[0].Value}
$data="$repo/火弩术士/参考资料/数据表"
$asm=[D2SSharp.Model.D2Save].Assembly;$r=[IO.StreamReader]::new($asm.GetManifestResourceStream('D2SSharp.Data.Txt._105.misc.txt'));$misc=@($r.ReadToEnd()|ConvertFrom-Csv -Delimiter "`t");$r.Dispose()
$armor=@(Import-Csv "$data/armor.txt" -Delimiter "`t");$weapons=@(Import-Csv "$data/weapons.txt" -Delimiter "`t")
$sizes=@{};foreach($row in $armor+$weapons+$misc){$sizes[$row.code]=@([int]$row.invwidth,[int]$row.invheight)}
function Grid($s,$page){$g=@{};$w=if($page -eq 'Cube'){3}else{10};$h=if($page -eq 'Stash'){10}else{4};foreach($i in $s.Items|Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq $page}){$z=$sizes[$i.ItemCodeString];Require ($null -ne $z -and $z[0] -gt 0 -and $z[1] -gt 0) 'Unknown dimensions';for($x=0;$x -lt $z[0];$x++){for($y=0;$y -lt $z[1];$y++){$gx=$i.Position.InvX+$x;$gy=$i.Position.InvY+$y;Require ($gx -ge 0 -and $gy -ge 0 -and $gx -lt $w -and $gy -lt $h -and !$g.ContainsKey("$gx,$gy")) "Overlap/bounds $page $gx,$gy";$g["$gx,$gy"]=$true}}};return ,$g}
function Free($s,$page,$width,$height){$g=Grid $s $page;for($y=0;$y -le 10-$height;$y++){for($x=0;$x -le 10-$width;$x++){$ok=$true;for($dx=0;$dx -lt $width;$dx++){for($dy=0;$dy -lt $height;$dy++){if($g.ContainsKey("$($x+$dx),$($y+$dy)")){$ok=$false}}};if($ok){return @($x,$y)}}};throw 'Stash full'}
function Stash($s,$i){$z=$sizes[$i.ItemCodeString];$p=Free $s 'Stash' $z[0] $z[1];$i.Position=Pos 'Stored' 'Stash' $p[0] $p[1]}
$gems=Import-Csv "$PSScriptRoot/gems.txt" -Delimiter "`t"
function ItemResistance($i){
 $v=@(0,0,0,0)
 foreach($st in @($i.Stats)+@($i.RunewordStats)){
  switch([int]$st.Id){39{$v[0]+=$st.Value};41{$v[1]+=$st.Value};43{$v[2]+=$st.Value};45{$v[3]+=$st.Value}}
 }
 foreach($c in $i.Sockets){
  if($null -eq $c){continue}
  $z=ItemResistance $c
  for($n=0;$n -lt 4;$n++){$v[$n]+=$z[$n]}
  $gem=@($gems|Where-Object code -eq $c.ItemCodeString)
  if($gem.Count){
   $category=if($i.ItemCodeString -eq 'uit'){'shield'}elseif($i.ItemCodeString -in @($weapons.code)){'weapon'}else{'helm'}
   for($m=1;$m -le 3;$m++){
    $code=$gem[0]."${category}Mod${m}Code"
    $value=[int]$gem[0]."${category}Mod${m}Max"
    switch($code){
     'res-fire'{$v[0]+=$value}
     'res-ltng'{$v[1]+=$value}
     'res-cold'{$v[2]+=$value}
     'res-pois'{$v[3]+=$value}
     'res-all'{for($n=0;$n -lt 4;$n++){$v[$n]+=$value}}
    }
   }
  }
 }
 return ,$v
}
function Resistance($s,[switch]$Switch){$q=0;foreach($d in @('Normal','Nightmare','Hell')){Require (([int]$s.Quests.$d.ActV.PrisonOfIce -band 1) -eq 1) 'Verify Anya quest';$q+=10};$v=@(($q-100),($q-100),($q-100),($q-100));foreach($i in $s.Items){$active=$i.Position.Mode -eq 'Equipped' -and $(if($Switch){$i.Position.BodyLocation -notin @('RightArm','LeftArm')}else{$i.Position.BodyLocation -notin @('RightHand','LeftHand')});$charm=$i.Position.Mode -eq 'Stored' -and $i.Position.StorePage -eq 'Inventory' -and $i.ItemCodeString -in @('cm1','cm2','cm3','cs2');if($active -or $charm){$r=ItemResistance $i;for($n=0;$n -lt 4;$n++){$v[$n]+=$r[$n]}}};return ,$v}
