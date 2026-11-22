@echo off
setlocal
set "HALF_RESTORE_SELF=%~f0"
set "HALF_RESTORE_VERIFY="
powershell.exe -NoProfile -Command "$source = [IO.File]::ReadAllText($env:HALF_RESTORE_SELF); & ([scriptblock]::Create(($source -split '(?m)^:RESTORE_POWERSHELL\r?$', 2)[1]))"
set "HALF_RESTORE_RESULT=%ERRORLEVEL%"
echo.
pause
exit /b %HALF_RESTORE_RESULT%

:RESTORE_POWERSHELL

function Read-HalfString($r) {
    $n=$r.ReadInt32()
    if($n -lt 1 -or $n -gt 4096){throw "String length $n at $($r.BaseStream.Position-4)"}
    $b=$r.ReadBytes($n)
    if($b.Length -ne $n -or $b[-1] -ne 0){throw 'Invalid string'}
    [Text.Encoding]::UTF8.GetString($b,0,$n-1)
}
function Read-HalfType($r) {
    $name=Read-HalfString $r
    $count=$r.ReadInt32()
    if($count -lt 0 -or $count -gt 20){throw 'Invalid type tree'}
    for($i=0;$i -lt $count;$i++){ $null=Read-HalfType $r }
    $name
}
function Read-HalfTag($r) {
    $start=$r.BaseStream.Position
    $name=Read-HalfString $r
    if($name -eq 'None'){return}
    $type=Read-HalfType $r
    $sizeAt=$r.BaseStream.Position
    $size=$r.ReadInt32()
    $flags=$r.ReadByte()
    if(($flags -notin @(0,8) -and !($flags -eq 16 -and $size -eq 0)) -or $size -lt 0){throw "Unsupported flags $flags or size $size for $name"}
    $data=$r.BaseStream.Position
    [pscustomobject]@{Name=$name;Type=$type;Start=$start;SizeAt=$sizeAt;Size=$size;Data=$data;End=$data+$size}
}
function Find-HalfTag($r,$text,$name,$from) {
    $p=$text.IndexOf($name+[char]0,$from,[StringComparison]::Ordinal)
    if($p -lt 4){return}
    $r.BaseStream.Position=$p-4
    $tag=Read-HalfTag $r
    if($tag.Name -ne $name){throw "Unexpected tag $name"}
    $tag
}
$ErrorActionPreference='Stop'
$folder=Split-Path -Parent $env:HALF_RESTORE_SELF

function Get-Sections($r) {
 $t=[Text.Encoding]::ASCII.GetString($r.ReadBytes(1MB))
 $p=Find-HalfTag $r $t 'Player Character' 0
 $e=Find-HalfTag $r $t 'Equipment_26_741A2FC641801842FE691295645C604F' $p.Data
 [pscustomobject]@{Player=$p;Equipment=$e;Text=$t}
}
function Write-Name($w,$name){
 $bytes=[Text.Encoding]::UTF8.GetBytes($name)
 $w.Write([int]($bytes.Length+1));$w.Write($bytes);$w.Write([byte]0)
}
function Write-Counter($w,$name,[int]$value){
 Write-Name $w $name; Write-Name $w 'IntProperty'
 $w.Write([int]0);$w.Write([int]4);$w.Write([byte]0);$w.Write($value)
}
function Set-Bytes($data,$offset,$value){
 [Array]::Copy([BitConverter]::GetBytes($value),0,$data,$offset,[BitConverter]::GetBytes($value).Length)
}

