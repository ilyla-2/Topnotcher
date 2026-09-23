param(
  [Parameter(Mandatory=$true)]
  [string]$FoundationPath,
  [Parameter(Mandatory=$true)]
  [string]$FrontendPath,
  [Parameter(Mandatory=$true)]
  [string]$OutputDirectory,
  [Parameter(Mandatory=$true)]
  [string]$SourceAuditPath,
  [Parameter(Mandatory=$true)]
  [string]$IdentityReportPath
)

$ErrorActionPreference = "Stop"

function Section([string]$Title) {
  Write-Host ""
  Write-Host ("=== " + $Title + " ===")
}

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$FoundationPath = (Resolve-Path -LiteralPath $FoundationPath).Path
$FrontendPath = (Resolve-Path -LiteralPath $FrontendPath).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$SourceAuditPath = (Resolve-Path -LiteralPath $SourceAuditPath).Path
$IdentityReportPath = (Resolve-Path -LiteralPath $IdentityReportPath).Path

$configPath = Join-Path $FoundationPath "src-tauri\tauri.conf.json"
$releaseConfigPath = Join-Path $FoundationPath "src-tauri\tauri.release-ace.conf.json"
$metadataPath = Join-Path $FoundationPath "release\metadata.json"
$config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $releaseConfigPath -PathType Leaf)) {
  throw "RC builder requires the v3.21.9 release overlay config."
}
$releaseConfig = Get-Content -Raw -LiteralPath $releaseConfigPath | ConvertFrom-Json
$metadata = Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json

if ($config.identifier -ne "local.cele.topnotcher.foundation") {
  throw "Certified base identifier changed unexpectedly: $($config.identifier)"
}
if ($releaseConfig.identifier -ne "com.ace.celetopnotcher") {
  throw "RC builder requires release overlay identifier com.ace.celetopnotcher; found $($releaseConfig.identifier)"
}
$releaseWindow = @($releaseConfig.app.windows)[0]
if (-not $releaseWindow -or $releaseWindow.url -ne "payload/CELE_Topnotcher_OS_v3_21_0.html") {
  throw "RC5 requires direct startup into the reviewed CELE v3.21.0 payload."
}
if ($metadata.publisher -ne "ace") {
  throw "RC builder requires publisher brand ace; found $($metadata.publisher)"
}
if ($metadata.signed -eq $true -or $metadata.publicReleaseApproved -eq $true) {
  throw "RC builder refuses metadata that already claims signing/public approval."
}
if ($config.bundle.windows.certificateThumbprint) {
  throw "RC builder expected no configured certificate thumbprint."
}
if ($config.bundle.windows.signCommand) {
  throw "RC builder expected no configured Windows signCommand."
}
if ($releaseConfig.bundle -and $releaseConfig.bundle.windows -and $releaseConfig.bundle.windows.certificateThumbprint) {
  throw "Release overlay unexpectedly configures a certificate thumbprint."
}
if ($releaseConfig.bundle -and $releaseConfig.bundle.windows -and $releaseConfig.bundle.windows.signCommand) {
  throw "Release overlay unexpectedly configures a signCommand."
}

Section "Install exact Node/Tauri dependencies"
Push-Location $FoundationPath
try {
  npm ci
  if ($LASTEXITCODE -ne 0) { throw "npm ci failed." }
} finally {
  Pop-Location
}

Section "Stage exact reviewed frontend using certified release tool"
$manifestPath = Join-Path $FrontendPath "ASTRA_PAYLOAD_MANIFEST_v3_21_0.pending.json"
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "Frozen frontend manifest is missing."
}
Push-Location $FoundationPath
try {
  python scripts/release_tool.py stage-certification --source $FrontendPath --manifest $manifestPath
  if ($LASTEXITCODE -ne 0) { throw "Certified payload staging failed." }
  python scripts/release_tool.py verify
  if ($LASTEXITCODE -ne 0) { throw "Foundation verification failed after payload staging." }
} finally {
  Pop-Location
}

$activePayload = Join-Path $FoundationPath "release\active-payload.json"
$payloadRoute = Join-Path $FoundationPath "app\payload.json"
$payloadDir = Join-Path $FoundationPath "app\payload"
if (-not (Test-Path -LiteralPath $activePayload -PathType Leaf)) { throw "active-payload.json was not produced." }
if (-not (Test-Path -LiteralPath $payloadRoute -PathType Leaf)) { throw "app/payload.json was not produced." }
if (-not (Test-Path -LiteralPath $payloadDir -PathType Container)) { throw "app/payload was not produced." }

