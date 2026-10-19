param(
 [Parameter(Mandatory)][string]$SourcePath,
 [Parameter(Mandatory)][string]$OutputPath,
 [Parameter(Mandatory)][string]$CharacterName,
 [Parameter(Mandatory)][string]$LibraryPath
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputPath){throw 'Output already exists; preserve the previous version'}
Add-Type -Path $LibraryPath
Add-Type -ReferencedAssemblies $LibraryPath -TypeDefinition @'
public static class ArchiveSupply {
 public static D2SSharp.Model.D2Save Read(string p)=>D2SSharp.Model.D2Save.Read(System.IO.File.ReadAllBytes(p));
 public static byte[] Bytes(D2SSharp.Model.D2Save s)=>s.ToBytes();
 public static uint Sum(byte[] b){uint c=0;for(int i=0;i<b.Length;i++)c=unchecked(((c<<1)|(c>>31))+(uint)((i>=12&&i<16)?0:b[i]));return c;}
}
'@
function Require($condition,[string]$message){if(!$condition){throw $message}}
function RemoveBelt($model){foreach($item in @($model.Items|Where-Object {$_.Position.Mode -eq 'InBelt'})){[void]$model.Items.Remove($item)}}
$raw=[IO.File]::ReadAllBytes($SourcePath)
$save=[ArchiveSupply]::Read($SourcePath)
Require ($save.Version -eq 105 -and $save.Character.Preview.Name -eq $CharacterName -and $save.Character.Level -eq 99) 'Unexpected character/version/level'
Require ([Convert]::ToHexString([ArchiveSupply]::Bytes($save)) -eq [Convert]::ToHexString($raw)) 'Source roundtrip mismatch'
$beltItem=@($save.Items|Where-Object {$_.Position.Mode -eq 'Equipped' -and $_.Position.BodyLocation -eq 'Belt'})
Require ($beltItem.Count -eq 1 -and $beltItem[0].ItemCodeString -in @('zvb','ulc')) 'Verify belt capacity before using this 16-slot tool'
$oldGold=[long]$save.Stats.GetStat(14);$oldBank=[long]$save.Stats.GetStat(15)
$beforeBelt=@($save.Items|Where-Object {$_.Position.Mode -eq 'InBelt'})
Require (@($beforeBelt|Where-Object {$_.ItemCodeString -notin @('rvl','rvs') -or $_.Position.InvY -ne 0 -or $_.Position.InvX -lt 0 -or $_.Position.InvX -gt 15}).Count -eq 0) 'Unexpected belt item/position'
Require (@($beforeBelt.Position.InvX|Sort-Object -Unique).Count -eq $beforeBelt.Count) 'Duplicate belt slots'
$save.Stats.SetStat(14,10000*$save.Character.Level)
$save.Stats.SetStat(15,2500000)
foreach($item in $beforeBelt){$item.ItemCodeString='rvl'}
for($slot=0;$slot -lt 16;$slot++){
 if(@($beforeBelt|Where-Object {$_.Position.InvX -eq $slot}).Count){continue}
 $item=[D2SSharp.Model.Item]::new();$item.ItemCodeString='rvl';$item.Version=101
 $item.Flags=[D2SSharp.Enums.ItemFlags]::Identified -bor [D2SSharp.Enums.ItemFlags]::CompactSave -bor [D2SSharp.Enums.ItemFlags]::JustSaved
 $position=[D2SSharp.Model.ItemPosition]::new();$position.Mode=[D2SSharp.Enums.ItemMode]::InBelt
 $position.StorePage=[D2SSharp.Enums.StorePage]::Null;$position.InvX=$slot;$position.InvY=0
 $item.Position=$position;$save.Items.Add($item)
}
$parent=Split-Path $OutputPath -Parent
if(!(Test-Path -LiteralPath $parent)){New-Item -ItemType Directory -Path $parent|Out-Null}
$candidate=$OutputPath+'.tmp'
Require (!(Test-Path -LiteralPath $candidate)) 'Candidate already exists; inspect it before retrying'
[IO.File]::WriteAllBytes($candidate,[ArchiveSupply]::Bytes($save))
$written=[IO.File]::ReadAllBytes($candidate);$check=[ArchiveSupply]::Read($candidate)
Require ([Convert]::ToHexString($written[0..3]) -eq '55AA55AA' -and [BitConverter]::ToUInt32($written,4) -eq 105 -and [BitConverter]::ToUInt32($written,8) -eq $written.Length -and [BitConverter]::ToUInt32($written,12) -eq [ArchiveSupply]::Sum($written)) 'Header/length/checksum mismatch'
Require ([Convert]::ToHexString([ArchiveSupply]::Bytes($check)) -eq [Convert]::ToHexString($written)) 'Written roundtrip mismatch'
Require ($check.Stats.GetStat(14) -eq 990000 -and $check.Stats.GetStat(15) -eq 2500000) 'Gold mismatch'
$belt=@($check.Items|Where-Object {$_.Position.Mode -eq 'InBelt'})
Require ($belt.Count -eq 16 -and @($belt|Where-Object ItemCodeString -ne 'rvl').Count -eq 0) 'Belt not full purple'
for($slot=0;$slot -lt 16;$slot++){Require (@($belt|Where-Object {$_.Position.InvX -eq $slot -and $_.Position.InvY -eq 0}).Count -eq 1) 'Belt slot mismatch'}
$check.Stats.SetStat(14,$oldGold);$check.Stats.SetStat(15,$oldBank)
$sourceCheck=[ArchiveSupply]::Read($SourcePath)
# Zero gold can be omitted from the source stat stream. Normalize only the two
# authorized gold fields on both sides before comparing everything else.
$sourceCheck.Stats.SetStat(14,$oldGold);$sourceCheck.Stats.SetStat(15,$oldBank)
RemoveBelt $check;RemoveBelt $sourceCheck
Require ([Convert]::ToHexString([ArchiveSupply]::Bytes($check)) -eq [Convert]::ToHexString([ArchiveSupply]::Bytes($sourceCheck))) 'Changes outside gold/belt detected'
Move-Item -LiteralPath $candidate -Destination $OutputPath
$report=[ordered]@{
 Date=(Get-Date).ToString('o');Character=$CharacterName;Source=$SourcePath;Output=$OutputPath
 SourceSHA256=(Get-FileHash -LiteralPath $SourcePath).Hash;SHA256=(Get-FileHash -LiteralPath $OutputPath).Hash;Bytes=$written.Length
 GoldBefore=$oldGold;GoldAfter=990000;PersonalStashGoldBefore=$oldBank;PersonalStashGoldAfter=2500000
 GoldLimitSource='https://classic.battle.net/diablo2exp/basics/'
 BeltBefore=$beforeBelt.Count;BeltAfter=16;OnlyGoldAndBeltChanged=$true;HeaderLengthChecksum=$true;WrittenRoundtrip=$true
 SharedStashTouched=$false;LatestSkillsEquipmentInventoryAndProgressPreserved=$true
}
$report|ConvertTo-Json -Depth 5|Set-Content -LiteralPath (Join-Path $parent '补给校验.json') -Encoding utf8
$report|ConvertTo-Json -Depth 5
