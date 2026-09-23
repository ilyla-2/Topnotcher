param(
  [Parameter(Mandatory=$true)][string]$Rc2ArtifactRoot,
  [Parameter(Mandatory=$true)][string]$FoundationPath,
  [Parameter(Mandatory=$true)][string]$FrontendPath,
  [Parameter(Mandatory=$true)][string]$OutputDirectory
)

$ErrorActionPreference="Stop"
$Rc2InstallerSha="6d5b378d3c46850c6f55e1046c9880f6fe8fa6b030bc23fc2d4cacddaa5d7d3b"
$Product="CELE Topnotcher OS"

function Sha([string]$p){(Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLowerInvariant()}
function Get-AppEntry {
  $roots=@(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  $a=@()
  foreach($r in $roots){try{$a+=Get-ItemProperty -Path $r -ErrorAction SilentlyContinue}catch{}}
  @($a|Where-Object{$_.DisplayName -eq $Product -or $_.DisplayName -like "CELE Topnotcher OS*"})|Select-Object -First 1
}
function Resolve-AppExe($entry){
  $loc=([string]$entry.InstallLocation).Trim().Trim('"')
  if($loc){
    $p=Join-Path $loc "CELE-Topnotcher-OS.exe"
    if(Test-Path -LiteralPath $p -PathType Leaf){return (Resolve-Path $p).Path}
  }
  if($entry.DisplayIcon){
    $s=[string]$entry.DisplayIcon
    $m=[regex]::Match($s,'^\s*"([^"]+)"')
    if($m.Success -and (Test-Path -LiteralPath $m.Groups[1].Value -PathType Leaf)){return $m.Groups[1].Value}
  }
  return $null
}
function Run-IpcCert([string]$exe,[string]$reportPath){
  if(Test-Path $reportPath){Remove-Item -Force $reportPath}
  $env:CELE_WEBVIEW_IPC_REPORT=$reportPath
  try{
    $p=Start-Process -FilePath $exe -PassThru
    $deadline=(Get-Date).AddSeconds(90)
    while(-not $p.HasExited -and (Get-Date)-lt $deadline){Start-Sleep -Milliseconds 500;$p.Refresh()}
    if(-not $p.HasExited){Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue;throw "IPC certificate timed out"}
    $exit=$p.ExitCode
  }finally{Remove-Item Env:CELE_WEBVIEW_IPC_REPORT -ErrorAction SilentlyContinue}
  if(-not(Test-Path $reportPath)){throw "IPC report missing"}
  $r=Get-Content -Raw $reportPath|ConvertFrom-Json
  if($r.status -ne "PASS"){throw "IPC report is not PASS"}
  $checks=@($r.checks)
  if($checks.Count -ne 13 -or @($checks|Where-Object{$_.status -ne "PASS"}).Count -ne 0){throw "IPC report is not 13/13 PASS"}
  [ordered]@{status="PASS";checks=13;exitCode=$exit;reportSha256=Sha $reportPath}
}
function Find-DataRoot {
  $hits=@()
  foreach($root in @($env:APPDATA,$env:LOCALAPPDATA)){
    if(-not $root -or -not(Test-Path $root)){continue}
    try{$hits+=Get-ChildItem -LiteralPath $root -Directory -Filter "Topnotcher Data" -Recurse -ErrorAction SilentlyContinue}catch{}
  }
  $hits|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
}
function Snapshot-Tree([string]$root){
  $map=[ordered]@{}
  Get-ChildItem -LiteralPath $root -File -Recurse -ErrorAction Stop|Sort-Object FullName|ForEach-Object{
    $rel=$_.FullName.Substring($root.Length).TrimStart('\','/')
    $map[$rel]=[ordered]@{bytes=$_.Length;sha256=Sha $_.FullName}
  }
  return $map
}
function Maps-Equal($a,$b){
  $ja=$a|ConvertTo-Json -Depth 10 -Compress
  $jb=$b|ConvertTo-Json -Depth 10 -Compress
  return $ja -eq $jb
}
function Silent-Uninstall($entry){
  $cmd=[string]$entry.QuietUninstallString
  $quiet=$true
  if([string]::IsNullOrWhiteSpace($cmd)){$cmd=[string]$entry.UninstallString;$quiet=$false}
  $m=[regex]::Match($cmd,'^\s*"([^"]+)"\s*(.*)$')
  if($m.Success){$exe=$m.Groups[1].Value;$args=$m.Groups[2].Value}else{
    $m=[regex]::Match($cmd,'^\s*(.+?\.exe)\s*(.*)$',[Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if(-not$m.Success){throw "Cannot parse uninstall command"}
    $exe=$m.Groups[1].Value.Trim();$args=$m.Groups[2].Value
  }
  if(-not$quiet -and $args -notmatch '(^|\s)/S(\s|$)'){$args=($args+" /S").Trim()}
  $p=Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
  if($p.ExitCode -ne 0){throw "Uninstall failed: $($p.ExitCode)"}
}

$Rc2ArtifactRoot=(Resolve-Path $Rc2ArtifactRoot).Path
$FoundationPath=(Resolve-Path $FoundationPath).Path
$FrontendPath=(Resolve-Path $FrontendPath).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory|Out-Null
$OutputDirectory=(Resolve-Path $OutputDirectory).Path

$rc2Installer=Get-ChildItem $Rc2ArtifactRoot -Recurse -File -Filter "CELE-Topnotcher-OS-v3.21.12-RC2-unsigned-setup.exe"|Select-Object -First 1
if(-not$rc2Installer){throw "Exact RC2 installer missing"}
if((Sha $rc2Installer.FullName)-ne $Rc2InstallerSha){throw "RC2 installer hash mismatch"}

Write-Host "=== Build certification-only 0.3.7 upgrade package ==="
Push-Location $FoundationPath
try{
  npm ci
  if($LASTEXITCODE -ne 0){throw "npm ci failed"}
  $manifest=Join-Path $FrontendPath "ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json"
  python scripts/release_tool.py stage-certification --source $FrontendPath --manifest $manifest
  if($LASTEXITCODE -ne 0){throw "payload staging failed"}

  $releaseCfg=Get-Content -Raw "src-tauri/tauri.release-ace.conf.json"|ConvertFrom-Json
  if($releaseCfg.identifier -ne "com.ace.celetopnotcher"){throw "upgrade config identifier mismatch"}
  if(@($releaseCfg.app.windows)[0].url -ne "payload/CELE_Topnotcher_OS_v3_21_0.html"){throw "upgrade config startup mismatch"}
  $releaseCfg|Add-Member -NotePropertyName version -NotePropertyValue "0.3.7" -Force
  $upgradeCfg="src-tauri/tauri.upgrade-cert-v32114.conf.json"
  $releaseCfg|ConvertTo-Json -Depth 20|Set-Content -LiteralPath $upgradeCfg -Encoding UTF8

  npm run tauri -- build --bundles nsis --config $upgradeCfg
  if($LASTEXITCODE -ne 0){throw "0.3.7 upgrade installer build failed"}
}finally{Pop-Location}

$bundleDir=Join-Path $FoundationPath "src-tauri\target\release\bundle\nsis"
$upgradeInstaller=Get-ChildItem $bundleDir -File -Filter "*.exe"|Sort-Object LastWriteTimeUtc -Descending|Select-Object -First 1
if(-not$upgradeInstaller){throw "0.3.7 upgrade installer missing"}
if($upgradeInstaller.Name -notmatch "0\.3\.7"){throw "Upgrade installer filename does not identify 0.3.7: $($upgradeInstaller.Name)"}
if((Get-AuthenticodeSignature $upgradeInstaller.FullName).Status -ne [Management.Automation.SignatureStatus]::NotSigned){throw "Upgrade certification installer unexpectedly signed"}

$seven=Get-Command 7z.exe -ErrorAction SilentlyContinue;if(-not$seven){$seven=Get-Command 7z -ErrorAction Stop}
$extract=Join-Path $env:RUNNER_TEMP "cele-v32114-upgrade-extract"
if(Test-Path $extract){Remove-Item -Recurse -Force $extract}
New-Item -ItemType Directory -Force $extract|Out-Null
& $seven.Source x "-o$extract" "-y" $upgradeInstaller.FullName|Out-Null
if($LASTEXITCODE -ne 0){throw "Upgrade installer extraction failed"}
$embedded=Get-ChildItem $extract -Recurse -File|Where-Object{$_.Name -eq "CELE-Topnotcher-OS.exe"}|Select-Object -First 1
if(-not$embedded){throw "Upgrade installer embedded EXE missing"}
$upgradeEmbeddedSha=Sha $embedded.FullName

Write-Host "=== Install exact frozen RC2 0.3.6 ==="
if(Get-AppEntry){throw "Runner not clean before upgrade certification"}
$p=Start-Process $rc2Installer.FullName -ArgumentList "/S" -Wait -PassThru
if($p.ExitCode -ne 0){throw "RC2 install failed"}
$entry=$null
for($i=0;$i-lt30-and-not$entry;$i++){Start-Sleep 1;$entry=Get-AppEntry}
if(-not$entry){throw "RC2 uninstall registration missing"}
if([string]$entry.DisplayVersion -ne "0.3.6"){throw "Expected installed RC2 DisplayVersion 0.3.6, found $($entry.DisplayVersion)"}
$exe=Resolve-AppExe $entry;if(-not$exe){throw "RC2 installed EXE missing"}

$preReport=Join-Path $OutputDirectory "pre-upgrade-ipc.json"
$preLaunch=Run-IpcCert $exe $preReport

$dataRoot=Find-DataRoot
if(-not$dataRoot){throw "Native Topnotcher Data root not found after RC2 IPC run"}
$before=Snapshot-Tree $dataRoot.FullName
if($before.Count -eq 0){throw "Native data root is empty before upgrade"}

Write-Host "=== Upgrade 0.3.6 -> certification-only 0.3.7 ==="
$up=Start-Process $upgradeInstaller.FullName -ArgumentList "/S" -Wait -PassThru
if($up.ExitCode -ne 0){throw "0.3.7 upgrade install failed"}
$entry2=$null
for($i=0;$i-lt30-and-not$entry2;$i++){Start-Sleep 1;$entry2=Get-AppEntry}
if(-not$entry2){throw "Upgrade uninstall registration missing"}
if([string]$entry2.DisplayVersion -ne "0.3.7"){throw "Upgrade did not move DisplayVersion to 0.3.7; found $($entry2.DisplayVersion)"}
$exe2=Resolve-AppExe $entry2;if(-not$exe2){throw "Upgraded installed EXE missing"}
$installedUpgradeSha=Sha $exe2
if($installedUpgradeSha -ne $upgradeEmbeddedSha){throw "Upgraded installed EXE does not match exact upgrade installer payload"}

$dataRootAfter=Find-DataRoot
if(-not$dataRootAfter){throw "Native data root disappeared during installer upgrade"}
if($dataRootAfter.FullName -ne $dataRoot.FullName){throw "Native data root moved unexpectedly during upgrade"}
$afterInstall=Snapshot-Tree $dataRootAfter.FullName
if(-not(Maps-Equal $before $afterInstall)){throw "Native data changed during installer upgrade before upgraded app launch"}

$postReport=Join-Path $OutputDirectory "post-upgrade-ipc.json"
$postLaunch=Run-IpcCert $exe2 $postReport

Write-Host "=== Uninstall upgraded build ==="
$installDir=Split-Path -Parent $exe2
Silent-Uninstall $entry2
for($i=0;$i-lt45;$i++){
  if(-not(Get-AppEntry)-and-not(Test-Path $exe2)){break}
  Start-Sleep 1
}
$regRemaining=[bool](Get-AppEntry)
$exeRemaining=Test-Path $exe2
$residual=@()
if(Test-Path $installDir){$residual=@(Get-ChildItem $installDir -Recurse -Force -ErrorAction SilentlyContinue)}
if($regRemaining -or $exeRemaining -or $residual.Count -gt 0){throw "Upgrade uninstall left application residuals"}

$report=[ordered]@{
  schemaVersion=1
  phase="v3.21.14-version-to-version-upgrade-certification"
  status="PASS"
  baseline=[ordered]@{
    version="0.3.6"
    rc2RunId=35897863593
    rc2ArtifactId=10767244775
    rc2InstallerSha256=$Rc2InstallerSha
  }
  upgrade=[ordered]@{
    certificationVersion="0.3.7"
    identifier="com.ace.celetopnotcher"
    startupUrl="payload/CELE_Topnotcher_OS_v3_21_0.html"
    installerFile=$upgradeInstaller.Name
    installerSha256=Sha $upgradeInstaller.FullName
    embeddedExecutableSha256=$upgradeEmbeddedSha
    installedExecutableSha256=$installedUpgradeSha
    displayVersionAfter="0.3.7"
  }
  nativeDataPreservation=[ordered]@{
    root=$dataRoot.FullName
    filesBefore=$before.Count
    exactTreeUnchangedBeforeUpgradedLaunch=$true
  }
  preUpgradeLaunch=$preLaunch
  postUpgradeLaunch=$postLaunch
  uninstall=[ordered]@{
    registryEntryRemaining=$regRemaining
    executableRemaining=$exeRemaining
    installDirectoryResidualCount=$residual.Count
  }
  scope=[ordered]@{
    versionToVersionUpgrade="PASS"
    nativeDataPreservationAcrossInstallerUpgrade="PASS"
    upgradedWebViewTauriIpc="PASS_13_OF_13"
    upgradedUninstall="PASS"
    note="0.3.7 is certification-only and is not a public release."
  }
  signing="NOT_CONFIGURED"
  nativeAdapterQA="pending-manual-desktop-gates"
  releaseReady=$false
}
$reportPath=Join-Path $OutputDirectory "v3.21.14-upgrade-report.json"
$report|ConvertTo-Json -Depth 20|Set-Content $reportPath -Encoding UTF8
$report|ConvertTo-Json -Depth 20|Write-Host