$stagedManifest = Get-Content -Raw -LiteralPath $activePayload | ConvertFrom-Json
if ($stagedManifest.files.Count -ne 106) { throw "Patched staged payload file count is not 106." }
foreach ($row in $stagedManifest.files) {
  $sourceFile = Join-Path $FrontendPath $row.path
  $stagedFile = Join-Path $payloadDir $row.path
  if (-not (Test-Path -LiteralPath $stagedFile -PathType Leaf)) { throw "Certified staged runtime missing $($row.path)" }
  if ((Get-Sha256 $sourceFile) -ne (Get-Sha256 $stagedFile)) { throw "Certified staged runtime byte mismatch: $($row.path)" }
}
Write-Host "Release-tool staging verified: 106/106 v3.21.20 payload files; compiler remains frozen."

Section "Build unsigned production-identity Windows RC"
Push-Location $FoundationPath
try {
  npm run tauri -- build --bundles nsis --config src-tauri/tauri.release-ace.conf.json
  if ($LASTEXITCODE -ne 0) { throw "Tauri/NSIS release candidate build failed." }
} finally {
  Pop-Location
}

$releaseDir = Join-Path $FoundationPath "src-tauri\target\release"
$installer = Get-ChildItem -LiteralPath (Join-Path $releaseDir "bundle\nsis") -Filter "*.exe" -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
if (-not $installer) { throw "NSIS installer was not produced." }

$appCandidates = Get-ChildItem -LiteralPath $releaseDir -Filter "*.exe" -File | Where-Object { $_.Length -gt 1MB } | Sort-Object LastWriteTimeUtc -Descending
$appExe = $appCandidates | Select-Object -First 1
if (-not $appExe) { throw "Release application EXE was not produced." }

Section "Verify public-config startup through real WebView2/Tauri IPC"
$releaseIpcReport = Join-Path $OutputDirectory "rc5-release-webview-ipc-report.json"
if (Test-Path -LiteralPath $releaseIpcReport) { Remove-Item -Force -LiteralPath $releaseIpcReport }
$env:CELE_WEBVIEW_IPC_REPORT = $releaseIpcReport
try {
  $ipcProcess = Start-Process -FilePath $appExe.FullName -PassThru
  $deadline = (Get-Date).AddSeconds(90)
  while (-not $ipcProcess.HasExited -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $ipcProcess.Refresh()
  }
  if (-not $ipcProcess.HasExited) {
    try { Stop-Process -Id $ipcProcess.Id -Force -ErrorAction SilentlyContinue } catch {}
    throw "RC5 public-config WebView2/Tauri IPC startup timed out."
  }
} finally {
  Remove-Item Env:CELE_WEBVIEW_IPC_REPORT -ErrorAction SilentlyContinue
}
if (-not (Test-Path -LiteralPath $releaseIpcReport -PathType Leaf)) {
  throw "RC5 public-config startup did not produce an IPC certification report."
}
$ipcReport = Get-Content -Raw -LiteralPath $releaseIpcReport | ConvertFrom-Json
if ($ipcReport.status -ne "PASS") {
  throw "RC5 public-config WebView2/Tauri IPC certification is not PASS."
}
$ipcChecks = @($ipcReport.checks)
if ($ipcChecks.Count -ne 13 -or @($ipcChecks | Where-Object { $_.status -ne "PASS" }).Count -ne 0) {
  throw "RC5 public-config IPC report did not contain 13 passing checks."
}
Write-Host "RC5 public startup routing + WebView2/Tauri IPC: PASS (13/13)."

Section "Verify RC is unsigned as expected"
$installerSig = Get-AuthenticodeSignature -LiteralPath $installer.FullName
$appSig = Get-AuthenticodeSignature -LiteralPath $appExe.FullName
if ($installerSig.Status -ne [System.Management.Automation.SignatureStatus]::NotSigned) {
  throw "Expected unsigned installer, got Authenticode status $($installerSig.Status)"
}
if ($appSig.Status -ne [System.Management.Automation.SignatureStatus]::NotSigned) {
  throw "Expected unsigned application EXE, got Authenticode status $($appSig.Status)"
}

Section "Extract NSIS installer for redistribution scan"
$sevenZip = Get-Command 7z.exe -ErrorAction SilentlyContinue
if (-not $sevenZip) { $sevenZip = Get-Command 7z -ErrorAction SilentlyContinue }
if (-not $sevenZip) { throw "7-Zip is unavailable on the Windows runner; cannot inspect NSIS payload." }

