param(
 [Parameter(Mandatory)][string]$SourcePath,
 [Parameter(Mandatory)][string]$OutputPath,
 [string]$LibraryPath=(Join-Path $env:USERPROFILE '.nuget\packages\d2ssharp\0.0.24\lib\net10.0\D2SSharp.dll')
)
$ErrorActionPreference='Stop'
if(Test-Path -LiteralPath $OutputPath){throw 'Output exists; preserve the prior version and use a new destination'}
Add-Type -Path $LibraryPath
Add-Type -ReferencedAssemblies $LibraryPath -TypeDefinition @'
using System;
using System.IO;
using D2SSharp.Model;
public static class PortalRepair {
 public static D2Save Read(string p)=>D2Save.Read(File.ReadAllBytes(p));
 public static byte[] Bytes(D2Save s)=>s.ToBytes();
 public static uint Checksum(byte[] b) {uint c=0;for(int i=0;i<b.Length;i++)c=unchecked(((c<<1)|(c>>31))+(uint)((i>=12&&i<16)?0:b[i]));return c;}
}
'@
$bdRoot=Split-Path $PSScriptRoot -Parent
$skillRows=Import-Csv -LiteralPath (Join-Path $bdRoot '参考资料\数据表\skills.txt') -Delimiter "`t"
$skill=@($skillRows | Where-Object skill -eq 'Townportal O Skill')
if($skill.Count -ne 1){throw 'Ambiguous correct oskill'}
$expected=[int]$skill[0].'*Id';if($expected -ne 411){throw 'Unexpected source data version; re-investigate instead of guessing'}
$original=[IO.File]::ReadAllBytes($SourcePath);$s=[PortalRepair]::Read($SourcePath)
if([Convert]::ToHexString([PortalRepair]::Bytes($s)) -ne [Convert]::ToHexString($original)){throw 'Source roundtrip differs'}
$ring=@($s.Items | Where-Object {$_.Quality -eq 'Unique' -and $_.QualityData.FileIndex -eq 415})
if($ring.Count -ne 1){throw 'Expected exactly one Sling'}
$portal=@($ring[0].Stats | Where-Object {[int]$_.Id -eq 97})
if($portal.Count -ne 1 -or $portal[0].Layer -ne 359 -or $portal[0].Value -ne 1){throw 'Source does not match the diagnosed 359 portal defect'}
$portal[0].Layer=$expected
$bindings=@($s.Character.SkillHotkeys)+@($s.Character.LeftSkill,$s.Character.RightSkill,$s.Character.SwitchLeftSkill,$s.Character.SwitchRightSkill)
$changed=@($bindings | Where-Object SkillId -eq 359)
foreach($b in $changed){$b.SkillId=$expected}
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force | Out-Null
[IO.File]::WriteAllBytes($OutputPath,[PortalRepair]::Bytes($s))
$raw=[IO.File]::ReadAllBytes($OutputPath);$check=[PortalRepair]::Read($OutputPath)
if([Convert]::ToHexString([PortalRepair]::Bytes($check)) -ne [Convert]::ToHexString($raw)){throw 'Output roundtrip differs'}
if([BitConverter]::ToUInt32($raw,8) -ne $raw.Length -or [PortalRepair]::Checksum($raw) -ne [BitConverter]::ToUInt32($raw,12)){throw 'Output length/checksum invalid'}
$fixed=@($check.Items | Where-Object {$_.Quality -eq 'Unique' -and $_.QualityData.FileIndex -eq 415})[0]
$fixedPortal=@($fixed.Stats | Where-Object {[int]$_.Id -eq 97})
if($fixedPortal.Count -ne 1 -or $fixedPortal[0].Layer -ne $expected){throw 'Fixed skill lost on disk'}
# Revert exactly the intended changes in a fresh read and require full byte equality.
$fixedPortal[0].Layer=359
foreach($b in @($check.Character.SkillHotkeys)+@($check.Character.LeftSkill,$check.Character.RightSkill,$check.Character.SwitchLeftSkill,$check.Character.SwitchRightSkill)){
 if($b.SkillId -eq $expected){$b.SkillId=359}
}
if([Convert]::ToHexString([PortalRepair]::Bytes($check)) -ne [Convert]::ToHexString($original)){throw 'Unrelated data changed or pre-existing correct oskill bindings need explicit handling'}
$report=[ordered]@{
 Character=$s.Character.Preview.Name;Class=$s.Character.Class.ToString();Level=$s.Character.Level;Format=$s.Version;Source='Latest landed CN snapshot';SourceSHA256=(Get-FileHash -LiteralPath $SourcePath -Algorithm SHA256).Hash
 File=(Split-Path $OutputPath -Leaf);Bytes=$raw.Length;SHA256=(Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash
 Fix=[ordered]@{Item='Sling';UniqueIndex=415;StatId=97;OldSkillId=359;OldSkillName='TownPortal';NewSkillId=$expected;NewSkillName='Townportal O Skill';Level=1;SkillBindingsChanged=$changed.Count}
 Validation=[ordered]@{RoundtripIdentical=$true;DeclaredLength=$true;Checksum=$true;RevertingFixReproducesSourceExactly=$true;OtherItemsStatsKeysAndProgressUnchanged=$true;InGameCrashRetest='Pending user test';CopiedToChineseGameFolder=$false}
 CurrentSnapshot=[ordered]@{SkillPointsSpent=($s.Skills.SkillLevels | Measure-Object -Sum).Sum;SkillPointsUnspent=$s.Stats.GetStat(5);BeltPotions=@($s.Items | Where-Object {$_.Position.Mode -eq 'InBelt'}).Count}
}
$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path (Split-Path $OutputPath -Parent) '校验清单.json') -Encoding utf8
$report | ConvertTo-Json -Depth 8
