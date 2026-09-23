param(
  [Parameter(Mandatory=$true)]
  [string]$ArtifactRoot,
  [Parameter(Mandatory=$true)]
  [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$ExpectedInstallerSha = "940c0e68c2097080c8e1e1c2da02d3aca7c018e08214911ad24bf718cadeb753"
$ExpectedExeSha = "baeaeddd1175100741d0c3c6bd1f34454399a4a8636312d9127af44d71faef77"
$ExpectedProduct = "CELE Topnotcher OS"
$ExpectedIdentifier = "com.ace.celetopnotcher"

function Section([string]$Title) {
  Write-Host ""
  Write-Host ("=== " + $Title + " ===")
}
function Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Get-CeleUninstallEntry {
  $roots = @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  $all = @()
  foreach ($root in $roots) {
    try { $all += Get-ItemProperty -Path $root -ErrorAction SilentlyContinue } catch {}
  }
  $matches = @($all | Where-Object {
    ($_.DisplayName -eq $ExpectedProduct) -or
    ($_.DisplayName -like "CELE Topnotcher OS*") -or
    ([string]$_.UninstallString -like "*CELE*Topnotcher*")
  })
  if ($matches.Count -eq 0) { return $null }
  if ($matches.Count -gt 1) { $matches = @($matches | Sort-Object DisplayVersion -Descending) }
  return $matches[0]
}
function Resolve-InstalledExe([object]$Entry) {
  $candidates = New-Object System.Collections.Generic.List[string]
  if ($Entry) {
    if ($Entry.DisplayIcon) {
      $icon = [string]$Entry.DisplayIcon
      if ($icon.StartsWith('"')) {
        $m = [regex]::Match($icon, '^"([^"]+)"')
        if ($m.Success) { $candidates.Add($m.Groups[1].Value) }
      } else {
        $candidates.Add(($icon -replace ',\d+$',''))
      }
    }
    if ($Entry.InstallLocation) {
      $candidates.Add((Join-Path ([string]$Entry.InstallLocation) "CELE-Topnotcher-OS.exe"))
    }
  }
  $candidates.Add((Join-Path $env:LOCALAPPDATA "CELE Topnotcher OS\CELE-Topnotcher-OS.exe"))
  $candidates.Add((Join-Path $env:LOCALAPPDATA "Programs\CELE Topnotcher OS\CELE-Topnotcher-OS.exe"))
  if ($env:ProgramFiles) { $candidates.Add((Join-Path $env:ProgramFiles "CELE Topnotcher OS\CELE-Topnotcher-OS.exe")) }
  $pf86 = [Environment]::GetEnvironmentVariable("ProgramFiles(x86)")
  if ($pf86) { $candidates.Add((Join-Path $pf86 "CELE Topnotcher OS\CELE-Topnotcher-OS.exe")) }
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) {
      return (Resolve-Path -LiteralPath $candidate).Path
    }
  }
  $searchRoots = @($env:LOCALAPPDATA, $env:ProgramFiles)
  if ($pf86) { $searchRoots += $pf86 }
  foreach ($root in $searchRoots) {
    if (-not $root -or -not (Test-Path -LiteralPath $root -PathType Container)) { continue }
    $hit = Get-ChildItem -LiteralPath $root -Filter "CELE-Topnotcher-OS.exe" -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($hit) { return $hit.FullName }
  }
  return $null
}
function Run-InstalledWebViewCertificate([string]$ExePath, [string]$ReportPath, [string]$Label) {
  if (Test-Path -LiteralPath $ReportPath) { Remove-Item -Force -LiteralPath $ReportPath }
  $env:CELE_WEBVIEW_IPC_REPORT = $ReportPath
  try {
    $p = Start-Process -FilePath $ExePath -PassThru
    $deadline = (Get-Date).AddSeconds(90)
    while (-not $p.HasExited -and (Get-Date) -lt $deadline) {
      Start-Sleep -Milliseconds 500
      $p.Refresh()
    }
    if (-not $p.HasExited) {
      try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}
      throw "$Label timed out waiting for installed WebView2/Tauri IPC certificate."
    }
    $exitCode = $p.ExitCode
  } finally {
    Remove-Item Env:CELE_WEBVIEW_IPC_REPORT -ErrorAction SilentlyContinue
  }
  if (-not (Test-Path -LiteralPath $ReportPath -PathType Leaf)) { throw "$Label did not produce a certification report." }
  $report = Get-Content -Raw -LiteralPath $ReportPath | ConvertFrom-Json
  if ($report.status -ne "PASS") { throw "$Label WebView2/Tauri IPC report is not PASS." }
  $checkCount = 0
  $failedChecks = @()
  if ($report.checks) {
    $checkCount = @($report.checks).Count
    foreach ($check in @($report.checks)) {
      if ($check.status -and $check.status -ne "PASS") { $failedChecks += [string]$check.name }
    }
  }
  if ($failedChecks.Count -gt 0) { throw "$Label report contains failed checks: $($failedChecks -join ', ')" }
  return [ordered]@{
    label = $Label
    processExitCode = $exitCode
    reportStatus = [string]$report.status
    phase = [string]$report.phase
    checkCount = $checkCount
    reportSha256 = Sha256 $ReportPath
  }
}
function Invoke-SilentUninstall([object]$Entry) {
  if (-not $Entry) { throw "Cannot uninstall: uninstall registry entry was not found." }
  $command = [string]$Entry.QuietUninstallString
  $usingQuiet = $true
  if ([string]::IsNullOrWhiteSpace($command)) {
    $command = [string]$Entry.UninstallString
    $usingQuiet = $false
  }
  if ([string]::IsNullOrWhiteSpace($command)) { throw "Uninstall registry entry has no uninstall command." }
  $exe = $null
  $args = ""
  $quoted = [regex]::Match($command, '^\s*"([^"]+)"\s*(.*)$')
  if ($quoted.Success) {
    $exe = $quoted.Groups[1].Value
    $args = $quoted.Groups[2].Value
  } else {
    $plain = [regex]::Match($command, '^\s*(.+?\.exe)\s*(.*)$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $plain.Success) { throw "Could not parse uninstall command: $command" }
    $exe = $plain.Groups[1].Value.Trim()
    $args = $plain.Groups[2].Value
  }
  if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Uninstaller executable not found: $exe" }
  if (-not $usingQuiet -and $args -notmatch '(^|\s)/S(\s|$)') { $args = ($args + " /S").Trim() }
  $p = Start-Process -FilePath $exe -ArgumentList $args -Wait -PassThru
  return [ordered]@{ executable = $exe; arguments = $args; exitCode = $p.ExitCode }
}

$ArtifactRoot = (Resolve-Path -LiteralPath $ArtifactRoot).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

$installer = Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File -Filter "CELE-Topnotcher-OS-v3.21.10-RC1-unsigned-setup.exe" | Select-Object -First 1
$portableExe = Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File -Filter "CELE-Topnotcher-OS-v3.21.10-RC1-unsigned.exe" | Select-Object -First 1
if (-not $installer) { throw "Frozen RC1 installer not found in downloaded artifact." }
if (-not $portableExe) { throw "Frozen RC1 application EXE not found in downloaded artifact." }

Section "Verify exact frozen RC1 inputs"
$installerSha = Sha256 $installer.FullName
$exeSha = Sha256 $portableExe.FullName
if ($installerSha -ne $ExpectedInstallerSha) { throw "RC1 installer hash mismatch: $installerSha" }
if ($exeSha -ne $ExpectedExeSha) { throw "RC1 executable hash mismatch: $exeSha" }
if ((Get-AuthenticodeSignature -LiteralPath $installer.FullName).Status -ne [System.Management.Automation.SignatureStatus]::NotSigned) { throw "Frozen RC1 installer signature state changed." }
if ((Get-AuthenticodeSignature -LiteralPath $portableExe.FullName).Status -ne [System.Management.Automation.SignatureStatus]::NotSigned) { throw "Frozen RC1 executable signature state changed." }

$existing = Get-CeleUninstallEntry
if ($existing) { throw "Runner is not clean: CELE Topnotcher OS is already registered before lifecycle test." }

Section "Silent install exact RC1"
$install = Start-Process -FilePath $installer.FullName -ArgumentList "/S" -Wait -PassThru
if ($install.ExitCode -ne 0) { throw "Silent RC1 install failed with exit code $($install.ExitCode)." }

$entry = $null
for ($i=0; $i -lt 30 -and -not $entry; $i++) {
  Start-Sleep -Seconds 1
  $entry = Get-CeleUninstallEntry
}
if (-not $entry) { throw "Installed RC1 did not register an uninstall entry." }

$installedExe = Resolve-InstalledExe $entry
if (-not $installedExe) { throw "Could not locate installed CELE-Topnotcher-OS.exe." }
$installDir = Split-Path -Parent $installedExe
$installedSha = Sha256 $installedExe
if ($installedSha -ne $ExpectedExeSha) { throw "Installed application hash does not match frozen RC1 EXE: $installedSha" }

Section "Launch installed app through real WebView2/Tauri IPC"
$firstReport = Join-Path $OutputDirectory "installed-webview-ipc-first.json"
$firstLaunch = Run-InstalledWebViewCertificate -ExePath $installedExe -ReportPath $firstReport -Label "first-installed-launch"

Section "Same-version silent reinstall/repair"
$repair = Start-Process -FilePath $installer.FullName -ArgumentList "/S" -Wait -PassThru
if ($repair.ExitCode -ne 0) { throw "Silent same-version reinstall failed with exit code $($repair.ExitCode)." }
$entryAfterRepair = Get-CeleUninstallEntry
if (-not $entryAfterRepair) { throw "Uninstall registration disappeared after same-version reinstall." }
$installedExeAfterRepair = Resolve-InstalledExe $entryAfterRepair
if (-not $installedExeAfterRepair) { throw "Installed EXE missing after same-version reinstall." }
if ((Sha256 $installedExeAfterRepair) -ne $ExpectedExeSha) { throw "Installed EXE hash changed after same-version reinstall." }

$secondReport = Join-Path $OutputDirectory "installed-webview-ipc-after-reinstall.json"
$secondLaunch = Run-InstalledWebViewCertificate -ExePath $installedExeAfterRepair -ReportPath $secondReport -Label "post-reinstall-launch"

Section "Silent uninstall"
$uninstall = Invoke-SilentUninstall $entryAfterRepair
for ($i=0; $i -lt 45; $i++) {
  $stillRegistered = Get-CeleUninstallEntry
  $exeStillThere = Test-Path -LiteralPath $installedExeAfterRepair -PathType Leaf
  if (-not $stillRegistered -and -not $exeStillThere) { break }
  Start-Sleep -Seconds 1
}

$finalEntry = Get-CeleUninstallEntry
$exeResidual = Test-Path -LiteralPath $installedExeAfterRepair -PathType Leaf
$installDirResidualFiles = @()
if (Test-Path -LiteralPath $installDir -PathType Container) {
  $installDirResidualFiles = @(Get-ChildItem -LiteralPath $installDir -Force -Recurse -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
}

$failures = @()
if ($finalEntry) { $failures += "Uninstall registry entry remains after silent uninstall." }
if ($exeResidual) { $failures += "Installed executable remains after silent uninstall." }
if ($installDirResidualFiles.Count -gt 0) { $failures += "Install directory contains residual application files after uninstall." }

$report = [ordered]@{
  schemaVersion = 1
  phase = "v3.21.11-installed-app-lifecycle-certification"
  status = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }
  releaseCandidate = [ordered]@{
    sourceRunId = 35894857839
    artifactId = 10767226392
    artifactDigest = "sha256:99b6f92c75e8cf09fca18e14a73b32f9d31242aec68d7290f9229eb0ae0667d8"
    installerSha256 = $installerSha
    executableSha256 = $exeSha
    authenticode = "NotSigned"
  }
  identity = [ordered]@{
    product = $ExpectedProduct
    identifier = $ExpectedIdentifier
    publisherBrand = "ace"
  }
  install = [ordered]@{
    exitCode = $install.ExitCode
    uninstallDisplayName = [string]$entry.DisplayName
    displayVersion = [string]$entry.DisplayVersion
    installedExecutable = $installedExe
    installedExecutableSha256 = $installedSha
    installDirectory = $installDir
  }
  firstInstalledLaunch = $firstLaunch
  sameVersionReinstall = [ordered]@{
    exitCode = $repair.ExitCode
    executableSha256After = Sha256 $installedExeAfterRepair
    launch = $secondLaunch
    note = "This is a same-version reinstall/repair check, not a version-to-version upgrade certification."
  }
  uninstall = [ordered]@{
    command = $uninstall
    registryEntryRemaining = [bool]$finalEntry
    executableRemaining = [bool]$exeResidual
    installDirectoryResidualCount = $installDirResidualFiles.Count
    installDirectoryResiduals = $installDirResidualFiles
  }
  scope = [ordered]@{
    automatedInstall = "PASS"
    automatedInstalledWebViewTauriIpc = "PASS"
    automatedSameVersionReinstall = "PASS"
    automatedUninstall = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }
    versionToVersionUpgrade = "NOT_TESTED"
    filePickerHumanInteraction = "NOT_TESTED"
    displayDpiHumanInspection = "NOT_TESTED"
    signing = "NOT_CONFIGURED"
  }
  failures = $failures
  nativeAdapterQA = "pending-manual-desktop-gates"
  releaseReady = $false
}

$reportPath = Join-Path $OutputDirectory "v3.21.11-installed-app-lifecycle-report.json"
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host ($report | ConvertTo-Json -Depth 12)
if ($failures.Count -gt 0) { throw "Installed-app lifecycle certification failed." }
Write-Host "v3.21.11 automated installed-app lifecycle: PASS"
