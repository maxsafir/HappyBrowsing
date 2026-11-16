# Lockbox for macOS 1.3.6

**A commitment device for your Mac.** Lockbox blocks the distracting parts of the internet *and* takes away your own admin rights, so you can't undo it in a moment of weakness. When you genuinely need admin (to install an app, run `sudo`, update macOS), you request it and wait. The wait is the point.

| What | How |
|---|---|
| YouTube: video pages only, Chrome only | No home feed, Shorts, search, channels or recommendations. Videos opened from Google still play in Chrome. YouTube doesn't load in any other app (VS Code's browser, other apps' web views, scripts). |
| Instagram: gone | Blocked in Chrome, in `/etc/hosts`, and (optionally) by NextDNS on every network. |
| Chrome only | Safari, Firefox, Brave, Edge, Arc and ~30 other browsers are closed within 5 seconds, matched by code signature, so renaming doesn't help. |
| App guard | While locked, only apps from developers already on your Mac can run. Re-signed or home-made browsers are closed. |
| Video and title only | No search bar, logo, comments, sidebar or end screens on video pages. Search and channel pages stay blank even when YouTube switches pages without reloading. |
| No escape hatches | Incognito and guest mode off, other extensions can't run on YouTube, the hiding filters can't be edited while locked. |
| Your account is Standard | No `sudo`, no removing profiles, no editing system files. |
| Delayed unlock | Lockbox app → *Request unlock* → after 30 min you're admin. *Re-lock* (or 2 h timeout) ends it. |

Tested on an Apple Silicon Mac with Google Chrome, November 2026.

---

## How it works

```
 ┌─────────────── Lockbox enforcer (root launchd daemon, every 5 s) ────────────────┐
 │  • keeps your account out of the admin group (unless unlocked)                   │
 │  • restores /etc/hosts, /etc/resolver, sudoers and PAM if changed                │
 │  • app guard: reads each running app's code signature; closes blocked browsers,  │
 │    and (while locked) apps from untrusted developers or untrusted ad-hoc builds  │
 │  • keeps NextDNS running and set as system DNS                                   │
 │  • if the Chrome profile disappears while armed → closes Chrome until it's back  │
 │  • runs the unlock state machine:  LOCKED → PENDING (wait) → UNLOCKED → LOCKED   │
 └───────────────────────────────────────────────────────────────────────────────────┘
 /etc/hosts            → Instagram blocked for every app, Chrome included
 NextDNS (on this Mac) → YouTube domains forwarded to a dead endpoint for every app;
                         Chrome uses its own encrypted DNS, so only Chrome can reach YouTube
 Chrome (via profile)  → its own encrypted DNS, so only Chrome can reach YouTube;
                         URL rules allow video pages only; no-settings extension hides the rest
 Lockbox.app           → drops a request file the enforcer reads (no privileges needed)
```

The security comes from one fact: **a Standard user can't stop a root daemon, remove a system profile, edit root-owned files, or add apps to /Applications.**

---

## Install

You need: an admin account (for setup only) and Google Chrome. NextDNS is optional.

**The short version:** run the installer, then keep running `lockboxctl guide`. It checks what's done and prints the exact next step.

1. **Unzip** `lockbox-mac` into Downloads.
2. **Install** (Terminal):
   ```
   cd ~/Downloads/lockbox-mac && sudo bash install.sh
   ```
   It asks for a NextDNS config ID — press Enter to skip. (`lockboxctl nextdns` explains how to get one; `sudo lockboxctl nextdns abc123` sets it up any time.)
