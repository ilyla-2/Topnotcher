param(
  [Parameter(Mandatory=$true)]
  [string]$ArtifactRoot,
  [Parameter(Mandatory=$true)]
  [string]$OutputDirectory
)

$ErrorActionPreference = "Stop"

$ExpectedInstallerSha = "6d5b378d3c46850c6f55e1046c9880f6fe8fa6b030bc23fc2d4cacddaa5d7d3b"
$ExpectedExeSha = "958102dec42e838dc2c89c910dc7383cd681e7baf2801abb5013ba7395831972"
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
      $location = ([string]$Entry.InstallLocation).Trim().Trim('"')
      if ($location) {
        $candidates.Add((Join-Path $location "CELE-Topnotcher-OS.exe"))
      }
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

$installer = Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File -Filter "CELE-Topnotcher-OS-v3.21.12-RC2-unsigned-setup.exe" | Select-Object -First 1
$portableExe = Get-ChildItem -LiteralPath $ArtifactRoot -Recurse -File -Filter "CELE-Topnotcher-OS-v3.21.12-RC2-unsigned.exe" | Select-Object -First 1
if (-not $installer) { throw "Frozen RC2 installer not found in downloaded artifact." }
if (-not $portableExe) { throw "Frozen RC2 application EXE not found in downloaded artifact." }

Section "Verify exact frozen RC2 inputs"
$installerSha = Sha256 $installer.FullName
$exeSha = Sha256 $portableExe.FullName
if ($installerSha -ne $ExpectedInstallerSha) { throw "RC2 installer hash mismatch: $installerSha" }
if ($exeSha -ne $ExpectedExeSha) { throw "RC2 executable hash mismatch: $exeSha" }
if ((Get-AuthenticodeSignature -LiteralPath $installer.FullName).Status -ne [System.Management.Automation.SignatureStatus]::NotSigned) { throw "Frozen RC2 installer signature state changed." }
if ((Get-AuthenticodeSignature -LiteralPath $portableExe.FullName).Status -ne [System.Management.Automation.SignatureStatus]::NotSigned) { throw "Frozen RC2 executable signature state changed." }

Section "Resolve executable bytes embedded in exact NSIS installer"
$sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
if (-not $sevenZip) { $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue }
if (-not $sevenZip) { throw "7-Zip is unavailable; cannot verify installer-embedded application bytes." }
$nsisExtract = Join-Path $env:RUNNER_TEMP "cele-v32113-nsis-extracted"
if (Test-Path -LiteralPath $nsisExtract) { Remove-Item -Recurse -Force -LiteralPath $nsisExtract }
New-Item -ItemType Directory -Force -Path $nsisExtract | Out-Null
& $sevenZip.Source x "-o$nsisExtract" "-y" $installer.FullName | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Could not extract frozen RC2 NSIS installer." }
$embeddedExeFiles = @(Get-ChildItem -LiteralPath $nsisExtract -Recurse -File -ErrorAction Stop | Where-Object { $_.Name -eq "CELE-Topnotcher-OS.exe" })
if ($embeddedExeFiles.Count -eq 0) { throw "NSIS extraction did not expose CELE-Topnotcher-OS.exe." }
$embeddedExeRecords = @()
$embeddedHashes = New-Object System.Collections.Generic.HashSet[string]
foreach ($f in $embeddedExeFiles) {
  $h = Sha256 $f.FullName
  [void]$embeddedHashes.Add($h)
  $embeddedExeRecords += [ordered]@{
    relativePath = $f.FullName.Substring($nsisExtract.Length).TrimStart('\','/')
    bytes = $f.Length
    sha256 = $h
  }
}
Write-Host "NSIS embedded application hashes: $($embeddedHashes -join ', ')"

$existing = Get-CeleUninstallEntry
if ($existing) { throw "Runner is not clean: CELE Topnotcher OS is already registered before lifecycle test." }

Section "Silent install exact RC2"
$install = Start-Process -FilePath $installer.FullName -ArgumentList "/S" -Wait -PassThru
if ($install.ExitCode -ne 0) { throw "Silent RC2 install failed with exit code $($install.ExitCode)." }

$entry = $null
for ($i=0; $i -lt 30 -and -not $entry; $i++) {
  Start-Sleep -Seconds 1
  $entry = Get-CeleUninstallEntry
}
if (-not $entry) { throw "Installed RC2 did not register an uninstall entry." }

$installedExe = Resolve-InstalledExe $entry
if (-not $installedExe) { throw "Could not locate installed CELE-Topnotcher-OS.exe." }
$installDir = Split-Path -Parent $installedExe
$installedSha = Sha256 $installedExe
if (-not $embeddedHashes.Contains($installedSha)) {
  throw "Installed application hash is not present in the exact frozen NSIS payload: $installedSha"
}

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
$installedShaAfterRepair = Sha256 $installedExeAfterRepair
if ($installedShaAfterRepair -ne $installedSha) { throw "Installed EXE hash changed after same-version reinstall." }
if (-not $embeddedHashes.Contains($installedShaAfterRepair)) { throw "Reinstalled EXE does not match exact frozen NSIS payload." }

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
  phase = "v3.21.13-installed-rc2-lifecycle-certification"
  status = if ($failures.Count -eq 0) { "PASS" } else { "FAIL" }
  releaseCandidate = [ordered]@{
    sourceRunId = 35897863593
    artifactId = 10767244775
    artifactDigest = "sha256:12c160beb5959ae93144ee3a8ca05abade210d6403724f381a0baeec2cb255ce"
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
    standaloneRcExecutableSha256 = $exeSha
    embeddedInstallerExecutables = $embeddedExeRecords
    installedMatchesEmbeddedInstallerExecutable = $true
    standaloneAndInstalledByteIdentical = ($installedSha -eq $exeSha)
    installDirectory = $installDir
  }
  firstInstalledLaunch = $firstLaunch
  sameVersionReinstall = [ordered]@{
    exitCode = $repair.ExitCode
    executableSha256After = $installedShaAfterRepair
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

$reportPath = Join-Path $OutputDirectory "v3.21.13-installed-rc2-lifecycle-report.json"
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host ($report | ConvertTo-Json -Depth 12)
if ($failures.Count -gt 0) { throw "Installed-app lifecycle certification failed." }
Write-Host "v3.21.13 automated installed RC2 lifecycle: PASS"
