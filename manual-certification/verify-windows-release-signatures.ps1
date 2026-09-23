param(
  [Parameter(Mandatory=$true)]
  [string]$InstallerPath,

  [Parameter(Mandatory=$true)]
  [string]$ExecutablePath,

  [Parameter(Mandatory=$false)]
  [string]$ExpectedPublisherSubjectPattern,

  [Parameter(Mandatory=$false)]
  [string]$OutputPath = ".\CELE-v3.21.8-signature-evidence.json"
)

$ErrorActionPreference = "Stop"

function Resolve-ReleaseFile([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Release file not found: $Path"
  }
  return (Resolve-Path -LiteralPath $Path).Path
}

function Inspect-Signature([string]$Path) {
  $resolved = Resolve-ReleaseFile $Path
  $hash = (Get-FileHash -LiteralPath $resolved -Algorithm SHA256).Hash.ToLowerInvariant()
  $sig = Get-AuthenticodeSignature -LiteralPath $resolved

  $record = [ordered]@{
    path = $resolved
    sha256 = $hash
    status = [string]$sig.Status
    statusMessage = [string]$sig.StatusMessage
    signerSubject = if ($sig.SignerCertificate) { $sig.SignerCertificate.Subject } else { $null }
    signerThumbprint = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { $null }
    signerNotBefore = if ($sig.SignerCertificate) { $sig.SignerCertificate.NotBefore.ToUniversalTime().ToString("o") } else { $null }
    signerNotAfter = if ($sig.SignerCertificate) { $sig.SignerCertificate.NotAfter.ToUniversalTime().ToString("o") } else { $null }
    timestampSubject = if ($sig.TimeStamperCertificate) { $sig.TimeStamperCertificate.Subject } else { $null }
    timestampThumbprint = if ($sig.TimeStamperCertificate) { $sig.TimeStamperCertificate.Thumbprint } else { $null }
    timestampPresent = [bool]$sig.TimeStamperCertificate
  }

  if ($sig.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
    throw "Authenticode signature is not Valid: $resolved ($($sig.Status))"
  }
  if (-not $sig.SignerCertificate) {
    throw "No signer certificate: $resolved"
  }
  if (-not $sig.TimeStamperCertificate) {
    throw "No timestamp certificate: $resolved"
  }
  if ($ExpectedPublisherSubjectPattern -and $sig.SignerCertificate.Subject -notmatch $ExpectedPublisherSubjectPattern) {
    throw "Signer subject does not match expected publisher pattern: $resolved"
  }

  return $record
}

$installer = Inspect-Signature $InstallerPath
$executable = Inspect-Signature $ExecutablePath

$signtool = Get-Command signtool.exe -ErrorAction SilentlyContinue
$signtoolResults = @()
if ($signtool) {
  foreach ($p in @($installer.path, $executable.path)) {
    $output = & $signtool.Source verify /pa /all /v $p 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
      throw ("SignTool verification failed for " + $p + [Environment]::NewLine + $output)
    }
    $signtoolResults += [ordered]@{ path=$p; status="PASS"; output=$output }
  }
}

$evidence = [ordered]@{
  schemaVersion = 1
  phase = "v3.21.8-windows-signature-verification"
  verifiedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
  expectedPublisherSubjectPattern = $ExpectedPublisherSubjectPattern
  installer = $installer
  executable = $executable
  signtoolAvailable = [bool]$signtool
  signtool = $signtoolResults
  result = "PASS"
  note = "Signature validity is separate from SmartScreen reputation."
}

$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host "CELE v3.21.8 SIGNATURE VERIFICATION: PASS"
Write-Host "Evidence: $OutputPath"
