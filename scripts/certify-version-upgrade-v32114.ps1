param(
  [Parameter(Mandatory=$true)]
  [string]$ArtifactRoot,
  [Parameter(Mandatory=$true)]
  [string]$FoundationPath,
  [Parameter(Mandatory=$true)]
  [string]$FrontendPath,
  [Parameter(Mandatory=$true)]
  [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"
$ExpectedRc2InstallerSha = "6d5b378d3c46850c6f55e1046c9880f6fe8fa6b030bc23fc2d4cacddaa5d7d3b"
$ExpectedRc2StandaloneExeSha = "958102dec42e838dc2c89c910dc7383cd681e7baf2801abb5013ba7395831972"
$OldVersion = "0.3.6"
$UpgradeVersion = "0.3.7"
$Product = "CELE Topnotcher OS"

function Sha256([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }
function Section([string]$Title) { Write-Host ""; Write-Host ("=== " + $Title + " ===") }

function Get-CeleUninstallEntry {
  $roots=@(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  $all=@()
  foreach($root in $roots){ try{$all += Get-ItemProperty -Path $root -ErrorAction SilentlyContinue}catch{} }
  $matches=@($all | Where-Object {
    ($_.DisplayName -eq $Product) -or ($_.DisplayName -like "CELE Topnotcher OS*") -or ([string]$_.UninstallString -like "*CELE*Topnotcher*")
  })
  if($matches.Count -eq 0){return $null}
  return @($matches | Sort-Object DisplayVersion -Descending)[0]
}

function Resolve-InstalledExe([object]$Entry) {
  $candidates=New-Object System.Collections.Generic.List[string]
  if($Entry){
    if($Entry.DisplayIcon){
      $icon=[string]$Entry.DisplayIcon
      if($icon.StartsWith('"')){
        $m=[regex]::Match($icon,'^"([^"]+)"')
        if($m.Success){$candidates.Add($m.Groups[1].Value)}
      } else {$candidates.Add(($icon -replace ',\d+$',''))}
    }
    if($Entry.InstallLocation){
      $location=([string]$Entry.InstallLocation).Trim().Trim('"')
      if($location){$candidates.Add((Join-Path $location "CELE-Topnotcher-OS.exe"))}
    }
  }
  $candidates.Add((Join-Path $env:LOCALAPPDATA "CELE Topnotcher OS\CELE-Topnotcher-OS.exe"))
  $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\CELE Topnotcher OS\CELE-Topnotcher-OS.exe"))
  foreach($candidate in $candidates){
    if($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)){return (Resolve-Path -LiteralPath $candidate).Path}
  }
  return $null
}

function Extract-EmbeddedExeHash([string]$Installer,[string]$Dir) {
  $seven=Get-Command 7z.exe -ErrorAction SilentlyContinue
  if(-not $seven){$seven=Get-Command 7z -ErrorAction SilentlyContinue}
  if(-not $seven){throw "7-Zip unavailable."}
  if(Test-Path $Dir){Remove-Item -Recurse -Force $Dir}
  New-Item -ItemType Directory -Force -Path $Dir | Out-Null
  & $seven.Source x "-o$Dir" "-y" $Installer | Out-Null
  if($LASTEXITCODE -ne 0){throw "Could not extract NSIS installer."}
  $hits=@(Get-ChildItem -LiteralPath $Dir -Recurse -File | Where-Object {$_.Name -eq "CELE-Topnotcher-OS.exe"})
  if($hits.Count -ne 1){throw "Expected exactly one embedded CELE executable; found $($hits.Count)."}
  return [ordered]@{path=$hits[0].FullName;bytes=$hits[0].Length;sha256=Sha256 $hits[0].FullName}
}

function Run-Ipc([string]$Exe,[string]$Report,[string]$Label) {
  if(Test-Path $Report){Remove-Item -Force $Report}
  $env:CELE_WEBVIEW_IPC_REPORT=$Report
  try{
    $p=Start-Process -FilePath $Exe -PassThru
    $deadline=(Get-Date).AddSeconds(90)
    while(-not $p.HasExited -and (Get-Date) -lt $deadline){Start-Sleep -Milliseconds 500;$p.Refresh()}
    if(-not $p.HasExited){try{Stop-Process -Id $p.Id -Force}catch{};throw "$Label IPC timeout."}
    $exit=$p.ExitCode
  } finally {Remove-Item Env:CELE_WEBVIEW_IPC_REPORT -ErrorAction SilentlyContinue}
  if(-not (Test-Path $Report)){throw "$Label did not emit IPC report."}
  $r=Get-Content -Raw $Report | ConvertFrom-Json
  $checks=@($r.checks)
  if($r.status -ne "PASS" -or $checks.Count -ne 13 -or @($checks | Where-Object {$_.status -ne "PASS"}).Count -ne 0){
    throw "$Label IPC certificate is not PASS 13/13."
  }
  return [ordered]@{status="PASS";checkCount=13;exitCode=$exit;reportSha256=Sha256 $Report}
}

function Silent-Uninstall([object]$Entry) {
  $cmd=[string]$Entry.QuietUninstallString
  if([string]::IsNullOrWhiteSpace($cmd)){$cmd=[string]$Entry.UninstallString}
  if([string]::IsNullOrWhiteSpace($cmd)){throw "No uninstall command."}
  $m=[regex]::Match($cmd,'^\s*"([^"]+)"\s*(.*)$')
  if($m.Success){$exe=$m.Groups[1].Value;$args=$m.Groups[2].Value}
  else{
    $m=[regex]::Match($cmd,'^\s*(.+?\.exe)\s*(.*)$',[System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if(-not $m.Success){throw "Cannot parse uninstall command: $cmd"}
    $exe=$m.Groups[1].Value.Trim();$args=$m.Groups[2].Value
  }
  if($args -notmatch '(^|\s)/S(\s|$)'){$args=($args+" /S").Trim()}
  $p=Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
  return $p.ExitCode
}

$ArtifactRoot=(Resolve-Path $ArtifactRoot).Path
$FoundationPath=(Resolve-Path $FoundationPath).Path
$FrontendPath=(Resolve-Path $FrontendPath).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory=(Resolve-Path $OutputDirectory).Path

$rc2Installer=Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File -Filter "CELE-Topnotcher-OS-v3.21.12-RC2-unsigned-setup.exe" | Select-Object -First 1
$rc2Exe=Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File -Filter "CELE-Topnotcher-OS-v3.21.12-RC2-unsigned.exe" | Select-Object -First 1
if(-not $rc2Installer -or -not $rc2Exe){throw "Frozen RC2 binaries missing."}
if((Sha256 $rc2Installer.FullName) -ne $ExpectedRc2InstallerSha){throw "Frozen RC2 installer hash mismatch."}
if((Sha256 $rc2Exe.FullName) -ne $ExpectedRc2StandaloneExeSha){throw "Frozen RC2 standalone EXE hash mismatch."}

Section "Prepare 0.3.7 upgrade build from same certified source"
$releaseConfigPath=Join-Path $FoundationPath "src-tauri\tauri.release-ace.conf.json"
if(-not (Test-Path $releaseConfigPath)){throw "Release config missing."}
$cfg=Get-Content -Raw $releaseConfigPath | ConvertFrom-Json
$cfg | Add-Member -NotePropertyName version -NotePropertyValue $UpgradeVersion -Force
$upgradeConfigPath=Join-Path $FoundationPath "src-tauri\tauri.upgrade-test.conf.json"
$cfg | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $upgradeConfigPath -Encoding UTF8

Push-Location $FoundationPath
try{
  npm ci
  if($LASTEXITCODE -ne 0){throw "npm ci failed."}
  $manifest=Join-Path $FrontendPath "ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json"
  python scripts/release_tool.py stage-certification --source $FrontendPath --manifest $manifest
  if($LASTEXITCODE -ne 0){throw "Certified payload staging failed."}
  python scripts/release_tool.py verify
  if($LASTEXITCODE -ne 0){throw "Foundation verify failed."}
  npm run tauri -- build --bundles nsis --config src-tauri/tauri.upgrade-test.conf.json
  if($LASTEXITCODE -ne 0){throw "Upgrade build failed."}
} finally {Pop-Location}

$releaseDir=Join-Path $FoundationPath "src-tauri\target\release"
$upgradeInstaller=Get-ChildItem -LiteralPath (Join-Path $releaseDir "bundle\nsis") -Filter "*.exe" -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
if(-not $upgradeInstaller){throw "0.3.7 NSIS installer missing."}
if((Get-AuthenticodeSignature $upgradeInstaller.FullName).Status -ne [System.Management.Automation.SignatureStatus]::NotSigned){throw "Upgrade test installer unexpectedly signed."}
$upgradeInstallerSha=Sha256 $upgradeInstaller.FullName
$upgradeEmbedded=Extract-EmbeddedExeHash $upgradeInstaller.FullName (Join-Path $env:RUNNER_TEMP "cele-v32114-upgrade-extract")

Section "Install frozen RC2 0.3.6"
if(Get-CeleUninstallEntry){throw "Runner not clean before upgrade test."}
$p=Start-Process -FilePath $rc2Installer.FullName -ArgumentList "/S" -Wait -PassThru
if($p.ExitCode -ne 0){throw "RC2 install failed."}
$oldEntry=$null
for($i=0;$i -lt 30 -and -not $oldEntry;$i++){Start-Sleep -Seconds 1;$oldEntry=Get-CeleUninstallEntry}
if(-not $oldEntry){throw "RC2 uninstall registration missing."}
if([string]$oldEntry.DisplayVersion -ne $OldVersion){throw "Expected RC2 version $OldVersion, found $($oldEntry.DisplayVersion)."}
$oldExe=Resolve-InstalledExe $oldEntry
if(-not $oldExe){throw "RC2 installed EXE missing."}
$oldIpc=Run-Ipc $oldExe (Join-Path $OutputDirectory "pre-upgrade-ipc.json") "pre-upgrade"

Section "Install 0.3.7 over 0.3.6"
$u=Start-Process -FilePath $upgradeInstaller.FullName -ArgumentList "/S" -Wait -PassThru
if($u.ExitCode -ne 0){throw "0.3.7 upgrade installer failed with exit $($u.ExitCode)."}
$newEntry=$null
for($i=0;$i -lt 30;$i++){
  Start-Sleep -Seconds 1
  $candidate=Get-CeleUninstallEntry
  if($candidate -and [string]$candidate.DisplayVersion -eq $UpgradeVersion){$newEntry=$candidate;break}
}
if(-not $newEntry){throw "Windows uninstall registration did not advance to $UpgradeVersion."}
$newExe=Resolve-InstalledExe $newEntry
if(-not $newExe){throw "Upgraded installed EXE missing."}
$newInstalledSha=Sha256 $newExe
if($newInstalledSha -ne $upgradeEmbedded.sha256){throw "Upgraded installed EXE does not match 0.3.7 installer payload."}
$newIpc=Run-Ipc $newExe (Join-Path $OutputDirectory "post-upgrade-ipc.json") "post-upgrade"

Section "Uninstall upgraded app"
$uninstallExit=Silent-Uninstall $newEntry
for($i=0;$i -lt 45;$i++){
  if(-not (Get-CeleUninstallEntry) -and -not (Test-Path $newExe)){break}
  Start-Sleep -Seconds 1
}
$finalEntry=Get-CeleUninstallEntry
$exeRemaining=Test-Path $newExe
$failures=@()
if($finalEntry){$failures+="Uninstall registration remains."}
if($exeRemaining){$failures+="Upgraded EXE remains."}
if($uninstallExit -ne 0){$failures+="Uninstall exit code $uninstallExit."}

$report=[ordered]@{
  schemaVersion=1
  phase="v3.21.14-version-to-version-upgrade-certification"
  status=if($failures.Count -eq 0){"PASS"}else{"FAIL"}
  sourceRc2=[ordered]@{
    version=$OldVersion
    runId=35897863593
    artifactId=10767244775
    installerSha256=$ExpectedRc2InstallerSha
  }
  upgradeCandidate=[ordered]@{
    version=$UpgradeVersion
    installerFile=$upgradeInstaller.Name
    installerBytes=$upgradeInstaller.Length
    installerSha256=$upgradeInstallerSha
    embeddedExecutableSha256=$upgradeEmbedded.sha256
    authenticode="NotSigned"
    sameCertifiedFrontendAndCompiler=$true
    releaseReady=$false
  }
  preUpgrade=[ordered]@{
    displayVersion=[string]$oldEntry.DisplayVersion
    ipc=$oldIpc
  }
  upgrade=[ordered]@{
    installerExitCode=$u.ExitCode
    displayVersionAfter=[string]$newEntry.DisplayVersion
    installedExecutableSha256=$newInstalledSha
    matchedUpgradeInstallerEmbeddedExecutable=$true
    ipc=$newIpc
  }
  uninstall=[ordered]@{
    exitCode=$uninstallExit
    registryEntryRemaining=[bool]$finalEntry
    executableRemaining=[bool]$exeRemaining
  }
  userDataPersistence="NOT_ASSERTED_BY_THIS_TEST"
  filePickerHumanInteraction="NOT_TESTED"
  displayDpiHumanInspection="NOT_TESTED"
  signing="NOT_CONFIGURED"
  failures=$failures
  nativeAdapterQA="pending-manual-desktop-gates"
  releaseReady=$false
}
$out=Join-Path $OutputDirectory "v3.21.14-version-upgrade-report.json"
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $out -Encoding UTF8
Write-Host ($report | ConvertTo-Json -Depth 12)
if($failures.Count -gt 0){throw "v3.21.14 upgrade certification failed."}
Write-Host "v3.21.14 version-to-version upgrade: PASS"
