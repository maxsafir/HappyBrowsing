# Lockbox installer for Windows 1.3.  In Terminal opened with "Run as administrator":
#   powershell -ExecutionPolicy Bypass -File install.ps1 [NEXTDNS_ID]
# Installs every layer but does NOT take admin away. Arming is a separate, explicit step.
param([string]$NextDnsId)
$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host 'Open Terminal with "Run as administrator", then run this again.'; exit 1 }
$Src  = Join-Path $PSScriptRoot 'src'
$App  = Join-Path $env:ProgramFiles 'Lockbox'
$Data = Join-Path $env:ProgramData 'Lockbox'

Write-Host '== 1/6 Files'
New-Item -ItemType Directory -Force $App, $Data, "$Data\inbox", "$Data\trust" | Out-Null
Copy-Item "$Src\*" $App -Force
# ProgramData: only SYSTEM and Administrators may change Lockbox's data; Users may only drop requests into inbox.
& icacls.exe $Data /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
& icacls.exe "$Data\inbox" /grant '*S-1-5-32-545:(OI)(CI)M' | Out-Null
if (-not (Test-Path "$Data\config.json")) {
  @{ TargetUser = ''; Armed = $false; UnlockDelay = 1800; AdminWindow = 7200; Exempt = @(); Filters = 'locked' } | ConvertTo-Json | Set-Content "$Data\config.json" -Encoding UTF8
}
$mp = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if ($mp -notlike "*$App*") { [Environment]::SetEnvironmentVariable('Path', "$mp;$App", 'Machine') }

Write-Host '== 2/6 NextDNS (optional)'
if (-not $NextDnsId -and -not (Get-Service NextDNS -ErrorAction SilentlyContinue)) {
  Write-Host '   NextDNS filters DNS on every network. Free account: https://nextdns.io -> Setup tab -> 6-character ID.'
  $NextDnsId = Read-Host '   NextDNS config ID (press Enter to skip)'
}
if ($NextDnsId) { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$App\lockboxctl.ps1" nextdns $NextDnsId }
else { Write-Host '   skipped - set it up later with: lockboxctl nextdns' }

Write-Host '== 3/6 Enforcer (runs as SYSTEM)'
$act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$App\enforcer.ps1`""
$sys = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$set = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) `
       -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -StartWhenAvailable
Get-ScheduledTask -TaskName 'Lockbox Enforcer' -ErrorAction SilentlyContinue | Stop-ScheduledTask
Register-ScheduledTask -TaskName 'Lockbox Enforcer' -Action $act -Trigger (New-ScheduledTaskTrigger -AtStartup) -Principal $sys -Settings $set -Force | Out-Null
$wact = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command `"Start-ScheduledTask -TaskName 'Lockbox Enforcer'`""
$wtrg = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 9999)
Register-ScheduledTask -TaskName 'Lockbox Watchdog' -Action $wact -Trigger $wtrg -Principal $sys -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries) -Force | Out-Null
Start-ScheduledTask -TaskName 'Lockbox Enforcer'

Write-Host '== 4/6 Lockbox app (Start menu)'
$lnk = (New-Object -ComObject WScript.Shell).CreateShortcut("$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Lockbox.lnk")
$lnk.TargetPath = 'powershell.exe'
$lnk.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$App\LockboxApp.ps1`""
$lnk.IconLocation = "$env:SystemRoot\System32\imageres.dll,54"
$lnk.Save()

Write-Host '== 5/6 Chrome'
$chrome = @("$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe") | Where-Object { Test-Path $_ }
if ($chrome) { Write-Host '   Chrome found. Rules apply within 30 s; restart Chrome to load them.' }
else { Write-Host '   Chrome not found in Program Files. Install Chrome for all users (chrome.com) while you are still admin.' }

Write-Host '== 6/6 Waiting for the enforcer'
Start-Sleep 10
Write-Host "   Status: $(Get-Content "$Data\status.txt" -ErrorAction SilentlyContinue)"
Write-Host ''
Write-Host 'Installed. Open a NEW administrator Terminal (so the lockboxctl command is found) and run:  lockboxctl guide'
