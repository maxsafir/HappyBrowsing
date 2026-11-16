# Records which programs may run from user-writable folders while HappyBrowsing is locked.
#   trust-scan.ps1             running programs + already-trusted list (used on every re-lock)
#   trust-scan.ps1 <user>      also scans that user's AppData (used when arming)
# Trusted = signed (as judged by SYSTEM) by a publisher found here, or (unsigned) this exact file hash.
param([string]$User)
$ErrorActionPreference = 'SilentlyContinue'
$Trust = Join-Path $env:ProgramData 'HappyBrowsing\trust'
New-Item -ItemType Directory -Force -Path $Trust | Out-Null
$pubs = [Collections.Generic.HashSet[string]]::new()
$hashes = [Collections.Generic.HashSet[string]]::new()
foreach ($f in 'publishers.txt','hashes.txt') {
  $p = Join-Path $Trust $f
  if (Test-Path $p) { Get-Content $p | ForEach-Object { if ($f -eq 'publishers.txt') { [void]$pubs.Add($_) } else { [void]$hashes.Add($_) } } }
}
'Microsoft Corporation','Microsoft Windows','Microsoft Windows Publisher','Google LLC' | ForEach-Object { [void]$pubs.Add($_) }

function Record($path) {
  $sig = Get-AuthenticodeSignature -LiteralPath $path
  if ($sig.Status -eq 'Valid' -and $sig.SignerCertificate) {
    [void]$pubs.Add($sig.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false))
  } else {
    $h = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
    if ($h) { [void]$hashes.Add($h) }
  }
}

$files = @()
if ($User) {
  $prof = (Get-CimInstance Win32_UserProfile | Where-Object { $_.LocalPath -match "\\$([regex]::Escape($User))$" } | Select-Object -First 1).LocalPath
  if ($prof) {
    $files += Get-ChildItem "$prof\AppData\Local\Programs" -Recurse -Filter *.exe -File
    $files += Get-ChildItem "$prof\AppData\Local" -Depth 3 -Filter *.exe -File
    $files += Get-ChildItem "$prof\AppData\Roaming" -Depth 3 -Filter *.exe -File
  }
}
$files | Select-Object -ExpandProperty FullName -Unique | ForEach-Object { Record $_ }
Get-Process | Where-Object { $_.Path } | Select-Object -ExpandProperty Path -Unique | ForEach-Object { Record $_ }

$pubs | Sort-Object | Set-Content (Join-Path $Trust 'publishers.txt') -Encoding UTF8
$hashes | Sort-Object | Set-Content (Join-Path $Trust 'hashes.txt') -Encoding UTF8
"trusted: $($pubs.Count) publishers, $($hashes.Count) unsigned programs"
