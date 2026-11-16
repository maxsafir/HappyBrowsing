# Lockbox

**A commitment device for your computer.** Lockbox blocks the distracting parts of the internet *and* takes away your own admin rights, so you can't undo it in a moment of weakness. When you genuinely need admin — to install an app or run an update — you request it and wait 30 minutes. The wait is the point.

**Website:** https://maxsafir.github.io/lockbox · **Downloads:** [Mac](docs/downloads/lockbox-mac.zip) · [Windows](docs/downloads/lockbox-windows.zip)

| | [macOS](mac/README.md) | [Windows](windows/README.md) |
|---|---|---|
| YouTube: video pages only, only in Chrome | ✔ | ✔ |
| Video and title only (no search, comments, recommendations) | ✔ | ✔ |
| Instagram blocked everywhere | ✔ | ✔ |
| Other browsers closed | ✔ | ✔ |
| App guard (re-signed / unknown apps closed while locked) | ✔ code signatures | ✔ Authenticode |
| Your account is Standard, 30-min unlock | ✔ | ✔ |
| NextDNS (optional) | ✔ | ✔ |
| Tested on real hardware | ✔ | not yet |

## How it works

A small enforcer runs as root (Mac: launchd daemon) or SYSTEM (Windows: scheduled task) and checks everything every 5 seconds. It keeps your account out of the admin group, re-applies the blocks if anything changes, closes blocked or untrusted apps, and runs the unlock timer. Everything else uses built-in mechanisms:

- **Chrome policies** limit YouTube to `/watch` pages, block Instagram, disable incognito and guest mode, and force-install extensions whose settings can't be changed.
- **Split DNS:** YouTube's domains don't resolve for any app except Chrome, which uses its own encrypted DNS.
- **hosts file** blocks Instagram for every app.

A Standard user can't stop a root/SYSTEM process, edit system files, or change machine policies — that's the whole lock.

## Repository layout

```
mac/        macOS version (install.sh, src/, README)
windows/    Windows version (install.ps1, src\, README)
shared/     rules used by both: Chrome policy builder, hosts list, YouTube domains, uBOL filters
docs/       website (GitHub Pages) + download zips
build.sh    regenerates Chrome rules and rebuilds docs/downloads/*.zip
```

After editing anything in `shared/`, run `./build.sh` and commit.

## Honest limits

Lockbox is built against impulses, not against a determined person with physical access and an afternoon: you can always request an unlock and then remove it, erase the machine, or (on Windows without BitLocker) edit files from a USB stick. See each platform's README for the full threat model.
