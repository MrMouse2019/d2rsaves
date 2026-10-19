param(
 [Parameter(Mandatory)][string]$SavePath,
 [string]$LibraryPath=(Join-Path $env:USERPROFILE '.nuget\packages\d2ssharp\0.0.24\lib\net10.0\D2SSharp.dll')
)
$ErrorActionPreference='Stop'
$bdRoot=Split-Path $PSScriptRoot -Parent
$unique=Import-Csv -LiteralPath (Join-Path $bdRoot '参考资料\数据表\uniqueitems.txt') -Delimiter "`t"
$skills=Import-Csv -LiteralPath (Join-Path $bdRoot '参考资料\数据表\skills.txt') -Delimiter "`t"
$row=@($unique | Where-Object index -eq 'Sling')[0]
$skill=@($skills | Where-Object skill -eq $row.par1)
if($row.prop1 -ne 'oskill' -or $skill.Count -ne 1){throw 'Cannot resolve Sling oskill from game data'}
$expected=[int]$skill[0].'*Id'
Add-Type -Path $LibraryPath
Add-Type -ReferencedAssemblies $LibraryPath -TypeDefinition @'
public static class PortalRegression {
 public static D2SSharp.Model.D2Save Read(string p)=>D2SSharp.Model.D2Save.Read(System.IO.File.ReadAllBytes(p));
}
'@
$save=[PortalRegression]::Read($SavePath)
$ring=@($save.Items | Where-Object {$_.Quality -eq 'Unique' -and $_.QualityData.FileIndex -eq [int]$row.'*ID'})
if($ring.Count -ne 1){throw 'Expected exactly one Sling ring'}
$stats=@($ring[0].Stats | Where-Object {[int]$_.Id -eq 97})
if($stats.Count -ne 1 -or $stats[0].Layer -ne $expected -or $stats[0].Value -ne 1){throw "Sling oskill mismatch: expected $expected ($($row.par1)), actual $($stats.Layer -join ',')"}
foreach($s in @($save.Character.SkillHotkeys)+@($save.Character.LeftSkill,$save.Character.RightSkill,$save.Character.SwitchLeftSkill,$save.Character.SwitchRightSkill)){
 if($s.SkillId -eq 359){throw 'A skill binding still references internal TownPortal 359'}
}
[pscustomobject]@{Result='PASS';Character=$save.Character.Preview.Name;SlingUniqueIndex=[int]$row.'*ID';ExpectedSkill=$expected;ExpectedSkillName=$row.par1;ActualSkill=$stats[0].Layer;Level=$stats[0].Value;NoInternalPortalBindings=$true} | ConvertTo-Json
