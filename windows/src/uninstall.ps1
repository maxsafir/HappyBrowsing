# Removes Lockbox completely. Needs an administrator Terminal, so it only works while unlocked.
$ErrorActionPreference = 'SilentlyContinue'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  Write-Host 'Run in an administrator Terminal (only possible while unlocked).'; exit 1 }
if ((Read-Host 'Remove Lockbox and all its blocks? Type REMOVE') -ne 'REMOVE') { exit 1 }
$App = Join-Path $env:ProgramFiles 'Lockbox'; $Data = Join-Path $env:ProgramData 'Lockbox'
'Lockbox Watchdog','Lockbox Enforcer' | ForEach-Object { Stop-ScheduledTask -TaskName $_; Unregister-ScheduledTask -TaskName $_ -Confirm:$false }
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" | Where-Object { $_.CommandLine -like '*Lockbox\enforcer.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Get-DnsClientNrptRule | Where-Object { $_.Comment -eq 'Lockbox' } | ForEach-Object { Remove-DnsClientNrptRule -Name $_.Name -Force }
$h = "$env:SystemRoot\System32\drivers\etc\hosts"; $in = $false
(Get-Content $h) | Where-Object { if ($_ -eq '# >>> lockbox') { $in = $true; return $false }; if ($_ -eq '# <<< lockbox') { $in = $false; return $false }; -not $in } | Set-Content $h -Encoding ASCII
$key = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
(Get-Content "$App\chrome-policy.json" -Raw | ConvertFrom-Json).PSObject.Properties.Name | ForEach-Object { Remove-ItemProperty $key -Name $_; Remove-Item "$key\$_" -Recurse }
Remove-Item "$key\3rdparty\extensions\ddkjiahejlhfcafbddmgiahcphecmpfh" -Recurse
if (Test-Path "$env:ProgramFiles\NextDNS\nextdns.exe") { & "$env:ProgramFiles\NextDNS\nextdns.exe" uninstall; Remove-Item "$env:ProgramFiles\NextDNS" -Recurse -Force }
Remove-Item "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Lockbox.lnk" -Force
$mp = [Environment]::GetEnvironmentVariable('Path', 'Machine'); [Environment]::SetEnvironmentVariable('Path', (($mp -split ';') | Where-Object { $_ -and $_ -ne $App }) -join ';', 'Machine')
Clear-DnsClientCache
Set-Location $env:SystemRoot
Remove-Item $Data -Recurse -Force; Remove-Item $App -Recurse -Force
Write-Host 'Lockbox removed. Restart the PC.'