$extractDir = Join-Path $OutputDirectory "installer-extracted"
if (Test-Path -LiteralPath $extractDir) { Remove-Item -Recurse -Force -LiteralPath $extractDir }
New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
& $sevenZip.Source x "-o$extractDir" "-y" $installer.FullName | Out-Host
if ($LASTEXITCODE -ne 0) { throw "7-Zip could not extract the NSIS installer." }

Section "Copy RC binaries and create evidence"
$binariesDir = Join-Path $OutputDirectory "binaries"
New-Item -ItemType Directory -Force -Path $binariesDir | Out-Null
$rcExe = Join-Path $binariesDir "CELE-Topnotcher-OS-v3.21.20-RC5-unsigned.exe"
$rcInstaller = Join-Path $binariesDir "CELE-Topnotcher-OS-v3.21.20-RC5-unsigned-setup.exe"
Copy-Item -LiteralPath $appExe.FullName -Destination $rcExe -Force
Copy-Item -LiteralPath $installer.FullName -Destination $rcInstaller -Force

$toolchain = [ordered]@{
  node = (& node --version | Out-String).Trim()
  npm = (& npm --version | Out-String).Trim()
  rustc = (& rustc --version | Out-String).Trim()
  cargo = (& cargo --version | Out-String).Trim()
}
$toolchain | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutputDirectory "toolchain.json") -Encoding UTF8

Copy-Item -LiteralPath $SourceAuditPath -Destination (Join-Path $OutputDirectory "source-public-package-audit.json") -Force
Copy-Item -LiteralPath $IdentityReportPath -Destination (Join-Path $OutputDirectory "release-identity-overlay.json") -Force

$manifestOut = [ordered]@{
  schemaVersion = 1
  phase = "v3.21.20-ocr-startup-rootfix-rc5"
  releaseCandidate = "RC5"
  releaseType = "UNSIGNED_NOT_FOR_PUBLIC_DISTRIBUTION"
  product = "CELE Topnotcher OS"
  publisherBrand = "ace"
  identifier = "com.ace.celetopnotcher"
  certifiedBaseline = [ordered]@{
    commitSha = "9f5529ee96c4828faa897183182c799101b699f5"
    githubActionsRunId = 35888521612
    runner = "windows-2025"
    compilerSha256 = "3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5"
  }
  executable = [ordered]@{
    file = [System.IO.Path]::GetFileName($rcExe)
    bytes = (Get-Item -LiteralPath $rcExe).Length
    sha256 = Get-Sha256 $rcExe
    authenticodeStatus = "NotSigned"
  }
  installer = [ordered]@{
    file = [System.IO.Path]::GetFileName($rcInstaller)
    bytes = (Get-Item -LiteralPath $rcInstaller).Length
    sha256 = Get-Sha256 $rcInstaller
    authenticodeStatus = "NotSigned"
  }
  sourceAudit = "PASS"
  publicStartupUrl = "payload/CELE_Topnotcher_OS_v3_21_0.html"
  publicStartupWebViewTauriIpc = "PASS_13_OF_13"
  uiInteractionRegression = "PASS_REQUIRED_BY_WORKFLOW"
  publicStartupReportSha256 = Get-Sha256 $releaseIpcReport
  codeSigning = "NOT_CONFIGURED"
  manualDesktopQA = "PENDING"
  finalRedistributionReview = "PENDING"
  publicReleaseApproved = $false
  releaseReady = $false
}
$manifestOut | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutputDirectory "RC_MANIFEST.json") -Encoding UTF8

$readme = @"
CELE Topnotcher OS v3.21.20 RC5

THIS IS AN UNSIGNED RELEASE CANDIDATE.
It is for controlled manual certification only, not public distribution.

Publisher brand: ace
Bundle identifier: com.ace.celetopnotcher

CELE frontend interaction layer patched in v3.21.20; frozen compiler and CELE data/analytics/engineering semantics unchanged.
Automated Windows v3.21.7 baseline: PASS.
Code signing: NOT CONFIGURED.
Manual file-picker/DPI/installed-app QA: PENDING.
Final redistribution approval: PENDING.
releaseReady: false
"@
$readme | Set-Content -LiteralPath (Join-Path $OutputDirectory "README-RC5.txt") -Encoding UTF8

Write-Host "RC application: $rcExe"
Write-Host "RC installer:   $rcInstaller"
Write-Host "RC builder completed; final release remains blocked."
