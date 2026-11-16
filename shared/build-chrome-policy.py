#!/usr/bin/env python3
"""Builds Chrome's Lockbox rules for both platforms.
macOS:
  src/Lockbox-Chrome.mobileconfig        locked: uBlock Origin Lite's dashboard, picker and filter editor are disabled
  src/Lockbox-Chrome-setup.mobileconfig  setup: same rules, but uBOL's Custom filters pane is available
  Both use the same identifier, so installing one replaces the other.
Windows:
  windows/src/chrome-policy.json  written to HKLM\\SOFTWARE\\Policies\\Google\\Chrome by the enforcer
  windows/src/ubol-policy.json    uBOL managed settings, "locked" and "open" variants

Edit the lists below, then run:  python3 shared/build-chrome-policy.py   (or ./build.sh)
Re-install the profile afterwards (same identifier, so it replaces the old one).
"""
import plistlib, uuid, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "mac" / "src"
WIN = ROOT / "windows" / "src"
STORE = "https://clients2.google.com/service/update2/crx"

# Extensions force-installed into Chrome (no settings to switch off).
EXTENSIONS = [
    "nppiofogichmlkadpbpkpojpidedifeh",  # Mono for YouTube (CSS-only: hides feed, sidebar, Shorts shelves, end cards)
    "aklbieaecfoidlgjmiipikpgmhbcjoja",  # YouTube Recommendation Blocker (backup)
    "ddkjiahejlhfcafbddmgiahcphecmpfh",  # uBlock Origin Lite: holds the custom hiding filters (src/ubol-filters.txt)
]
UBOL = "ddkjiahejlhfcafbddmgiahcphecmpfh"
UBOL_LOCKED = {"disabledFeatures": ["dashboard", "develop", "filteringMode", "picker", "zapper"],
               "noFiltering": ["-*"], "disableFirstRunPage": True}
UBOL_SETUP = {"disabledFeatures": ["filteringMode", "zapper"], "noFiltering": ["-*"], "disableFirstRunPage": True}
# Sites blocked in Chrome. Paths in URL_ALLOW win over the broader block.
URL_BLOCK = ["youtube.com", "instagram.com", "cdninstagram.com"]
URL_ALLOW = ["youtube.com/watch", "youtube.com/embed", "youtube.com/redirect",
             "accounts.youtube.com", "consent.youtube.com", "youtube.com/signin"]
# Other extensions are not allowed to run on these sites (so nothing can undo the hiding).
PROTECTED_HOSTS = ["*://*.youtube.com", "*://*.instagram.com", "*://*.youtube-nocookie.com"]

ext_settings = {"*": {"runtime_blocked_hosts": PROTECTED_HOSTS}}
for eid in EXTENSIONS:
    ext_settings[eid] = {"installation_mode": "force_installed", "update_url": STORE,
                         "runtime_allowed_hosts": ["*://*.youtube.com", "*://*.youtube-nocookie.com"]}
policy = {
    "URLBlocklist": URL_BLOCK,
    "URLAllowlist": URL_ALLOW,
    "ExtensionSettings": ext_settings,
    "IncognitoModeAvailability": 1,          # incognito off
    "BrowserGuestModeEnabled": False,        # guest mode off
    # Chrome alone resolves through its own encrypted DNS, so it is the only app that can reach
    # YouTube (the system resolver blocks YouTube for everything else). install.sh swaps the
    # template for your NextDNS endpoint when you give it a NextDNS ID.
    "DnsOverHttpsMode": "secure",
    "DnsOverHttpsTemplates": "https://chrome.cloudflare-dns.com/dns-query",
    "ExtensionDeveloperModeSettings": 1,     # no unpacked extensions
    "DeveloperToolsAvailability": 1,         # no DevTools on force-installed extensions
    "DeveloperToolsAvailabilityBlocklist": ["youtube.com", "instagram.com"],
}
plistlib.dump(policy, open(SRC / "chrome-policy.plist", "wb"))

ns = uuid.UUID("6f1c2a52-0b5e-4f0e-9a7e-1c0ffee10c4b")

def profile(ubol_settings, name, desc):
    inner = {"PayloadType": "com.apple.ManagedClient.preferences", "PayloadVersion": 1,
             "PayloadIdentifier": "com.lockbox.chrome.prefs",
             "PayloadUUID": str(uuid.uuid5(ns, "inner-" + name + "-1.3.1")).upper(),
             "PayloadDisplayName": "Lockbox Chrome rules", "PayloadEnabled": True,
             "PayloadContent": {
                 "com.google.Chrome": {"Forced": [{"mcx_preference_settings": policy}]},
                 "com.google.Chrome.extensions." + UBOL: {"Forced": [{"mcx_preference_settings": ubol_settings}]},
             }}
    return {"PayloadType": "Configuration", "PayloadVersion": 1,
            "PayloadIdentifier": "com.lockbox.chrome",
            "PayloadUUID": str(uuid.uuid5(ns, "outer-" + name + "-1.3.1")).upper(),
            "PayloadDisplayName": "Lockbox – Chrome" + ("" if name == "locked" else " (setup)"),
            "PayloadDescription": desc, "PayloadOrganization": "Lockbox",
            "PayloadScope": "System", "PayloadContent": [inner]}

plistlib.dump(profile(UBOL_LOCKED, "locked",
    "Lockbox rules for Google Chrome: YouTube video pages only, Instagram blocked, filters locked."),
    open(SRC / "Lockbox-Chrome.mobileconfig", "wb"))
plistlib.dump(profile(UBOL_SETUP, "setup",
    "SETUP version: same rules, but uBlock Origin Lite's Custom filters pane is open so you can paste the filters. Replace with the normal profile afterwards."),
    open(SRC / "Lockbox-Chrome-setup.mobileconfig", "wb"))
import json
json.dump(policy, open(WIN / "chrome-policy.json", "w"), indent=2)
json.dump({"id": UBOL, "locked": UBOL_LOCKED, "open": UBOL_SETUP}, open(WIN / "ubol-policy.json", "w"), indent=2)
print("wrote mac/src (plist + 2 mobileconfigs) and windows/src (chrome-policy.json, ubol-policy.json)")
