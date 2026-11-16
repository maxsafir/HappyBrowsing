# HappyBrowsing app for Windows: request an unlock, cancel it, or re-lock. Runs as the normal user.
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$Data = Join-Path $env:ProgramData 'HappyBrowsing'
function Get-Status { try { (Get-Content "$Data\status.txt" -ErrorAction Stop | Select-Object -First 1).Trim() } catch { 'HappyBrowsing is not running.' } }
$cfg = try { Get-Content "$Data\config.json" -Raw | ConvertFrom-Json } catch { $null }
$delay = if ($cfg) { [int]($cfg.UnlockDelay / 60) } else { 30 }
$window = if ($cfg) { [int]($cfg.AdminWindow / 60) } else { 120 }

$f = New-Object Windows.Forms.Form
$f.Text = 'HappyBrowsing'; $f.Width = 460; $f.Height = 250; $f.StartPosition = 'CenterScreen'
$f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false; $f.Font = New-Object Drawing.Font('Segoe UI', 10)
$status = New-Object Windows.Forms.Label
$status.Left = 20; $status.Top = 18; $status.Width = 410; $status.Height = 28
$status.Font = New-Object Drawing.Font('Segoe UI Semibold', 12)
$note = New-Object Windows.Forms.Label
$note.Left = 20; $note.Top = 52; $note.Width = 410; $note.Height = 80
$note.Text = "Unlocking makes your account an administrator (to install apps) after a $delay-minute wait. YouTube and Instagram stay blocked. Admin ends when you press Re-lock, or automatically after $window minutes."
$btn = New-Object Windows.Forms.Button
$btn.Left = 20; $btn.Top = 145; $btn.Width = 300; $btn.Height = 40
$close = New-Object Windows.Forms.Button
$close.Left = 330; $close.Top = 145; $close.Width = 100; $close.Height = 40; $close.Text = 'Close'
$close.Add_Click({ $f.Close() })

function Refresh-UI {
  $s = Get-Status; $status.Text = $s; $btn.Enabled = $true
  if ($s -like 'LOCKED*') { $btn.Text = "Request unlock ($delay min wait)"; $btn.Tag = 'unlock' }
  elseif ($s -like 'UNLOCK PENDING*') { $btn.Text = 'Cancel unlock request'; $btn.Tag = 'cancel' }
  elseif ($s -like 'UNLOCKED*') { $btn.Text = 'Re-lock now'; $btn.Tag = 'relock' }
  else { $btn.Text = 'Unavailable'; $btn.Enabled = $false }
}
$btn.Add_Click({
  New-Item -ItemType File -Force -Path (Join-Path "$Data\inbox" $btn.Tag) | Out-Null
  $btn.Enabled = $false; $btn.Text = 'Working...'
})
$timer = New-Object Windows.Forms.Timer; $timer.Interval = 3000; $timer.Add_Tick({ Refresh-UI }); $timer.Start()
$f.Controls.AddRange(@($status, $note, $btn, $close))
Refresh-UI
[void]$f.ShowDialog()