3. **Install the setup profile:** System Settings → General → **Device Management** → double-click **Lockbox – Chrome (setup)** → **Install**. Quit Chrome (⌘Q) and reopen it.
4. **Paste the YouTube filters:** `pbcopy < /Library/Lockbox/ubol-filters.txt`, then in Chrome: puzzle icon → **uBlock Origin Lite** → gear → **Custom filters** → paste → save. Open a YouTube video: only the video and its title should show.
5. **Lock the filters:** `open /Library/Lockbox/Lockbox-Chrome.mobileconfig` → Device Management → double-click **Lockbox – Chrome** → **Install**. **Restart the Mac.**
6. **Check every layer:** `lockboxctl verify` — every line ✔.
7. **Open the apps you use day to day** (so they're recorded as trusted), then **arm it**:
   ```
   sudo lockboxctl arm YOUR_USERNAME            # 30 min wait, 2 h admin window
   sudo lockboxctl arm YOUR_USERNAME 1440 120   # 24 h wait instead
   ```
   Type `ARM` to confirm, then restart once more.

### NextDNS (optional)

```
lockboxctl nextdns            # how to get a config ID + current status
sudo lockboxctl nextdns abc123   # install or switch (while unlocked)
```
In the NextDNS dashboard you can add Instagram under Parental Control. Leave **Block Bypass Methods** off — it would block Chrome's encrypted DNS.

## Upgrading from an earlier version

1. Lockbox app → **Request unlock**, wait until you're admin.
2. Move the old `lockbox-mac` folder to the Trash, unzip the new one into Downloads, then:
   ```
   cd ~/Downloads/lockbox-mac && sudo bash install.sh
   ```
   (Your NextDNS setup is kept.)
3. Run `lockboxctl guide` and follow it until it says "Arm it".
4. `lockboxctl verify` — all ✔.
5. Open the apps you use, then `sudo lockboxctl arm YOUR_USERNAME` — this re-locks and records your trusted apps.

---

## Daily use

- **Need admin?** Open **Lockbox** (Applications) → *Request unlock* → wait → you're admin. Install things, run `sudo`, update macOS.
- **Done?** Lockbox → *Re-lock now*. It also re-locks itself after the admin window. On re-lock, apps you installed into /Applications become trusted automatically.
- **Changed your mind during the wait?** Lockbox → *Cancel unlock request*.
- Blocks stay on even while you're unlocked; only the app guard pauses.
- `lockboxctl verify` and `lockboxctl status` work any time without sudo.

Tip: unlock about once a month to let macOS security updates install.

---

## Customising (while unlocked)

| Change | Where | Apply with |
|---|---|---|
| Instagram-style blocks (all apps, incl. Chrome) | `src/hosts-block.txt` | `sudo bash install.sh` |
| YouTube-style blocks (all apps except Chrome) | `src/youtube-domains.txt` | `sudo bash install.sh` |
| Browsers to close | `src/browsers.txt` (signing identifiers) | `sudo bash install.sh` |
| What YouTube hides | `src/ubol-filters.txt` | install the setup profile, edit uBOL Custom filters, install the normal profile |
| Chrome URL rules / extensions | `shared/build-chrome-policy.py` (repo root) | `./build.sh`, re-install the profile, restart |
| Trust one more app (e.g. something you built) | — | `sudo lockboxctl trust /path/To.app` |
| Unlock wait / admin window | — | `sudo lockboxctl arm USER DELAY_MIN WINDOW_MIN` |

---

## What it does **not** stop (honest threat model)

| Way around | Cost to you |
|---|---|
| Request unlock, then dismantle Lockbox as admin | The unlock wait — that's the design |
| Erase the Mac in Recovery | Everything on the disk |
| Write your own browser that does its own encrypted DNS and is signed by an already-trusted developer | Not realistically possible without that developer's signing key |
| Other devices (phone, tablet) | Not covered |
| A Short opened as `/watch?v=…` in Chrome | Plays |

Side effects to know about: apps from a **new** developer installed while locked won't open until your next unlock → re-lock; self-updating apps update only while unlocked; YouTube embeds inside other apps don't play.

Recovery Mode on Apple Silicon asks for an **administrator** password before giving access to Terminal or security settings. With Lockbox armed there is no admin account, so the expected outcome is that erasing the Mac is the only option there. (Not yet tested on a Mac with zero admins.)

---

## Troubleshooting

**`verify` says "YouTube still resolves for other apps".**
YouTube is blocked for other apps by the NextDNS app on your Mac (a local, root-owned setting; changing your NextDNS account online doesn't undo it). Install it with `sudo lockboxctl nextdns YOUR_ID` while unlocked. Chrome isn't affected because it uses its own encrypted DNS. Never put YouTube in `/etc/hosts`: Chrome reads that file too, and videos fail with "no internet connection".

**An app won't open (it closes immediately).**
`lockboxctl status` shows why. Usually it's from a developer that wasn't on the Mac when you armed. Unlock, then `sudo lockboxctl trust /Applications/That.app` (or just re-lock — apps in /Applications are trusted on re-lock).

**Chrome can't load anything on hotel/campus Wi-Fi.**
Chrome uses encrypted DNS, which can't pass a Wi-Fi login page. Use the macOS login window that pops up when you join the network; Chrome works once you're signed in.

**`chrome://policy` shows old or broken rules, not Lockbox's.**
Another blocker left Chrome policy files in `/Library/Managed Preferences` locked with the `schg` flag. `install.sh` removes these (backups in `/Library/Lockbox/backup`). Re-run it, restart.

**Chrome keeps closing.**
While locked, Chrome only runs with the normal (locked) Lockbox – Chrome profile. If it was removed, or the setup version is still installed, request an unlock, install `/Library/Lockbox/Lockbox-Chrome.mobileconfig`, restart.

**YouTube redesigned and something shows again.**
Request an unlock, install the setup profile, update the filter in uBOL's Custom filters (DevTools are blocked on YouTube, so look up the new element name on another device), then install the normal profile again.

**NextDNS stopped filtering near the end of the month.**
The free plan covers 300,000 queries/month. Instagram stays blocked by `/etc/hosts` and Chrome; YouTube stays limited by `/etc/resolver` and Chrome.

**Locked out and want everything gone.**
Request an unlock, wait, then: `sudo /Library/Lockbox/uninstall.sh`.

---

## Files

```
install.sh                      installer (does not arm)
src/enforcer.sh                 root daemon
src/trust-scan.sh               records trusted developers / builds
src/lockboxctl                  guide · verify · nextdns · arm · trust · status
src/Lockbox.applescript         the Lockbox app
src/com.lockbox.enforcer.plist  LaunchDaemon
src/Lockbox-Chrome.mobileconfig Chrome rules, filters locked (generated)
src/Lockbox-Chrome-setup.mobileconfig  same rules, uBOL filter editor open (generated)
src/ubol-filters.txt            YouTube hiding filters for uBlock Origin Lite
src/chrome-policy.plist         same rules as a plain plist (generated)
src/hosts-block.txt             /etc/hosts entries (all apps)
src/youtube-domains.txt         blocked for every app except Chrome
src/browsers.txt                signing identifiers of browsers to close
src/uninstall.sh                full removal (root only)
```

Credits: [uBlock Origin Lite](https://github.com/uBlockOrigin/uBOL-home), [Mono for YouTube](https://chromewebstore.google.com/detail/nppiofogichmlkadpbpkpojpidedifeh) (hides recommendations), [NextDNS](https://nextdns.io) CLI.
