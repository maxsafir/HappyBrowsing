# Lockbox enforcer for Windows 1.3 — runs as SYSTEM from the "Lockbox Enforcer" scheduled task, every 5 seconds.
#   locked   -> target user is a Standard user, every block enforced, app guard on, uBOL filters locked
#   pending  -> unlock requested, still locked, waits UnlockDelay seconds
#   unlocked -> target user is an administrator (blocks stay on, app guard off) until Re-lock or AdminWindow ends
$ErrorActionPreference = 'SilentlyContinue'

$App   = Join-Path $env:ProgramFiles 'Lockbox'
$Data  = Join-Path $env:ProgramData 'Lockbox'
$Inbox = Join-Path $Data 'inbox'
$Trust = Join-Path $Data 'trust'
$Log   = Join-Path $Data 'lockbox.log'
$Hosts = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$ChromeKey = 'HKLM:\SOFTWARE\Policies\Google\Chrome'

function Write-Log($msg) { Add-Content -Path $Log -Value ("{0} {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) }
function Now { [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

# Administrators group by SID, so this works on any Windows language.
$AdminsName = (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]

function Load-Config {
  $c = @{ TargetUser = ''; Armed = $false; UnlockDelay = 1800; AdminWindow = 7200; Exempt = @(); Filters = 'locked' }
  $f = Join-Path $Data 'config.json'
  if (Test-Path $f) { (Get-Content $f -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $c[$_.Name] = $_.Value } }
  return $c
}
function Load-State {
  $s = @{ State = 'locked'; UnlockAt = 0; RelockAt = 0 }
  $f = Join-Path $Data 'state.json'
  if (Test-Path $f) { (Get-Content $f -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $s[$_.Name] = $_.Value } }
  return $s
}
function Save-State($s) { $s | ConvertTo-Json | Set-Content -Path (Join-Path $Data 'state.json') -Encoding UTF8 }

# ---------- admin group ----------
function Get-AdminMembers {
  $g = [ADSI]"WinNT://./$AdminsName,group"
  @($g.psbase.Invoke('Members')) | ForEach-Object {
    $path = $_.GetType().InvokeMember('ADsPath', 'GetProperty', $null, $_, $null)   # WinNT://DOMAIN/name
    $name = $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null)
    [pscustomobject]@{ Name = $name; Path = $path }
  }
}
function Test-Admin($user) { (Get-AdminMembers | Where-Object { $_.Name -eq $user }) -ne $null }
function Promote($user) { & net.exe localgroup "$AdminsName" "$user" /add *> $null; Write-Log "promoted $user" }
function Demote($user)  { & net.exe localgroup "$AdminsName" "$user" /delete *> $null; Write-Log "demoted $user" }

function Enforce-Admins($cfg, $st) {
  if (-not $cfg.Armed) { return }
  $allowed = @($cfg.Exempt)
  if ($st.State -eq 'unlocked') { $allowed += $cfg.TargetUser }
  foreach ($m in Get-AdminMembers) {
    # Keep the built-in Administrator (-500) in the group but disabled; keep domain groups alone.
    $sid = $null
    try { $sid = (New-Object Security.Principal.NTAccount($m.Name)).Translate([Security.Principal.SecurityIdentifier]).Value } catch {}
    if ($sid -and $sid -like 'S-1-5-21-*-500') { continue }
    if ($m.Path -match '^WinNT://[^/]+/[^/]+$') { continue }   # 2 segments = domain/Azure AD account or group; local accounts have 3
    if ($allowed -contains $m.Name) { continue }
    Demote $m.Name
  }
  if ($st.State -eq 'unlocked' -and -not (Test-Admin $cfg.TargetUser)) { Promote $cfg.TargetUser }
  # Built-in Administrator stays disabled.
  Get-LocalUser | Where-Object { $_.SID.Value -like 'S-1-5-21-*-500' -and $_.Enabled } | ForEach-Object {
    Disable-LocalUser -SID $_.SID; Write-Log 'disabled built-in Administrator'
  }
}

# ---------- hosts (Instagram, every app incl. Chrome) ----------
function Enforce-Hosts {
  $want = Get-Content (Join-Path $App 'hosts-block.txt')
  $lines = Get-Content $Hosts
  $in = $false; $cur = @(); $rest = @()
  foreach ($l in $lines) {
    if ($l -eq '# >>> lockbox') { $in = $true; continue }
    if ($l -eq '# <<< lockbox') { $in = $false; continue }
    if ($in) { $cur += $l } else { $rest += $l }
  }
  if (($cur -join "`n") -ne ($want -join "`n")) {
    $new = $rest + '# >>> lockbox' + $want + '# <<< lockbox'
    Set-Content -Path $Hosts -Value $new -Encoding ASCII
    Clear-DnsClientCache
    Write-Log 'hosts block re-applied'
  }
}

# ---------- YouTube for every app except Chrome (NRPT) ----------
# Windows' Name Resolution Policy Table sends YouTube lookups to a dead loopback address.
# Chrome resolves through its own encrypted DNS (policy), so only Chrome can still reach YouTube.
function Enforce-Nrpt {
  $domains = Get-Content (Join-Path $App 'youtube-domains.txt') | Where-Object { $_ -and $_ -notmatch '^#' }
  $existing = @(Get-DnsClientNrptRule | Where-Object { $_.Comment -eq 'Lockbox' })
  $changed = $false
  foreach ($d in $domains) {
    foreach ($ns in @(".$d", $d)) {
      if (-not ($existing | Where-Object { $_.Namespace -contains $ns })) {
        Add-DnsClientNrptRule -Namespace $ns -NameServers '127.0.0.2' -Comment 'Lockbox' | Out-Null
        $changed = $true
      }
    }
  }
  if ($changed) { Clear-DnsClientCache; Write-Log 'YouTube NRPT block re-applied' }
}

# ---------- Chrome policies ----------
function Set-PolicyValue($key, $name, $value) {
  if (-not (Test-Path $key)) { New-Item -Path $key -Force | Out-Null }
  if ($value -is [bool]) { New-ItemProperty -Path $key -Name $name -PropertyType DWord -Value ([int]$value) -Force | Out-Null }
  elseif ($value -is [int] -or $value -is [long]) { New-ItemProperty -Path $key -Name $name -PropertyType DWord -Value ([int]$value) -Force | Out-Null }
  elseif ($value -is [string]) { New-ItemProperty -Path $key -Name $name -PropertyType String -Value $value -Force | Out-Null }
  elseif ($value -is [array]) {
    $sub = Join-Path $key $name
    if (Test-Path $sub) { Remove-Item $sub -Recurse -Force }
    New-Item -Path $sub -Force | Out-Null
    $i = 1; foreach ($v in $value) { New-ItemProperty -Path $sub -Name "$i" -PropertyType String -Value "$v" -Force | Out-Null; $i++ }
  }
  else { New-ItemProperty -Path $key -Name $name -PropertyType String -Value ($value | ConvertTo-Json -Depth 10 -Compress) -Force | Out-Null }
}
$script:LastChrome = ''
function Enforce-Chrome($cfg, $st) {
  $raw = Get-Content (Join-Path $App 'chrome-policy.json') -Raw
  $mode = if (($st.State -eq 'unlocked' -or -not $cfg.Armed) -and $cfg.Filters -eq 'open') { 'open' } else { 'locked' }
  # Only rewrite when something changed (rewriting makes Chrome reload its policies).
  $sig = "$raw|$mode"
  if ($sig -eq $script:LastChrome -and (Get-ItemProperty $ChromeKey).DnsOverHttpsMode -eq 'secure') { return }
  $pol = $raw | ConvertFrom-Json
  foreach ($p in $pol.PSObject.Properties) { Set-PolicyValue $ChromeKey $p.Name $p.Value }
  $u = Get-Content (Join-Path $App 'ubol-policy.json') -Raw | ConvertFrom-Json
  $ukey = "$ChromeKey\3rdparty\extensions\$($u.id)\policy"
  if (-not (Test-Path $ukey)) { New-Item -Path $ukey -Force | Out-Null }
  $set = $u.$mode
  # uBOL on Windows: strings and arrays as REG_SZ (arrays as JSON), booleans as REG_DWORD.
  New-ItemProperty -Path $ukey -Name disabledFeatures -PropertyType String -Value ($set.disabledFeatures | ConvertTo-Json -Compress) -Force | Out-Null
  New-ItemProperty -Path $ukey -Name noFiltering -PropertyType String -Value ($set.noFiltering | ConvertTo-Json -Compress) -Force | Out-Null
  New-ItemProperty -Path $ukey -Name disableFirstRunPage -PropertyType DWord -Value 1 -Force | Out-Null
  $script:LastChrome = $sig
  Write-Log "Chrome policies applied (uBOL filters $mode)"
}

# ---------- app guard ----------
$SigCache = @{}
$BlockedNames = @(); $BlockedSigners = @()
function Load-BrowserList {
  $script:BlockedNames = @(); $script:BlockedSigners = @()
  foreach ($l in Get-Content (Join-Path $App 'browsers-windows.txt')) {
    if ($l -match '^\s*#' -or -not $l.Trim()) { continue }
    if ($l -like 'signer:*') { $script:BlockedSigners += $l.Substring(7).Trim() } else { $script:BlockedNames += $l.Trim().ToLower() }
  }
}
function Get-SigInfo($path) {
  $item = Get-Item -LiteralPath $path
  $key = "$path|$($item.LastWriteTimeUtc.Ticks)"
  if ($SigCache.ContainsKey($key)) { return $SigCache[$key] }
  $sig = Get-AuthenticodeSignature -LiteralPath $path   # trust evaluated as SYSTEM: user-imported certificates don't count
  $signer = ''
  if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate) { $signer = $sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false) }
  $info = [pscustomobject]@{ Valid = ($sig.Status -eq 'Valid'); Signer = $signer; Hash = $null }
  if (-not $info.Valid) { $info.Hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
  $SigCache[$key] = $info
  return $info
}
function Test-AdminOnlyPath($path) {
  # Places a Standard user can't write to: anything installed here was installed by an admin.
  foreach ($root in @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:SystemRoot)) {
    if ($root -and $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) { return $true }
  }
  return $false
}
function Guard-Apps($cfg, $st) {
  $guard = $cfg.Armed -and $st.State -ne 'unlocked' -and (Test-Path (Join-Path $Trust 'publishers.txt'))
  $pubs = @(); $hashes = @()
  if ($guard) { $pubs = Get-Content (Join-Path $Trust 'publishers.txt'); $hashes = Get-Content (Join-Path $Trust 'hashes.txt') }
  # Only programs running in a user's session; Windows services (SYSTEM, LOCAL/NETWORK SERVICE) are admin-installed.
  foreach ($p in Get-Process -IncludeUserName | Where-Object { $_.Path -and $_.UserName -and $_.UserName -notlike 'NT AUTHORITY\*' }) {
    $exe = [IO.Path]::GetFileName($p.Path).ToLower()
    $reason = $null
    if ($BlockedNames -contains $exe -and $exe -ne 'msedgewebview2.exe') { $reason = 'blocked browser' }
    if (-not $reason -and ($exe -eq 'chrome.exe' -or $BlockedSigners.Count)) {
      $si = Get-SigInfo $p.Path
      if ($si.Signer -and ($BlockedSigners -contains $si.Signer)) { $reason = "blocked browser ($($si.Signer))" }
      elseif ($exe -eq 'chrome.exe' -and $si.Signer -ne 'Google LLC') { $reason = 'chrome.exe not signed by Google (Chromium or a modified build)' }
    }
    if (-not $reason -and $guard -and -not (Test-AdminOnlyPath $p.Path)) {
      $si = Get-SigInfo $p.Path
      if ($si.Valid) { if ($pubs -notcontains $si.Signer) { $reason = "untrusted publisher $($si.Signer)" } }
      elseif ($hashes -notcontains $si.Hash) { $reason = 'unsigned, untrusted program' }
    }
    if ($reason) { Stop-Process -Id $p.Id -Force; Write-Log "closed $($p.Path): $reason" }
  }
}

# ---------- NextDNS ----------
function Enforce-NextDns {
  $svc = Get-Service -Name 'NextDNS' -ErrorAction SilentlyContinue
  if ($svc -and $svc.Status -ne 'Running') { Start-Service 'NextDNS'; Write-Log 'NextDNS started' }
}

# ---------- requests from the Lockbox app ----------
function Relocked {
  Start-Process -WindowStyle Hidden -FilePath powershell.exe -ArgumentList '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$App\trust-scan.ps1`""
}
function Process-Inbox($cfg, $st) {
  $now = Now
  if (Test-Path "$Inbox\relock") {
    Remove-Item "$Inbox\*" -Force
    if ($st.State -ne 'locked') { $was = $st.State; $st.State = 'locked'; $st.UnlockAt = 0; $st.RelockAt = 0; Save-State $st; Write-Log 'relock by button'; if ($was -eq 'unlocked') { Relocked } }
  }
  if (Test-Path "$Inbox\cancel") {
    Remove-Item "$Inbox\cancel","$Inbox\unlock" -Force
    if ($st.State -eq 'pending') { $st.State = 'locked'; $st.UnlockAt = 0; Save-State $st; Write-Log 'unlock cancelled' }
  }
  if (Test-Path "$Inbox\unlock") {
    Remove-Item "$Inbox\unlock" -Force
    if ($st.State -eq 'locked') { $st.State = 'pending'; $st.UnlockAt = $now + [int]$cfg.UnlockDelay; Save-State $st; Write-Log 'unlock requested' }
  }
  Remove-Item "$Inbox\*" -Force
  if ($st.State -eq 'pending' -and $now -ge $st.UnlockAt) { $st.State = 'unlocked'; $st.RelockAt = $now + [int]$cfg.AdminWindow; Save-State $st; Write-Log 'unlocked' }
  if ($st.State -eq 'unlocked' -and $now -ge $st.RelockAt) { $st.State = 'locked'; $st.UnlockAt = 0; $st.RelockAt = 0; Save-State $st; Write-Log 'auto relock'; Relocked }
}

function Write-Status($cfg, $st) {
  $now = Now
  switch ($st.State) {
    'locked'   { $msg = 'LOCKED' }
    'pending'  { $msg = "UNLOCK PENDING - admin rights in $([math]::Ceiling(($st.UnlockAt - $now) / 60)) min" }
    'unlocked' { $msg = "UNLOCKED (admin) - auto re-lock in $([math]::Ceiling(($st.RelockAt - $now) / 60)) min" }
  }
  if (-not $cfg.Armed) { $msg += ' (not armed yet)' }
  Set-Content -Path (Join-Path $Data 'status.txt') -Value $msg -Encoding UTF8
}

# ---------- main loop ----------
New-Item -ItemType Directory -Force -Path $Inbox | Out-Null
Write-Log 'enforcer 1.3 started'
Load-BrowserList
$i = 0
while ($true) {
  $cfg = Load-Config; $st = Load-State
  Process-Inbox $cfg $st
  if ($st.State -eq 'locked' -and $cfg.Filters -eq 'open' -and $cfg.Armed) {   # re-lock always closes the filter editor
    $cfg.Filters = 'locked'; ($cfg | ConvertTo-Json) | Set-Content (Join-Path $Data 'config.json') -Encoding UTF8
  }
  Enforce-Admins $cfg $st
  Enforce-Hosts
  if ($i % 6 -eq 0) { Enforce-Nrpt; Enforce-Chrome $cfg $st; Enforce-NextDns }
  Guard-Apps $cfg $st
  if ($i % 720 -eq 0) { $SigCache.Clear(); Load-BrowserList }
  Write-Status $cfg $st
  $i++
  Start-Sleep -Seconds 5
}
