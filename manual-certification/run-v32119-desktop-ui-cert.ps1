param(
  [Parameter(Mandatory=$true)]
  [string]$InstallerPath,

  [Parameter(Mandatory=$false)]
  [string]$OutputDirectory = ".\CELE-v3.21.19-manual-desktop-ui-evidence",

  [Parameter(Mandatory=$false)]
  [string]$TesterName = ""
)

$ErrorActionPreference = "Stop"

$ExpectedInstallerSha256 = "7ec4f3db339803f431b7ab081f325c19e17ffc1adbffa28dd8dd1536154696f6"
$ExpectedProduct = "CELE Topnotcher OS"
$ExpectedVersion = "0.3.6"
$ExpectedIdentifier = "com.ace.celetopnotcher"

function Get-Sha256([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Ask-YesNo([string]$Question) {
  while ($true) {
    $answer = (Read-Host "$Question [Y/N]").Trim().ToLowerInvariant()
    if ($answer -in @("y","yes")) { return $true }
    if ($answer -in @("n","no")) { return $false }
    Write-Host "Please answer Y or N."
  }
}

function Ask-Notes([string]$Prompt) {
  return (Read-Host "$Prompt").Trim()
}

function Get-AppEntry {
  $roots=@(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
  )
  $all=@()
  foreach($root in $roots){
    try{$all += Get-ItemProperty -Path $root -ErrorAction SilentlyContinue}catch{}
  }
  $matches=@($all | Where-Object {
    ($_.DisplayName -eq $ExpectedProduct) -or ($_.DisplayName -like "CELE Topnotcher OS*")
  })
  if($matches.Count -eq 0){return $null}
  return @($matches | Sort-Object DisplayVersion -Descending)[0]
}

function Resolve-AppExe([object]$Entry) {
  if($Entry.InstallLocation){
    $location=([string]$Entry.InstallLocation).Trim().Trim('"')
    if($location){
      $p=Join-Path $location "CELE-Topnotcher-OS.exe"
      if(Test-Path -LiteralPath $p -PathType Leaf){return (Resolve-Path -LiteralPath $p).Path}
    }
  }
  if($Entry.DisplayIcon){
    $s=[string]$Entry.DisplayIcon
    $m=[regex]::Match($s,'^\s*"([^"]+)"')
    if($m.Success -and (Test-Path -LiteralPath $m.Groups[1].Value -PathType Leaf)){return $m.Groups[1].Value}
  }
  return $null
}

function Get-SystemDpi {
  if(-not ("NativeDpi" -as [type])){
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class NativeDpi {
  [DllImport("user32.dll")]
  public static extern uint GetDpiForSystem();
}
"@
  }
  $dpi=[NativeDpi]::GetDpiForSystem()
  return [ordered]@{
    dpi=[int]$dpi
    percent=[int][Math]::Round(($dpi / 96.0) * 100.0)
  }
}

function Capture-Screen([string]$Path) {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $bounds=[System.Windows.Forms.SystemInformation]::VirtualScreen
  $bitmap=New-Object System.Drawing.Bitmap $bounds.Width,$bounds.Height
  $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen($bounds.Left,$bounds.Top,0,0,$bounds.Size)
    $bitmap.Save($Path,[System.Drawing.Imaging.ImageFormat]::Png)
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}

$InstallerPath=(Resolve-Path -LiteralPath $InstallerPath).Path
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory=(Resolve-Path -LiteralPath $OutputDirectory).Path
$screens=Join-Path $OutputDirectory "screenshots"
$fixtures=Join-Path $OutputDirectory "fixtures"
New-Item -ItemType Directory -Force -Path $screens,$fixtures | Out-Null

$installerSha=Get-Sha256 $InstallerPath
if($installerSha -ne $ExpectedInstallerSha256){
  throw "Installer SHA-256 mismatch. Expected exact RC4 $ExpectedInstallerSha256, found $installerSha"
}
$signature=Get-AuthenticodeSignature -LiteralPath $InstallerPath
if($signature.Status -ne [System.Management.Automation.SignatureStatus]::NotSigned){
  throw "This kit expects exact unsigned RC4. Signature status is $($signature.Status)."
}

$invalidPdf=Join-Path $fixtures "invalid-not-a-real-pdf.pdf"
"This is deliberately not a PDF. CELE v3.21.19 rejection fixture." | Set-Content -LiteralPath $invalidPdf -Encoding ASCII

Write-Host "Stopping any currently running CELE Topnotcher OS instance before RC4 replacement..."
Get-Process -Name "CELE-Topnotcher-OS" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "Installing exact RC4 silently, even if an older 0.3.6 candidate is already present..."
$p=Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -PassThru
if($p.ExitCode -ne 0){throw "RC4 installation failed with exit code $($p.ExitCode)."}
$entry=$null
for($i=0;$i -lt 30 -and -not $entry;$i++){Start-Sleep -Seconds 1;$entry=Get-AppEntry}
if(-not $entry){throw "CELE Topnotcher OS uninstall registration was not found."}
if([string]$entry.DisplayVersion -ne $ExpectedVersion){
  throw "Expected installed RC4 version $ExpectedVersion, found $($entry.DisplayVersion)."
}
$appExe=Resolve-AppExe $entry
if(-not $appExe){throw "Installed CELE Topnotcher OS executable could not be located."}

$os=Get-CimInstance Win32_OperatingSystem
$computer=Get-CimInstance Win32_ComputerSystem
$video=@(Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution)

if([string]::IsNullOrWhiteSpace($TesterName)){
  $TesterName=Read-Host "Tester name or initials"
}
$started=(Get-Date).ToUniversalTime().ToString("o")

Write-Host ""
Write-Host "Launching CELE Topnotcher OS normally."
Write-Host "This is a human UI certification. The script records evidence; it does not approve the release."
Start-Process -FilePath $appExe | Out-Null
Start-Sleep -Seconds 3

Write-Host ""
Write-Host "=== Sidebar interaction checks ==="
Write-Host "Before testing PDF/OCR, verify the interaction regression that blocked RC2."
Write-Host "Click each sidebar group once to open it, then again to close it."
Write-Host ""

$navigation=[ordered]@{}
$navigation.practice=Ask-YesNo "Does Practice open and close normally?"
$navigation.progress=Ask-YesNo "Does Progress open and close normally?"
$navigation.sources=Ask-YesNo "Does Sources & AI open and close normally?"
$navigation.system=Ask-YesNo "Does System open and close normally?"
$navigation.notes=Ask-Notes "Sidebar interaction notes (press Enter if none)"
$navigationPass=@($navigation.practice,$navigation.progress,$navigation.sources,$navigation.system) -notcontains $false

Write-Host ""
Write-Host "=== Native file-picker checks ==="
Write-Host "Use a harmless NON-PRIVATE valid PDF of your choice for the valid-file checks."
Write-Host "For invalid-file rejection, use:"
Write-Host "  $invalidPdf"
Write-Host ""

$picker=[ordered]@{}
$picker.validPdfPickerOpened=Ask-YesNo "Did the app's source-PDF picker open normally?"
$picker.validPdfImported=Ask-YesNo "After selecting a valid PDF, did the app accept it and show the document/page information without error?"
$picker.pageRendering=Ask-YesNo "Could you render at least two PDF pages (or the available page if one-page) through the native document UI?"
$picker.ocrInteraction=Ask-YesNo "Could you run the available native OCR interaction on the imported document/image region and receive a result?"
$picker.cancelPath=Ask-YesNo "Open the picker again and press Cancel. Did the app remain stable with no unintended import/data mutation?"
$picker.invalidPdfRejected=Ask-YesNo "Try the generated invalid-not-a-real-pdf.pdf fixture. Was it rejected cleanly without a crash?"
$picker.notes=Ask-Notes "File-picker notes (press Enter if none)"

$pickerPass = @(
  $picker.validPdfPickerOpened,
  $picker.validPdfImported,
  $picker.pageRendering,
  $picker.ocrInteraction,
  $picker.cancelPath,
  $picker.invalidPdfRejected
) -notcontains $false

Write-Host ""
Write-Host "=== DPI / display checks ==="
Write-Host "You will test 100%, 125%, 150%, and 200% Windows scaling."
Write-Host "For each level: change Settings > System > Display > Scale, restart the app if Windows/app behavior requires it,"
Write-Host "navigate to a representative CELE study/document screen, then return here."
Write-Host ""

$dpiResults=@()
foreach($target in @(100,125,150,200)){
  Read-Host "Set Windows display scaling to $target%, place CELE Topnotcher OS on the representative screen, then press Enter"
  Start-Sleep -Seconds 2
  $actual=Get-SystemDpi
  $shot=Join-Path $screens ("dpi-" + $target + "-percent.png")
  Capture-Screen $shot

  $checks=[ordered]@{
    targetPercent=$target
    measuredDpi=$actual.dpi
    measuredPercent=$actual.percent
    screenshot=[IO.Path]::GetFileName($shot)
    screenshotSha256=Get-Sha256 $shot
    noClippedText=Ask-YesNo "At $target%, is critical text readable without clipping?"
    navigationReachable=Ask-YesNo "At $target%, are sidebar/navigation controls reachable and usable?"
    dialogsUsable=Ask-YesNo "At $target%, are dialogs/modals fully visible with their action buttons reachable?"
    studyPagesUsable=Ask-YesNo "At $target%, are representative study/dashboard pages usable without destructive overlap?"
    documentUiUsable=Ask-YesNo "At $target%, is the PDF/document/OCR interface usable without inaccessible controls?"
    horizontalOverflowAcceptable=Ask-YesNo "At $target%, is there no release-blocking unintended horizontal overflow?"
  }
  $checks.notes=Ask-Notes "Notes for $target% (press Enter if none)"
  $dpiResults += $checks
}

$dpiPass=$true
foreach($r in $dpiResults){
  foreach($name in @("noClippedText","navigationReachable","dialogsUsable","studyPagesUsable","documentUiUsable","horizontalOverflowAcceptable")){
    if($r[$name] -ne $true){$dpiPass=$false}
  }
}

$overall = if($navigationPass -and $pickerPass -and $dpiPass){"COMPLETE_PASS_CANDIDATE"}else{"COMPLETE_WITH_FAILURES"}

$report=[ordered]@{
  schemaVersion=1
  phase="v3.21.19-manual-desktop-ui-certification"
  status=$overall
  approval="NOT_AUTOMATIC"
  tester=[ordered]@{
    name=$TesterName
    startedAtUtc=$started
    completedAtUtc=(Get-Date).ToUniversalTime().ToString("o")
  }
  releaseCandidate=[ordered]@{
    rc="v3.21.18-RC4"
    product=$ExpectedProduct
    version=$ExpectedVersion
    identifier=$ExpectedIdentifier
    installerSha256=$installerSha
    authenticodeStatus=[string]$signature.Status
  }
  environment=[ordered]@{
    computerName=$env:COMPUTERNAME
    osCaption=$os.Caption
    osVersion=$os.Version
    osBuild=$os.BuildNumber
    osArchitecture=$os.OSArchitecture
    manufacturer=$computer.Manufacturer
    model=$computer.Model
    video=$video
  }
  sidebarInteraction=[ordered]@{
    result=if($navigationPass){"PASS_CANDIDATE"}else{"FAIL"}
    checks=$navigation
  }
  nativeFilePicker=[ordered]@{
    result=if($pickerPass){"PASS_CANDIDATE"}else{"FAIL"}
    checks=$picker
  }
  displayAndDpi=[ordered]@{
    result=if($dpiPass){"PASS_CANDIDATE"}else{"FAIL"}
    checks=$dpiResults
  }
  remainingNonUiReleaseGates=@(
    "Authenticode code signing",
    "final redistribution review of signed release package"
  )
  nativeAdapterQA="pending-human-review-of-this-evidence"
  releaseReady=$false
}

$reportPath=Join-Path $OutputDirectory "v3.21.19-manual-desktop-ui-report.json"
$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$hashes=@()
Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse | Sort-Object FullName | ForEach-Object {
  $hashes += [ordered]@{
    path=$_.FullName.Substring($OutputDirectory.Length).TrimStart('\','/')
    bytes=$_.Length
    sha256=Get-Sha256 $_.FullName
  }
}
$hashPath=Join-Path $OutputDirectory "EVIDENCE_SHA256.json"
$hashes | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $hashPath -Encoding UTF8

$zip=$OutputDirectory.TrimEnd('\') + ".zip"
if(Test-Path $zip){Remove-Item -Force $zip}
Compress-Archive -Path (Join-Path $OutputDirectory "*") -DestinationPath $zip -CompressionLevel Optimal

Write-Host ""
Write-Host "=== Manual desktop UI evidence complete ==="
Write-Host "Status: $overall"
Write-Host "Evidence folder: $OutputDirectory"
Write-Host "Evidence ZIP: $zip"
Write-Host "ZIP SHA-256: $(Get-Sha256 $zip)"
Write-Host ""
Write-Host "This result is a candidate for review only. It does NOT set nativeAdapterQA=approved or releaseReady=true."
