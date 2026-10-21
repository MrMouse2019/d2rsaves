param([string]$SavePath="$env:USERPROFILE/Saved Games/Diablo II Resurrected (CN)/BlizzSorc.d2s")
$ErrorActionPreference='Stop'
$repo=Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Add-Type -Path "$repo/冰法/工具依赖/d2ssharp/lib/net10.0/D2SSharp.dll"
Add-Type -ReferencedAssemblies "$repo/冰法/工具依赖/d2ssharp/lib/net10.0/D2SSharp.dll" -TypeDefinition @'
public static class IceSave {
 public static D2SSharp.Model.D2Save Read(string p)=>D2SSharp.Model.D2Save.Read(System.IO.File.ReadAllBytes(p));
 public static byte[] Bytes(D2SSharp.Model.D2Save s)=>s.ToBytes();
 public static uint Sum(byte[] b){uint c=0;for(int i=0;i<b.Length;i++)c=unchecked(((c<<1)|(c>>31))+(uint)((i>=12&&i<16)?0:b[i]));return c;}
}
'@
function ShowItem($i){[ordered]@{Code=$i.ItemCodeString;Seed=$i.ItemSeed;Quality="$($i.Quality)";QualityData=$i.QualityData;Flags="$($i.Flags)";Position=$i.Position;Runeword=$i.RunewordId;Stats=@($i.Stats|Select-Object Id,Layer,Value);RWStats=@($i.RunewordStats|Select-Object Id,Layer,Value);Sockets=@($i.Sockets.ItemCodeString);Defense=$i.Defense;Durability=$i.MaxDurability}}
$p=$SavePath
$s=[IceSave]::Read($p)
[ordered]@{Name=$s.Character.Preview.Name;Level=$s.Character.Level;Version=$s.Version;Stats=$s.Stats;Merc=$s.Character.MercData;MercItems=@($s.MercItems.Items|ForEach-Object {ShowItem $_});Items=@($s.Items|ForEach-Object {ShowItem $_});Skills=$s.Skills}|ConvertTo-Json -Depth 12