function Read-SavePath($prompt,$default,$other){
 while($true){
  $name=(Read-Host "$prompt [$default]").Trim()
  if(!$name){$name=$default}
  if($name -notmatch '^[^\\/:*?"<>|\x00-\x1F]+\.sav$'){
   Write-Host 'Enter only a .sav filename in this folder. Do not enter a path.'
   continue
  }
  $path=Join-Path $folder $name
  if($path -eq $other){Write-Host 'Choose a different file for the destination.';continue}
  $item=Get-Item -LiteralPath $path -ErrorAction SilentlyContinue
  if(!$item -or $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){
   Write-Host "No regular save file named '$name' beside the batch file."
   continue
  }
  if($item.FullName -eq $other){Write-Host 'Choose a different file for the destination.';continue}
  return $item.FullName
 }
}
Write-Host "Save folder: $folder"
$oldPath=Read-SavePath 'Restore FROM (old backup filename)' 'gsc.sav'
$livePath=Read-SavePath 'Restore TO (filename to update)' 'GameProgress.sav' $oldPath
function Get-Top($reader,$player){
 $tags=@{}
 $reader.BaseStream.Position=$player.End
 while($reader.BaseStream.Position -lt $reader.BaseStream.Length){
  $tag=Read-HalfTag $reader
  if(!$tag){break}
  if($tags.ContainsKey($tag.Name)){throw "Duplicate property: $($tag.Name)"}
  $tags[$tag.Name]=$tag
  $reader.BaseStream.Position=$tag.End
 }
 $tags
}
function Get-Record($reader,$tag){
 if(!$tag){throw 'Missing property in the backup'}
 $reader.BaseStream.Position=$tag.Start
 return ,($reader.ReadBytes($tag.End-$tag.Start))
}
function Counter-Record($name,[int]$value){
 $m=[IO.MemoryStream]::new()
 $w=[IO.BinaryWriter]::new($m)
 try{Write-Counter $w $name $value; return ,($m.ToArray())}finally{$w.Dispose()}
}
function Add-Edit($start,$end,[byte[]]$bytes){
 $edits.Add([pscustomobject]@{Start=[long]$start;End=[long]$end;Bytes=$bytes;Order=$edits.Count})
}
$gold=12000
if(!$env:HALF_RESTORE_VERIFY){
 do {
  $answer=Read-Host 'Total gold [12000]'
  if([string]::IsNullOrWhiteSpace($answer)){break}
  $candidate=0
  if([int]::TryParse($answer,[ref]$candidate) -and $candidate -ge 0){$gold=$candidate;break}
  Write-Host 'Enter a whole number from 0 to 2147483647.'
 }while($true)
}
$old=[IO.BinaryReader]::new([IO.File]::OpenRead($oldPath))
$data=[IO.File]::ReadAllBytes($livePath)
$sha=[Security.Cryptography.SHA256]::Create()
$initialHash=[Convert]::ToBase64String($sha.ComputeHash($data))
$fresh=[IO.BinaryReader]::new([IO.MemoryStream]::new($data))
try{
 $a=Get-Sections $old
 $b=Get-Sections $fresh
 $from=Get-Top $old $a.Player
 $to=Get-Top $fresh $b.Player
 $oldDay=Find-HalfTag $old ($a.Text.Substring(0,$a.Player.Start)) 'Day Count' 0
 if(!$oldDay){$oldDay=$from['Day Count'];if($oldDay){$old.BaseStream.Position=$oldDay.Data}}
 if(!$oldDay -or $oldDay.Type -ne 'IntProperty' -or $oldDay.Size -ne 4){throw 'Backup Day Count is missing or invalid'}
 $days=$old.ReadInt32()
 $oldBaron=$from['Baron Defeated Times']
 if(!$oldBaron -or $oldBaron.Type -ne 'IntProperty' -or $oldBaron.Size -ne 4){throw 'Backup Baron counter is missing or invalid'}
 $old.BaseStream.Position=$oldBaron.Data
 $defeats=$old.ReadInt32()
 $edits=[Collections.Generic.List[object]]::new()

 foreach($key in @('Height_21_0EB204DF4978B92AD0ED188FD32EEC7B','Weight_23_65E4C6534D14653F96EB739F159E58CD','Fat_49_7A3AFCEF42B632594A9904B38CD43768')){
  $src=Find-HalfTag $old $a.Text $key $a.Player.Data
  $dst=Find-HalfTag $fresh $b.Text $key $b.Player.Data
  if(!$src -or !$dst -or $src.Type -ne 'DoubleProperty' -or $dst.Type -ne 'DoubleProperty' -or $src.Size -ne 8 -or $dst.Size -ne 8 -or $src.End -gt $a.Equipment.Start -or $dst.End -gt $b.Equipment.Start){throw "Unexpected body field: $key"}
  Set-Bytes $data $dst.Data ($old.ReadDouble())
 }
 $day=Find-HalfTag $fresh ($b.Text.Substring(0,$b.Player.Start)) 'Day Count' 0
 if(!$day){$day=$to['Day Count']}
 if($day){Add-Edit $day.Start $day.End (Counter-Record 'Day Count' $days)}
 else{Add-Edit $b.Player.Start $b.Player.Start (Counter-Record 'Day Count' $days)}
 foreach($key in @('Player Tier','Permanent Tier','Reputation on Rank','Baron Defeated Times','Insured Items')){
  $record=Get-Record $old $from[$key]
  if($to.ContainsKey($key)){Add-Edit $to[$key].Start $to[$key].End $record}
  else{Add-Edit $b.Player.End $b.Player.End $record}
 }
 $funds=$to['Player Funds']
 if(!$funds -or $funds.Type -ne 'IntProperty' -or $funds.Size -ne 4){throw 'Unexpected Player Funds field'}
 Set-Bytes $data $funds.Data ([int]$gold)

 $result=[IO.MemoryStream]::new()
 $offset=0L
 foreach($edit in ($edits | Sort-Object Start,End,Order)){
  if($edit.Start -lt $offset){throw 'Overlapping save edits'}
  $result.Write($data,$offset,$edit.Start-$offset)
  $result.Write($edit.Bytes,0,$edit.Bytes.Length)
  $offset=$edit.End
 }
 $result.Write($data,$offset,$data.Length-$offset)
 $output=$result.ToArray()
 $check=[IO.BinaryReader]::new([IO.MemoryStream]::new($output))
 try{
  $verified=Get-Sections $check
  $top=Get-Top $check $verified.Player
  $check.BaseStream.Position=$top['Player Funds'].Data
  if($check.ReadInt32() -ne $gold){throw 'Gold verification failed'}
  foreach($key in @('Player Tier','Permanent Tier','Reputation on Rank','Baron Defeated Times','Insured Items')){
   if([Convert]::ToBase64String((Get-Record $check $top[$key])) -cne [Convert]::ToBase64String((Get-Record $old $from[$key]))){throw "Verification failed for $key"}
  }
  $day=Find-HalfTag $check ($verified.Text.Substring(0,$verified.Player.Start)) 'Day Count' 0
  if(!$day){$day=$top['Day Count'];$check.BaseStream.Position=$day.Data}
  if($check.ReadInt32() -ne $days){throw 'Day count verification failed'}
  foreach($key in @('Height_21_0EB204DF4978B92AD0ED188FD32EEC7B','Weight_23_65E4C6534D14653F96EB739F159E58CD','Fat_49_7A3AFCEF42B632594A9904B38CD43768')){
   $null=Find-HalfTag $old $a.Text $key $a.Player.Data
   $null=Find-HalfTag $check $verified.Text $key $verified.Player.Data
   if($old.ReadDouble() -ne $check.ReadDouble()){throw "Body verification failed: $key"}
  }
 }finally{$check.Dispose()}
 if(!$env:HALF_RESTORE_VERIFY){
  $token=[Guid]::NewGuid().ToString('N').Substring(0,8)
  $backup=Join-Path $folder (([IO.Path]::GetFileNameWithoutExtension($livePath)) + ' - before restore ' + (Get-Date -Format 'yyyyMMdd-HHmmss') + "-$token.sav")
  $temporary=Join-Path $folder ('.restore-' + $token + '.tmp')
  try {
   $file=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew)
   try{$file.Write($output,0,$output.Length);$file.Flush($true)}finally{$file.Dispose()}
   $currentHash=[Convert]::ToBase64String($sha.ComputeHash([IO.File]::ReadAllBytes($livePath)))
   if($currentHash -cne $initialHash){throw 'The destination save changed during the restore. Close the game and retry.'}
   [IO.File]::Replace($temporary,$livePath,$backup)
  }finally{
   if(Test-Path -LiteralPath $temporary){Remove-Item -LiteralPath $temporary}
  }
  Write-Host "Restored: $livePath"
  Write-Host "Original destination backed up: $backup"
 }
 Write-Host "Verified body values, insured items, rank, $days days, $defeats Baron defeats, and $gold gold."
}finally{$old.Dispose();$fresh.Dispose();$sha.Dispose()}
