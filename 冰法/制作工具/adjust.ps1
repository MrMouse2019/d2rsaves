param([Parameter(Mandatory)][string]$SourcePath,[Parameter(Mandatory)][string]$OutputPath)
. "$PSScriptRoot/common.ps1"
Require (!(Test-Path $OutputPath)) 'Output already exists'
$raw=[IO.File]::ReadAllBytes($SourcePath);$s=[IceEdit]::Read($SourcePath)
Require ($s.Version -eq 105 -and $s.Character.Preview.Name -eq 'BlizzSorc' -and $s.Character.Level -eq 99 -and $s.Stats.GetStat(12) -eq 99) 'Wrong source'
Require (Same ([IceEdit]::Bytes($s)) $raw) 'Source roundtrip mismatch'
$before=Resistance $s;Require (($before -join ',') -eq '110,145,76,65') 'Recalculate resistance for changed source'
$originalCount=$s.Items.Count;$moved=@();$positions=@{};$beltCodes=@{}
# Keep all user items and their identities; move only six all-resist charms.
$allres=@($s.Items|Where-Object {$_.ItemCodeString -eq 'cm1' -and $_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Inventory' -and (Value $_ 39) -eq 5 -and (Value $_ 45) -eq 5}|Sort-Object {$_.Position.InvX})
Require ($allres.Count -eq 6) 'Expected six all-resist small charms'
$prefix=Import-Csv "$data/magicprefix.txt" -Delimiter "`t";$suffix=Import-Csv "$data/magicsuffix.txt" -Delimiter "`t"
Require ($prefix[349].mod1code -eq 'res-cold' -and $prefix[349].mod1max -eq 11 -and $prefix[408].mod1code -eq 'res-pois' -and $prefix[408].mod1max -eq 11 -and $suffix[349].itype1 -eq 'scha' -and $suffix[349].mod1max -eq 20) 'Affix table mismatch'
for($n=0;$n -lt 6;$n++){$old=$allres[$n];$idx=$s.Items.IndexOf($old);$positions[$idx]=$old.Position;$originalPos=$old.Position;Stash $s $old;$moved+=[ordered]@{Index=$idx;FromX=$originalPos.InvX;FromY=$originalPos.InvY;StashX=$old.Position.InvX;StashY=$old.Position.InvY};$c=[D2SSharp.Model.Item]::new();$c.ItemCodeString='cm1';$c.Version=101;$c.ItemLevel=99;$c.ItemSeed=Seed;$c.Flags=[D2SSharp.Enums.ItemFlags]::Identified -bor [D2SSharp.Enums.ItemFlags]::JustSaved;$c.Quality=[D2SSharp.Enums.ItemQuality]::Magic;$c.QualityData=[D2SSharp.Model.MagicQualityData]::new();$c.QualityData.PrefixId=if($n -lt 3){349}else{408};$c.QualityData.SuffixId=349;$c.Position=$originalPos;foreach($a in @(@(7,5120),@($(if($n -lt 3){43}else{45}),11))){$st=[D2SSharp.Model.Stat]::new();$st.Id=[D2SSharp.Enums.StatId][int]$a[0];$st.Value=[long]$a[1];$c.Stats.Add($st)};$s.Items.Add($c)}
# Copy verified perfect runewords with fresh seeds; preserve mercenary identity and aura.
$donorPath="$repo/新星电法/实测定稿/NovaPerfect.d2s";$donor=[IceEdit]::Read($donorPath)
$oldMerc=@();foreach($body in @('RightArm','Head','Torso')){$old=@($s.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq $body});Require ($old.Count -eq 1) 'Merc slot missing';$old=$old[0];$oldMerc+=[ordered]@{Code=$old.ItemCodeString;Runeword=$old.RunewordId;Unique=$old.QualityData.FileIndex;Slot=$body};$new=@($donor.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq $body});Require ($new.Count -eq 1) 'Donor slot missing';$new=$new[0];Reseed $new;$new.Position=$old.Position;$s.MercItems.Items[$s.MercItems.Items.IndexOf($old)]=$new;Stash $s $old;$s.Items.Add($old)}
Require (@($s.Items|Where-Object {$_.Position.Mode -eq 'Equipped' -and $_.Position.BodyLocation -eq 'Belt' -and $_.ItemCodeString -eq 'ulc'}).Count -eq 1) 'Unexpected belt capacity'
$belt=@($s.Items|Where-Object {$_.Position.Mode -eq 'InBelt'});foreach($p in $belt){$beltCodes[$s.Items.IndexOf($p)]=$p.ItemCodeString;$p.ItemCodeString='rvl'}
foreach($slot in 0..15){if(@($belt|Where-Object {$_.Position.InvX -eq $slot}).Count){continue};$p=[D2SSharp.Model.Item]::new();$p.ItemCodeString='rvl';$p.Version=101;$p.Flags=[D2SSharp.Enums.ItemFlags]::Identified -bor [D2SSharp.Enums.ItemFlags]::CompactSave -bor [D2SSharp.Enums.ItemFlags]::JustSaved;$p.Position=Pos 'InBelt' 'Null' $slot 0;$s.Items.Add($p)}
foreach($page in @('Inventory','Cube','Stash')){[void](Grid $s $page)}
New-Item -ItemType Directory -Path (Split-Path $OutputPath -Parent) -Force|Out-Null
[IO.File]::WriteAllBytes($OutputPath,[IceEdit]::Bytes($s));$written=[IO.File]::ReadAllBytes($OutputPath);$v=[IceEdit]::Read($OutputPath)
Require ([Convert]::ToHexString($written[0..3]) -eq '55AA55AA' -and [BitConverter]::ToUInt32($written,8) -eq $written.Length -and [BitConverter]::ToUInt32($written,12) -eq [IceEdit]::Sum($written)) 'Header length checksum'
Require (Same ([IceEdit]::Bytes($v)) $written) 'Written roundtrip mismatch'
$after=Resistance $v;$switchRes=Resistance $v -Switch;Require (($after -join ',') -eq '80,115,79,68' -and ($switchRes -join ',') -eq '40,75,79,68') 'Resistance mismatch'
$inv=@($v.Items|Where-Object {$_.Position.Mode -eq 'Stored' -and $_.Position.StorePage -eq 'Inventory'})
$cold=@($inv|Where-Object {$_.ItemCodeString -eq 'cm1' -and (Value $_ 43) -eq 11});$poison=@($inv|Where-Object {$_.ItemCodeString -eq 'cm1' -and (Value $_ 45) -eq 11})
Require ($cold.Count -eq 4 -and $poison.Count -eq 3 -and @($cold+$poison|Where-Object {(Value $_ 7) -ne 5120}).Count -eq 0) 'Charm stats mismatch'
$mi=@($v.MercItems.Items|Where-Object ItemCodeString -eq '7wc')[0];$mh=@($v.MercItems.Items|Where-Object ItemCodeString -eq 'uh9')[0]
Require ($mi.RunewordId -eq 20568 -and ($mi.Sockets.ItemCodeString -join ',') -eq 'r08,r03,r07,r12' -and (Value $mi 151 120 -RW) -eq 17 -and (Value $mi 17 -RW) -eq 260 -and (Value $mi 119 -RW) -eq 250 -and (Value $mi 97 9 -RW) -eq 6) 'Insight mismatch'
Require (($mh.Sockets.ItemCodeString -join ',') -eq 'r13,r16,r07' -and (Value $mh 151 109 -RW) -eq 1 -and (Value $mh 16 -RW) -eq 100) 'Cure mismatch'
$vb=@($v.Items|Where-Object {$_.Position.Mode -eq 'InBelt'});Require ($vb.Count -eq 16 -and @($vb|Where-Object ItemCodeString -ne 'rvl').Count -eq 0) 'Belt mismatch';foreach($slot in 0..15){Require (@($vb|Where-Object {$_.Position.InvX -eq $slot -and $_.Position.InvY -eq 0}).Count -eq 1) 'Belt layout mismatch'}
foreach($page in @('Inventory','Cube','Stash')){[void](Grid $v $page)}
function Tree($items){foreach($i in $items){if($null -eq $i){continue};$i;Tree $i.Sockets}}
$tree=@(Tree $v.Items)+@(Tree $v.MercItems.Items);$colossal=@($tree|Where-Object {$_.Quality -eq 'Unique' -and $_.QualityData.FileIndex -ge 420 -and $_.QualityData.FileIndex -le 429 -and $_.ItemCodeString -eq 'cjw'});Require ($colossal.Count -le 1) 'Too many colossal jewels'
$sunder=@($inv|Where-Object ItemCodeString -eq 'cs2');Require ($sunder.Count -eq 1 -and $sunder[0].QualityData.FileIndex -eq 427 -and $sunder[0].Stats.Count -eq 7 -and (Value $sunder[0] 43) -eq -70 -and (Value $sunder[0] 335) -eq 10 -and (Value $sunder[0] 7) -eq 16640 -and (Value $sunder[0] 35) -eq 10 -and (Value $sunder[0] 99) -eq 24 -and (Value $sunder[0] 80) -eq 25 -and (Value $sunder[0] 187) -eq 300) 'Sunder changed/malformed'
# Revert exactly the authorized positions, new items, belt codes and three merc slots.
$undo=[IceEdit]::Read($OutputPath);$original=[IceEdit]::Read($SourcePath)

