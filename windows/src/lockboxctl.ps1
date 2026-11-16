# Lockbox control tool for Windows.   lockboxctl <command>
#   guide                         what to do next, step by step
#   verify                        check every layer
#   nextdns [ID]                  no ID: how to get one + status.  With ID (admin): install/switch NextDNS
#   filters open|lock             open uBlock Origin Lite's filter editor (admin, before arming or while unlocked) / lock it
#   arm <user> [delay] [window]   (admin) take admin away from <user>; minutes, default 30 / 120
#   trust <program.exe>           (admin) trust one more program, e.g. something you built
#   status                        state, config and recent log
param([string]$Cmd = 'help', [string]$A1, [string]$A2, [string]$A3)
$ErrorActionPreference = 'SilentlyContinue'
$Version = '1.3.1'
$App  = Join-Path $env:ProgramFiles 'Lockbox'
$Data = Join-Path $env:ProgramData 'Lockbox'
$ChromeKey = 'HKLM:\SOFTWARE\Policies\Google\Chrome'
$UbolKey = "$ChromeKey\3rdparty\extensions\ddkjiahejlhfcafbddmgiahcphecmpfh\policy"

function Ok($m)  { Write-Host "  [OK] $m" -ForegroundColor Green }
function Bad($m) { Write-Host "  [X]  $m" -ForegroundColor Red; $script:Fail = $true }
function Info($m){ Write-Host "  -    $m" }
function Is-Elevated { ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) }
function Need-Admin { if (-not (Is-Elevated)) { Write-Host 'Run this in Terminal opened with "Run as administrator" (only possible while unlocked).'; exit 1 } }
function Load-Config { if (Test-Path "$Data\config.json") { Get-Content "$Data\config.json" -Raw | ConvertFrom-Json } else { [pscustomobject]@{ TargetUser=''; Armed=$false; UnlockDelay=1800; AdminWindow=7200; Exempt=@(); Filters='locked' } } }
function Save-Config($c) { $c | ConvertTo-Json | Set-Content "$Data\config.json" -Encoding UTF8 }
function Admins-Name { (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([Security.Principal.NTAccount]).Value.Split('\')[-1] }
function Is-AdminUser($u) { (& net.exe localgroup (Admins-Name)) -contains $u }

switch ($Cmd) {
  'verify' {
    $script:Fail = $false; Write-Host "Lockbox $Version - verify"
    $sf = Get-Item "$Data\status.txt"
    if ($sf -and ((Get-Date) - $sf.LastWriteTime).TotalSeconds -lt 60) { Ok 'enforcer running' } else { Bad 'enforcer not running (status not updated in the last minute)' }
    if ((Get-ItemProperty $ChromeKey).DnsOverHttpsMode -eq 'secure') { Ok 'Chrome rules applied (own encrypted DNS)' } else { Bad 'Chrome rules missing' }
    $df = (Get-ItemProperty $UbolKey).disabledFeatures
    if ($df -match 'picker') { Ok 'uBlock Origin Lite filters locked' } elseif ($df) { Info 'uBlock Origin Lite filter editor is OPEN (lockboxctl filters lock)' } else { Bad 'uBlock Origin Lite settings missing' }
    if ((Get-Content "$env:SystemRoot\System32\drivers\etc\hosts") -contains '# >>> lockbox') { Ok 'hosts block present (Instagram)' } else { Bad 'hosts block missing' }
    $n = @(Get-DnsClientNrptRule | Where-Object { $_.Comment -eq 'Lockbox' }).Count
    if ($n) { Ok "YouTube DNS rules: $n" } else { Bad 'YouTube DNS rules missing' }
    $r = Resolve-DnsName www.youtube.com -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue
    if (-not ($r | Where-Object { $_.IPAddress })) { Ok 'YouTube does not resolve for other apps' } else { Bad 'YouTube still resolves for other apps' }
    if (Resolve-DnsName www.google.com -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue) { Ok 'normal DNS works' } else { Bad 'normal DNS lookups failing' }
    if (Get-Service NextDNS) { if ((Get-Service NextDNS).Status -eq 'Running') { Ok 'NextDNS running' } else { Bad 'NextDNS installed but not running' } } else { Info 'NextDNS not installed (optional: lockboxctl nextdns)' }
    if (Test-Path "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Lockbox.lnk") { Ok 'Lockbox app in Start menu' } else { Bad 'Lockbox Start menu shortcut missing' }
    $c = Load-Config
    if ($c.Armed) {
      Ok "armed for $($c.TargetUser) (unlock wait $([int]($c.UnlockDelay/60)) min, admin window $([int]($c.AdminWindow/60)) min)"
      $st = Get-Content "$Data\state.json" -Raw | ConvertFrom-Json
      if ($st.State -ne 'unlocked') { if (Is-AdminUser $c.TargetUser) { Bad "$($c.TargetUser) is admin while locked" } else { Ok "$($c.TargetUser) is a Standard user" } }
      if (Test-Path "$Data\trust\publishers.txt") { Ok "app guard trust list: $((Get-Content "$Data\trust\publishers.txt").Count) publishers" }
    } else { Info 'not armed yet (lockboxctl arm <user>)' }
    $bl = (New-Object -ComObject Shell.Application).NameSpace("$env:SystemDrive\").Self.ExtendedProperty('System.Volume.BitLockerProtection') -eq 1
    if ($bl) { Ok 'BitLocker on' } else { Info 'BitLocker/Device encryption off: someone with physical access could bypass Lockbox from outside Windows' }
    Write-Host "  status: $(Get-Content "$Data\status.txt")"
    if ($script:Fail) { Write-Host 'Some checks failed.'; exit 1 } else { Write-Host 'All checks passed.' }
  }

  'nextdns' {
    if (-not $A1) {
@'
NextDNS filters DNS on every network you join (optional - Lockbox's own blocks work without it).

  1. Make a free account at https://nextdns.io
  2. Open the Setup tab. Your config ID is the 6-character code next to "ID" (e.g. abc123).
  3. Optional, in the NextDNS dashboard:
       Parental Control -> Websites, Apps & Games -> add Instagram
       Leave Settings -> "Block Bypass Methods" OFF (it would break Chrome's encrypted DNS)
  4. Install it (admin Terminal, while unlocked):   lockboxctl nextdns abc123
'@ | Write-Host
      $s = Get-Service NextDNS; Write-Host ("Current: " + $(if ($s) { $s.Status } else { 'not installed' }))
      exit 0
    }
    Need-Admin
    if ($A1 -notmatch '^[a-z0-9]{6}$') { Write-Host "That doesn't look like a NextDNS ID (6 letters/digits, e.g. abc123)."; exit 1 }
    $nd = "$env:ProgramFiles\NextDNS\nextdns.exe"
    if (-not (Test-Path $nd)) {
      Write-Host 'Downloading NextDNS...'
      $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
      $rel = Invoke-RestMethod https://api.github.com/repos/nextdns/nextdns/releases/latest
      $asset = $rel.assets | Where-Object { $_.name -match "windows_$arch\.zip$" } | Select-Object -First 1
      if (-not $asset) { Write-Host 'Could not find the NextDNS download. Install it from https://nextdns.io instead.'; exit 1 }
      $tmp = Join-Path $env:TEMP 'nextdns.zip'
      Invoke-WebRequest $asset.browser_download_url -OutFile $tmp
      New-Item -ItemType Directory -Force "$env:ProgramFiles\NextDNS" | Out-Null
      Expand-Archive $tmp -DestinationPath "$env:ProgramFiles\NextDNS" -Force
    }
    & $nd uninstall *> $null
    & $nd install -config $A1 -report-client-info -auto-activate
    Start-Sleep 2; & $nd status
    Write-Host 'Check it at https://test.nextdns.io (should say status: ok)'
  }

  'filters' {
    Need-Admin
    $c = Load-Config
    $st = if (Test-Path "$Data\state.json") { (Get-Content "$Data\state.json" -Raw | ConvertFrom-Json).State } else { 'locked' }
    if ($A1 -eq 'open') {
      if ($c.Armed -and $st -ne 'unlocked') { Write-Host 'Only possible while unlocked.'; exit 1 }
      $c.Filters = 'open'; Save-Config $c
      Write-Host 'Opening in ~30 s. Then: quit Chrome fully and reopen it, puzzle icon -> uBlock Origin Lite -> gear -> Custom filters.'
      Get-Content "$App\ubol-filters.txt" | Set-Clipboard
      Write-Host 'The filters are on your clipboard - paste them there and save. Then run: lockboxctl filters lock'
    } elseif ($A1 -eq 'lock') {
      $c.Filters = 'locked'; Save-Config $c; New-Item -Force "$Data\filters-pasted" | Out-Null
      Write-Host 'Locked within ~30 s. Restart Chrome; the Custom filters pane will be gone.'
    } else { Write-Host 'usage: lockboxctl filters open|lock' }
  }

  'guide' {
    $c = Load-Config
    Write-Host "Lockbox $Version - setup guide"
    function Step($t, [string[]]$lines) { Write-Host ''; Write-Host "NEXT: $t" -ForegroundColor Cyan; $lines | ForEach-Object { Write-Host "  $_" }; exit 0 }
    if (-not (Test-Path "$Data\status.txt")) { Step 'Install Lockbox' @('Open Terminal as administrator, then:', 'cd $HOME\Downloads\lockbox-windows; powershell -ExecutionPolicy Bypass -File install.ps1') }
    $df = (Get-ItemProperty $UbolKey).disabledFeatures
    $uf = Join-Path $Data 'filters-pasted'
    if (-not (Test-Path $uf)) {
      if ($c.Filters -ne 'open') { Step 'Open the YouTube filter editor' @('Admin Terminal:  lockboxctl filters open') }
      Step 'Paste the YouTube filters, then lock them' @(
        '1. Quit Chrome fully (also from the system tray) and reopen it',
        '2. Puzzle icon -> uBlock Origin Lite -> gear -> Custom filters -> paste (already on your clipboard) -> save',
        '3. Open a YouTube video: only the video and its title should show',
        '4. Admin Terminal:  lockboxctl filters lock')
    }
    if (-not (Get-Service NextDNS)) { Write-Host 'Optional: NextDNS is not set up. Run "lockboxctl nextdns" for instructions.' }
    if (-not $c.Armed) {
      Step 'Arm it (removes your admin rights)' @('Open the apps you use day to day first, then in an admin Terminal:', "lockboxctl arm $env:USERNAME", 'Type ARM, then restart.')
    }
    Write-Host ''; Write-Host "All set - Lockbox is armed for $($c.TargetUser). Status: $(Get-Content "$Data\status.txt")"
    Write-Host 'Need admin? Start menu -> Lockbox -> Request unlock.'
  }

  'arm' {
    Need-Admin
    $u = $A1; $d = if ($A2) { [int]$A2 } else { 30 }; $w = if ($A3) { [int]$A3 } else { 120 }
    if (-not $u -or -not (Get-LocalUser -Name $u)) { Write-Host 'usage: lockboxctl arm <local user name> [delay_min] [window_min]'; exit 1 }
    $others = @(Get-LocalUser | Where-Object { $_.Enabled -and $_.Name -ne $u -and (Is-AdminUser $_.Name) -and $_.SID.Value -notlike '*-500' })
    if ($others) { Write-Host "Note: these admin accounts will also lose admin: $($others.Name -join ', ')" }
    Write-Host "This makes '$u' a Standard user. Getting admin back will need a $d-minute wait in the Lockbox app."
    if ((Read-Host 'Type ARM to continue') -ne 'ARM') { Write-Host 'cancelled'; exit 1 }
    Write-Host 'Recording which programs are trusted (open the apps you use before this)...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$App\trust-scan.ps1" -User $u
    $c = Load-Config
    $c.TargetUser = $u; $c.Armed = $true; $c.UnlockDelay = $d * 60; $c.AdminWindow = $w * 60; $c.Exempt = @(); $c.Filters = 'locked'
    Save-Config $c
    @{ State = 'locked'; UnlockAt = 0; RelockAt = 0 } | ConvertTo-Json | Set-Content "$Data\state.json" -Encoding UTF8
    Start-Sleep 12
    if (Is-AdminUser $u) { Write-Host "Armed, but $u still shows as admin - run: lockboxctl verify" } else { Write-Host "ARMED. $u is now a Standard user. Sign out and back in (or restart)." }
  }

  'trust' {
    Need-Admin
    if (-not (Test-Path $A1)) { Write-Host 'usage: lockboxctl trust C:\path\to\program.exe'; exit 1 }
    $sig = Get-AuthenticodeSignature -LiteralPath $A1
    if ($sig.Status -eq 'Valid') { $p = $sig.SignerCertificate.GetNameInfo('SimpleName', $false); Add-Content "$Data\trust\publishers.txt" $p; "trusted publisher $p" }
    else { $h = (Get-FileHash $A1 -Algorithm SHA256).Hash; Add-Content "$Data\trust\hashes.txt" $h; "trusted this exact file ($h)" }
  }

  'status' { Get-Content "$Data\status.txt"; Get-Content "$Data\config.json"; Get-Content "$Data\lockbox.log" -Tail 15 }
  'version' { $Version }
  default { Get-Content $PSCommandPath -TotalCount 8 | Select-Object -Skip 1 | ForEach-Object { $_ -replace '^# ?', '' } }
}
