param(
  [Parameter(Mandatory=$true)]
  [string]$InstallerPath,

  [Parameter(Mandatory=$false)]
  [string]$ExecutablePath,

  [Parameter(Mandatory=$false)]
  [string]$OutputDirectory = ".\CELE-v3.21.8-manual-evidence"
)

$ErrorActionPreference = "Stop"

function Get-Sha256([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "File not found: $Path"
  }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-SignatureRecord([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    return $null
  }
  $sig = Get-AuthenticodeSignature -LiteralPath $Path
  return [ordered]@{
    path = (Resolve-Path -LiteralPath $Path).Path
    status = [string]$sig.Status
    statusMessage = [string]$sig.StatusMessage
    signerSubject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { $null }
    signerThumbprint = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { $null }
    timeStamperSubject = if ($sig.TimeStamperCertificate) { $sig.TimeStamperCertificate.Subject } else { $null }
    timeStamperThumbprint = if ($sig.TimeStamperCertificate) { $sig.TimeStamperCertificate.Thumbprint } else { $null }
  }
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path

$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$display = Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution

$installerResolved = (Resolve-Path -LiteralPath $InstallerPath).Path
$installerHash = Get-Sha256 $installerResolved
$exeResolved = $null
$exeHash = $null
if ($ExecutablePath) {
  $exeResolved = (Resolve-Path -LiteralPath $ExecutablePath).Path
  $exeHash = Get-Sha256 $exeResolved
}

$record = [ordered]@{
  schemaVersion = 1
  phase = "v3.21.8-manual-release-evidence"
  capturedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  automatedBaseline = [ordered]@{
    commitSha = "9f5529ee96c4828faa897183182c799101b699f5"
    githubActionsRunId = 35888521612
    runner = "windows-2025"
    evidenceArtifactSha256 = "bb9832fbeafe895c7fe439e65511b59dfec78a3b5408e2e31ab2189979a07002"
    frozenCompilerSha256 = "3133e9ea5259afd12dfc8f2ba7b7cc3cdc8b4e2b089ad86bad40936e504d0ef5"
  }
  environment = [ordered]@{
    computerName = $env:COMPUTERNAME
    osCaption = $os.Caption
    osVersion = $os.Version
    osBuildNumber = $os.BuildNumber
    architecture = $os.OSArchitecture
    manufacturer = $cs.Manufacturer
    model = $cs.Model
    displays = @($display)
  }
  files = [ordered]@{
    installer = [ordered]@{
      path = $installerResolved
      sha256 = $installerHash
      authenticode = Get-SignatureRecord $installerResolved
    }
    executable = if ($exeResolved) {
      [ordered]@{
        path = $exeResolved
        sha256 = $exeHash
        authenticode = Get-SignatureRecord $exeResolved
      }
    } else { $null }
  }
  manualChecks = [ordered]@{
    nativeFilePicker = [ordered]@{
      status = "PENDING"
      notes = ""
      evidenceRefs = @()
    }
    displayAndDpi = [ordered]@{
      status = "PENDING"
      testedScaling = @("100%","125%","150%","200%")
      notes = ""
      evidenceRefs = @()
    }
    installedAppLifecycle = [ordered]@{
      status = "PENDING"
      notes = ""
      evidenceRefs = @()
    }
    codeSigning = [ordered]@{
      status = "PENDING"
      notes = "Use the captured Authenticode records; APPROVED requires the intended publisher certificate and valid timestamp."
      evidenceRefs = @()
    }
    redistributionReview = [ordered]@{
      status = "PENDING"
      notes = ""
      evidenceRefs = @()
    }
  }
  tester = [ordered]@{
    name = ""
    reviewedAtUtc = $null
  }
}

$jsonPath = Join-Path $OutputDirectory "manual-evidence.json"
$record | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$readme = @"
CELE Topnotcher OS v3.21.8 Manual Evidence Folder

Generated: $($record.capturedAtUtc)

This collector DOES NOT approve any manual gate.
It captures the machine, installer/executable hashes, and Authenticode state.

Complete the five manual checks described in:
docs/V3_21_8_MANUAL_RELEASE_GATE.md

Then add evidence references (screenshots, recordings, logs) to manual-evidence.json.
Do not change a status to APPROVED unless the check was actually performed.
"@

$readme | Set-Content -LiteralPath (Join-Path $OutputDirectory "README.txt") -Encoding UTF8

Write-Host "Evidence skeleton created:"
Write-Host "  $jsonPath"
Write-Host "Installer SHA-256: $installerHash"
if ($exeHash) { Write-Host "Executable SHA-256: $exeHash" }
Write-Host "No manual gate was auto-approved."
