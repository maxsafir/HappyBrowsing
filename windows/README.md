# Lockbox for Windows 1.3

The Windows version of Lockbox: it blocks the distracting parts of the internet *and* takes away your own administrator rights, so you can't undo it in a moment of weakness. When you need admin (to install an app, change settings, run Windows Update), you request it in the Lockbox app and wait.

> **Status: new.** The Windows version is built to mirror the Mac version, which has been tested on a real machine. Run `lockboxctl verify` after installing and before arming, and report anything that fails.

| What | How on Windows |
|---|---|
| YouTube: video pages only, Chrome only | Chrome policies in `HKLM\SOFTWARE\Policies\Google\Chrome`; YouTube domains sent to a dead resolver for every other app via the Name Resolution Policy Table (NRPT); Chrome alone uses its own encrypted DNS. |
| Video and title only | uBlock Origin Lite holds the hiding filters; its editor is switched off by policy while locked. |
| Instagram: gone | Chrome policy + the hosts file (+ NextDNS, optional). |
| Chrome only | Firefox, Edge, Brave, Opera, Vivaldi, Arc and others are closed within 5 seconds, matched by file name **and** by Authenticode publisher. A `chrome.exe` not signed by Google (Chromium, modified builds) is closed too. |
| App guard | While locked, programs running from places you can write to (your user folder, USB drives…) must be signed by a publisher already trusted, or be an exact file you trusted. Signatures are checked by the SYSTEM account, so importing your own certificate doesn't help. |
| Your account is Standard | No UAC elevation, no changing the policies, hosts file, DNS rules or the Lockbox task. The built-in Administrator account is kept disabled. |
| Delayed unlock | Start menu → **Lockbox** → *Request unlock* → after 30 min you're an administrator. *Re-lock* (or 2 h timeout) ends it. |

## How it works

```
 Scheduled task "Lockbox Enforcer" (SYSTEM, starts at boot, loops every 5 s)
   • keeps your account out of Administrators (unless unlocked), built-in Administrator disabled
   • re-applies Chrome policies, uBOL lock, hosts block, NRPT rules
   • app guard: closes blocked browsers, and (while locked) untrusted programs from user-writable folders
   • keeps the NextDNS service running
   • unlock state machine:  LOCKED → PENDING (wait) → UNLOCKED → LOCKED
 Scheduled task "Lockbox Watchdog" (SYSTEM, every 5 min) restarts the enforcer if it ever stops
 Lockbox app (Start menu) drops a request file into C:\ProgramData\Lockbox\inbox
```

## Install

You need: an administrator account (for setup only), Windows 10 or 11, and Google Chrome **installed for all users** (the normal installer from google.com/chrome does this when run as admin). Turning on **BitLocker** (Pro) or **Device encryption** (Home) is strongly recommended — see the threat model.

The short version: run the installer, then keep running `lockboxctl guide` — it prints the exact next step.

1. Unzip `lockbox-windows` into Downloads.
2. Right-click Start → **Terminal (Admin)**, then:
   ```
   cd $HOME\Downloads\lockbox-windows
   powershell -ExecutionPolicy Bypass -File install.ps1
   ```
   It asks for a NextDNS config ID — press Enter to skip.
3. Open a **new** admin Terminal (so `lockboxctl` is found) and run `lockboxctl guide`. It walks you through:
   - `lockboxctl filters open` → quit Chrome fully, reopen → puzzle icon → **uBlock Origin Lite** → gear → **Custom filters** → paste (already on your clipboard) → save → check a YouTube video shows only the video and title → `lockboxctl filters lock`
   - `lockboxctl verify` — every line `[OK]`
4. Open the apps you use day to day (so they're recorded as trusted), then:
   ```
   lockboxctl arm YOUR_USERNAME            # 30 min wait, 2 h admin window
   lockboxctl arm YOUR_USERNAME 1440 120   # 24 h wait instead
   ```
   Type `ARM`, then sign out and back in.

### NextDNS (optional)
```
lockboxctl nextdns            # how to get a config ID + current status
lockboxctl nextdns abc123     # install or switch (admin Terminal, while unlocked)
```
Leave NextDNS's **Block Bypass Methods** off — it would block Chrome's encrypted DNS.

## Daily use

- **Need admin?** Start menu → **Lockbox** → *Request unlock* → wait. Then right-click Start → Terminal (Admin), installers, Windows Update all work.
- **Done?** Lockbox → *Re-lock now* (or it re-locks itself). Programs you installed while unlocked are trusted automatically on re-lock.
- **Changed your mind?** Lockbox → *Cancel unlock request*.
- Blocks stay on while unlocked; only the app guard pauses.

## Customising (admin Terminal, while unlocked)

| Change | How |
|---|---|
| What YouTube hides | `lockboxctl filters open`, edit in uBOL's Custom filters, `lockboxctl filters lock` |
| Blocked browsers | edit `C:\Program Files\Lockbox\browsers-windows.txt` |
| Trust one more program | `lockboxctl trust C:\path\to\program.exe` |
| Unlock wait / admin window | `lockboxctl arm USER DELAY_MIN WINDOW_MIN` |
| Chrome rules | edit `shared/build-chrome-policy.py`, run `./build.sh`, re-install |

## What it does **not** stop (honest threat model)

| Way around | Cost to you |
|---|---|
| Request unlock, then remove Lockbox as admin | The unlock wait — that's the design |
| **Without BitLocker:** boot from a USB stick or the recovery environment and edit files offline | 15+ minutes and a second computer — turn on BitLocker / Device encryption to close this |
| "Reset this PC" from the sign-in screen | Wipes your apps and settings |
| Other devices | Not covered |
| A Short opened as `/watch?v=…` in Chrome | Plays |

Side effects: Microsoft Edge is closed whenever it opens (WebView2 apps keep working). Programs from a new publisher installed into your user folder while locked won't open until your next unlock → re-lock. YouTube embeds inside other apps don't play.

## Troubleshooting

- **`verify` says "YouTube still resolves for other apps".** Check `Get-DnsClientNrptRule`. If the rules exist but don't apply, add the domains in `youtube-domains.txt` to your NextDNS Denylist (Chrome is unaffected).
- **A program closes right after opening.** `lockboxctl status` shows why. Unlock, then `lockboxctl trust <path>` (or just re-lock).
- **Chrome can't load pages on hotel/campus Wi-Fi.** Chrome's encrypted DNS can't pass a Wi-Fi login page; use the sign-in window Windows opens when you join the network.
- **Microsoft Defender warns about the hosts file** ("HostsFileHijack"). Lockbox edits the hosts file on purpose to block Instagram; choose *Allow on device* while unlocked.
- **Remove everything:** unlock, then in an admin Terminal: `& "$env:ProgramFiles\Lockbox\uninstall.ps1"`

## Files

```
install.ps1                 installer (does not arm)
src\enforcer.ps1            SYSTEM loop
src\trust-scan.ps1          records trusted publishers / files
src\lockboxctl.ps1 (.cmd)   guide · verify · nextdns · filters · arm · trust · status
src\LockboxApp.ps1          the Lockbox app
src\chrome-policy.json      Chrome rules (generated from shared/)
src\ubol-policy.json        uBlock Origin Lite settings, locked/open (generated)
src\hosts-block.txt         hosts entries (all apps)
src\youtube-domains.txt     blocked for every app except Chrome
src\ubol-filters.txt        YouTube hiding filters
src\browsers-windows.txt    browsers to close (file names + publishers)
src\uninstall.ps1           full removal (admin only)
```