foreach($idx in $positions.Keys){$undo.Items[[int]$idx].Position=$positions[$idx]};foreach($idx in $beltCodes.Keys){$undo.Items[[int]$idx].ItemCodeString=$beltCodes[$idx]}
for($n=0;$n -lt $undo.MercItems.Items.Count;$n++){if($undo.MercItems.Items[$n].Position.BodyLocation -in @('RightArm','Head','Torso')){$oldStored=$undo.Items[$originalCount+6+$(@('RightArm','Head','Torso').IndexOf([string]$undo.MercItems.Items[$n].Position.BodyLocation))];$oldStored.Position=$original.MercItems.Items[$n].Position;$undo.MercItems.Items[$n]=$oldStored}}
while($undo.Items.Count -gt $originalCount){$undo.Items.RemoveAt($undo.Items.Count-1)}
Require (Same ([IceEdit]::Bytes($undo)) $raw) 'Unrelated data changed'
$hire=Import-Csv "$PSScriptRoot/hireling.txt" -Delimiter "`t"|Where-Object {$_.Id -eq $v.Character.MercData.HirelingId -and $_.Level -eq '75'}
Require ($hire.Count -eq 1 -and $v.Character.MercData.Experience -eq 114095520) 'Merc data changed; recalculate'
$mercStrength=[int][math]::Floor([int]$hire.Str+(98-75)*[int]$hire.'Str/Lvl'/8);$mercDex=[int][math]::Floor([int]$hire.Dex+(98-75)*[int]$hire.'Dex/Lvl'/8)
Require ($mercStrength -ge 178 -and $mercDex -ge 130 -and $mercStrength -ge 96) 'Merc cannot equip gear without old helm'
$ma=@($v.MercItems.Items|Where-Object {$_.Position.BodyLocation -eq 'Torso'})[0]
$baseArmor=@($armor|Where-Object code -eq $ma.ItemCodeString)[0]
$armorRequirement=[int]$baseArmor.reqstr-$(if($ma.Flags.HasFlag([D2SSharp.Enums.ItemFlags]::Ethereal)){10}else{0})
Require ($mercStrength -ge $armorRequirement) 'Merc armor requires strength from the old helm; choose a wearable replacement'
Require ($ma.RunewordId -eq 20520 -and (Value $ma 39 -RW) -eq 50 -and (Value $ma 41 -RW) -eq 50 -and (Value $ma 43 -RW) -eq 50 -and (Value $ma 45 -RW) -eq 50 -and (Value $ma 60 -RW) -eq 8 -and (Value $ma 0 -RW) -eq 20 -and (Value $ma 127 -RW) -eq 2 -and ($ma.Sockets.ItemCodeString -join ',') -eq 'r14,r22,r30,r24') 'Chains of Honor mismatch'
$newSeeds=@($tree|Where-Object {$_.ItemSeed -ne 0 -and $_.ItemSeed -notin @((Tree $original.Items).ItemSeed+(Tree $original.MercItems.Items).ItemSeed)})
Require (@($newSeeds.ItemSeed|Sort-Object -Unique).Count -eq $newSeeds.Count) 'New duplicate seeds'
$report=[ordered]@{Date=[TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTimeOffset]::UtcNow,'China Standard Time').ToString('o');Character='BlizzSorc';Level=99;Format=105;Bytes=$written.Length;SHA256=(Get-FileHash $OutputPath).Hash;SourceSHA256=(Get-FileHash $SourcePath).Hash;DonorSHA256=(Get-FileHash $donorPath).Hash;LibrarySHA256=(Get-FileHash $lib).Hash;Status='原角色用户已测试；本次调整待游戏复测';Resistance=[ordered]@{Order='Fire,Lightning,Cold,Poison';Difficulty='Hell';Anya=30;Penalty=-100;SpiritRuneContributions='Ort lightning 35, Thul cold 35, Tal poison 35';BeforeRaw=$before;MainRaw=$after;MainDisplay=@(75,75,75,68);SwitchRaw=$switchRes;SwitchDisplay=@(40,75,75,68);NoEnemyConvictionOrLowerResist=$true};Charms=[ordered]@{ColdLife=4;PoisonLife=3;EachLife=20;EachResistance=11;OldAllResRetainedInStash=6;Moved=$moved};Mercenary=[ordered]@{HirelingId=$v.Character.MercData.HirelingId;Aura=$hire.Skill2;Level=98;StrengthWithoutOldHelm=$mercStrength;Dexterity=$mercDex;Weapon='Ethereal superior Giant Thresher Insight 17/260/250/6';Helm='Ethereal superior Bone Visage Cure';Armor='Ethereal superior Archon Plate Chains of Honor; original Sacred Armor Fortitude preserved in stash';OldGear=$oldMerc;OldGearRetainedInStash=$true};Belt=[ordered]@{Before=$belt.Count;After=16;FullRejuvenation=16};Validation=[ordered]@{HeaderLengthChecksum=$true;WrittenRoundtrip=$true;UndoChangesReproducesSourceBytes=$true;InventoryCubeStashBoundsOverlap=$true;RenewedColdSunderTypeAndSevenStats=$true;ColossalJewels=$colossal.Count;MercenaryAllThreeItemsWearable=$true;SkillsStatsGoldProgressAndExistingSeedsPreserved=$true;InGameRetestPending=$true};Files=@()}
$report|ConvertTo-Json -Depth 10|Set-Content (Join-Path (Split-Path $OutputPath -Parent) '校验清单.json') -Encoding utf8
$report|ConvertTo-Json -Depth 10
