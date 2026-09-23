param(
  [Parameter(Mandatory=$true)]
  [string]$InstallerPath,

  [Parameter(Mandatory=$false)]
  [string]$OutputDirectory = ".\CELE-v3.21.21-RC5-preboard-retest-evidence",

  [Parameter(Mandatory=$false)]
  [string]$TesterName = ""
)

$ErrorActionPreference = "Stop"

$ExpectedInstallerSha256 = "9e6ffb1a8a04fea43087a7eb13dab55721d5cfbbf3d5ed816bb71a190fea85da"
$ExpectedProduct = "CELE Topnotcher OS"
$ExpectedVersion = "0.3.6"
$ExpectedIdentifier = "com.ace.celetopnotcher"
$MonitorSeconds = 90
$HangThresholdSamples = 5

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

function Get-UiProcess([int]$Pid) {
  try {
    $p=Get-Process -Id $Pid -ErrorAction Stop
    $p.Refresh()
    return $p
  } catch {
    return $null
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
  throw "Installer SHA-256 mismatch. Expected exact RC5 $ExpectedInstallerSha256, found $installerSha"
}
$signature=Get-AuthenticodeSignature -LiteralPath $InstallerPath
if($signature.Status -ne [System.Management.Automation.SignatureStatus]::NotSigned){
  throw "This kit expects exact unsigned RC5. Signature status is $($signature.Status)."
}

$invalidPdf=Join-Path $fixtures "invalid-not-a-real-pdf.pdf"
"This is deliberately not a PDF. CELE v3.21.21 rejection fixture." | Set-Content -LiteralPath $invalidPdf -Encoding ASCII

Write-Host ""
Write-Host "Stopping any currently running CELE Topnotcher OS instance..."
Get-Process -Name "CELE-Topnotcher-OS" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1

Write-Host "Installing exact RC5 silently, even if another 0.3.6 candidate is installed..."
$install=Start-Process -FilePath $InstallerPath -ArgumentList "/S" -Wait -PassThru
if($install.ExitCode -ne 0){throw "RC5 installation failed with exit code $($install.ExitCode)."}

$entry=$null
for($i=0;$i -lt 30 -and -not $entry;$i++){Start-Sleep -Seconds 1;$entry=Get-AppEntry}
if(-not $entry){throw "CELE Topnotcher OS uninstall registration was not found."}
if([string]$entry.DisplayVersion -ne $ExpectedVersion){
  throw "Expected installed RC5 version $ExpectedVersion, found $($entry.DisplayVersion)."
}
$appExe=Resolve-AppExe $entry
if(-not $appExe){throw "Installed CELE Topnotcher OS executable could not be located."}

if([string]::IsNullOrWhiteSpace($TesterName)){
  $TesterName=Read-Host "Tester name or initials"
}
$started=(Get-Date).ToUniversalTime().ToString("o")

$os=Get-CimInstance Win32_OperatingSystem
$computer=Get-CimInstance Win32_ComputerSystem
$video=@(Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution)

Write-Host ""
Write-Host "Launching RC5..."
$app=Start-Process -FilePath $appExe -PassThru
Start-Sleep -Seconds 4

$initial=Get-UiProcess $app.Id
if(-not $initial){throw "RC5 exited before the preboard test began."}

Write-Host ""
Write-Host "=== RC5 REAL PREBOARD REGRESSION ==="
Write-Host "Use the SAME preboard PDF that made RC4 become Not Responding."
Write-Host "Do not upload or copy the PDF into this evidence folder."
Write-Host ""
Write-Host "When you press Enter below, immediately switch to CELE Topnotcher OS and import that preboard PDF."
Write-Host "The script will monitor the app process for $MonitorSeconds seconds."
Read-Host "Press Enter when ready"

$samples=@()
$consecutiveNotResponding=0
$maxConsecutiveNotResponding=0
$everExited=$false
for($i=0;$i -lt $MonitorSeconds;$i++){
  $p=Get-UiProcess $app.Id
  if(-not $p){
    $everExited=$true
    $samples += [ordered]@{
      second=$i
      utc=(Get-Date).ToUniversalTime().ToString("o")
      exited=$true
      responding=$false
      workingSet64=$null
      totalProcessorSeconds=$null
      mainWindowTitle=""
    }
    break
  }
  $responding=[bool]$p.Responding
  if($responding){$consecutiveNotResponding=0}else{$consecutiveNotResponding++}
  if($consecutiveNotResponding -gt $maxConsecutiveNotResponding){$maxConsecutiveNotResponding=$consecutiveNotResponding}
  $samples += [ordered]@{
    second=$i
    utc=(Get-Date).ToUniversalTime().ToString("o")
    exited=$false
    responding=$responding
    workingSet64=[int64]$p.WorkingSet64
    totalProcessorSeconds=[Math]::Round($p.TotalProcessorTime.TotalSeconds,3)
    mainWindowTitle=[string]$p.MainWindowTitle
  }
  if(($i % 10) -eq 0){
    Write-Host ("Monitor {0}/{1}s - Responding={2} - WorkingSet={3:N0} MB" -f $i,$MonitorSeconds,$responding,($p.WorkingSet64/1MB))
  }
  Start-Sleep -Seconds 1
}

$processResponsivePass=(-not $everExited) -and ($maxConsecutiveNotResponding -lt $HangThresholdSamples)
$after=Get-UiProcess $app.Id
$shot=Join-Path $screens "post-preboard-import.png"
if($after){Capture-Screen $shot}

Write-Host ""
Write-Host "Automatic process monitor complete."
Write-Host "Process exited during test: $everExited"
Write-Host "Maximum consecutive Not Responding samples: $maxConsecutiveNotResponding"
Write-Host "Automatic responsiveness gate: $(if($processResponsivePass){'PASS_CANDIDATE'}else{'FAIL'})"
Write-Host ""

$picker=[ordered]@{}
$picker.samePreboardUsed=Ask-YesNo "Did you use the same preboard PDF that froze RC4?"
$picker.validPdfImported=Ask-YesNo "Did RC5 finish accepting the preboard PDF and show document/page information?"
$picker.pageRendering=Ask-YesNo "Could you render at least two pages from that preboard PDF?"
$picker.ocrInteraction=Ask-YesNo "Could you run native OCR on at least one rendered page/region and receive a result?"
$picker.cancelPath=Ask-YesNo "Open the source-PDF picker again and press Cancel. Did the app remain stable with no unintended import?"
$picker.invalidPdfRejected=Ask-YesNo "Try the generated invalid-not-a-real-pdf.pdf. Was it rejected cleanly without a crash?"
$picker.notes=Ask-Notes "Preboard/PDF notes (press Enter if none)"

$humanPass=@(
  $picker.samePreboardUsed,
  $picker.validPdfImported,
  $picker.pageRendering,
  $picker.ocrInteraction,
  $picker.cancelPath,
  $picker.invalidPdfRejected
) -notcontains $false

$pickerPass=$processResponsivePass -and $humanPass
$status=if($pickerPass){"PREBOARD_REGRESSION_PASS_CANDIDATE"}else{"PREBOARD_REGRESSION_FAIL"}

$report=[ordered]@{
  schemaVersion=1
  phase="v3.21.21-rc5-real-preboard-retest"
  status=$status
  approval="NOT_AUTOMATIC"
  tester=[ordered]@{
    name=$TesterName
    startedAtUtc=$started
    completedAtUtc=(Get-Date).ToUniversalTime().ToString("o")
  }
  releaseCandidate=[ordered]@{
    rc="v3.21.20-RC5"
    product=$ExpectedProduct
    version=$ExpectedVersion
    identifier=$ExpectedIdentifier
    installerSha256=$installerSha
    authenticodeStatus=[string]$signature.Status
  }
  automatedProcessMonitor=[ordered]@{
    durationSeconds=$MonitorSeconds
    sampleCount=$samples.Count
    hangThresholdConsecutiveSamples=$HangThresholdSamples
    maxConsecutiveNotRespondingSamples=$maxConsecutiveNotResponding
    everExited=$everExited
    passCandidate=$processResponsivePass
    samples=$samples
  }
  nativeFilePicker=[ordered]@{
    result=if($pickerPass){"PASS_CANDIDATE"}else{"FAIL"}
    checks=$picker
  }
  screenshot=[ordered]@{
    file=if(Test-Path $shot){[IO.Path]::GetFileName($shot)}else{$null}
    sha256=if(Test-Path $shot){Get-Sha256 $shot}else{$null}
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
  displayAndDpi="NOT_TESTED_IN_THIS_FOCUSED_RETEST"
  remainingReleaseGates=@(
    "strict 100/125/150/200 percent DPI retest",
    "Authenticode code signing",
    "final redistribution review of signed release package"
  )
  nativeAdapterQA="pending-human-review-of-this-evidence"
  releaseReady=$false
}

$reportPath=Join-Path $OutputDirectory "v3.21.21-rc5-real-preboard-retest-report.json"
$report | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $reportPath -Encoding UTF8

$hashes=@()
Get-ChildItem -LiteralPath $OutputDirectory -File -Recurse | Sort-Object FullName | ForEach-Object {
  $hashes += [ordered]@{
    path=$_.FullName.Substring($OutputDirectory.Length).TrimStart('\','/')
    bytes=$_.Length
    sha256=Get-Sha256 $_.FullName
  }
}
$hashPath=Join-Path $OutputDirectory "EVIDENCE_SHA256.json"
$hashes | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $hashPath -Encoding UTF8

$zip=$OutputDirectory.TrimEnd('\') + ".zip"
if(Test-Path $zip){Remove-Item -Force $zip}
Compress-Archive -Path (Join-Path $OutputDirectory "*") -DestinationPath $zip -CompressionLevel Optimal

Write-Host ""
Write-Host "=== RC5 preboard retest complete ==="
Write-Host "Status: $status"
Write-Host "Evidence ZIP: $zip"
Write-Host "ZIP SHA-256: $(Get-Sha256 $zip)"
Write-Host ""
Write-Host "This focused retest does NOT approve the DPI gate, signing, redistribution, nativeAdapterQA, or public release."
