#!/bin/bash
# Lockbox 1.3.3 installer — sudo bash install.sh [NEXTDNS_CONFIG_ID]
# Installs every layer but does NOT take admin away. Arming is a separate, explicit step.
set -e
[ "$(id -u)" = 0 ] || { echo "Run with: sudo bash install.sh [NEXTDNS_ID]"; exit 1; }
[ "$(uname)" = Darwin ] || { echo "macOS only"; exit 1; }
SRC="$(cd "$(dirname "$0")/src" && pwd)"
BASE=/Library/Lockbox
MP="/Library/Managed Preferences"
ME="${SUDO_USER:-$(stat -f %Su /dev/console)}"
NEXTDNS_ID="$1"

grep -qs '^ARMED=1' "$BASE/config" && echo "Lockbox is armed — re-installing keeps your settings."

echo "== 1/6 Files"
mkdir -p "$BASE/inbox" "$BASE/backup"
for f in enforcer.sh trust-scan.sh browsers.txt hosts-block.txt youtube-hosts.txt youtube-domains.txt chrome-policy.plist Lockbox-Chrome.mobileconfig Lockbox-Chrome-setup.mobileconfig ubol-filters.txt lockboxctl uninstall.sh; do
  cp -f "$SRC/$f" "$BASE/$f"
done
chown -R root:wheel "$BASE"
chmod 755 "$BASE" "$BASE/enforcer.sh" "$BASE/trust-scan.sh" "$BASE/lockboxctl" "$BASE/uninstall.sh"
chmod 644 "$BASE"/*.txt "$BASE"/*.plist "$BASE"/*.mobileconfig
chmod 1777 "$BASE/inbox"
[ -f "$BASE/config" ] || printf 'TARGET_USER=\nARMED=0\nUNLOCK_DELAY=1800\nADMIN_WINDOW=7200\nEXEMPT=""\n' > "$BASE/config"
chmod 644 "$BASE/config"
ln -sf "$BASE/lockboxctl" /usr/local/bin/lockboxctl 2>/dev/null || { mkdir -p /usr/local/bin; ln -sf "$BASE/lockboxctl" /usr/local/bin/lockboxctl; }
touch /var/log/lockbox.log; chmod 644 /var/log/lockbox.log

echo "== 2/6 Clearing old Chrome rules that would block the new ones"
# Hand-made, flag-locked (schg) Chrome policy files override real profiles and can't be replaced by macOS.
for f in "$MP/com.google.Chrome.plist" "$MP"/*/com.google.Chrome.plist; do
  [ -e "$f" ] || continue
  if ls -lO "$f" | grep -q schg; then
    cp -p "$f" "$BASE/backup/$(echo "$f" | tr '/ ' '__')" 2>/dev/null || true
    chflags noschg "$f" && rm -f "$f" && echo "   removed locked leftover: $f"
  fi
done
# User-level Chrome "policies" written with `defaults write` (left over from other blockers).
if sudo -u "$ME" defaults read com.google.Chrome >/dev/null 2>&1; then
  sudo -u "$ME" defaults export com.google.Chrome "$BASE/backup/user-chrome-prefs.plist" 2>/dev/null || true
  sudo -u "$ME" defaults delete com.google.Chrome && echo "   cleared user-level Chrome policies (backup in $BASE/backup)"
fi

echo "== 3/6 NextDNS (optional)"
if [ -z "$NEXTDNS_ID" ] && [ ! -x /usr/local/bin/nextdns ] && [ -t 0 ]; then
  echo "   NextDNS filters DNS on every network. Free account: https://nextdns.io → Setup tab → 6-character ID."
  read -r -p "   NextDNS config ID (press Enter to skip): " NEXTDNS_ID
fi
if [ -n "$NEXTDNS_ID" ]; then
  "$BASE/lockboxctl" nextdns "$NEXTDNS_ID" | sed 's/^/   /'
elif [ -x /usr/local/bin/nextdns ]; then
  echo "   already installed: $(/usr/local/bin/nextdns status)"
else
  echo "   skipped — set it up later with: lockboxctl nextdns"
fi

echo "== 4/6 Lockbox app"
rm -rf /Applications/Lockbox.app
osacompile -o /Applications/Lockbox.app "$SRC/Lockbox.applescript"
chown -R root:wheel /Applications/Lockbox.app

echo "== 5/6 Enforcer service"
cp -f "$SRC/com.lockbox.enforcer.plist" /Library/LaunchDaemons/
chown root:wheel /Library/LaunchDaemons/com.lockbox.enforcer.plist
chmod 644 /Library/LaunchDaemons/com.lockbox.enforcer.plist
launchctl bootout system/com.lockbox.enforcer 2>/dev/null || true
sleep 1
launchctl bootstrap system /Library/LaunchDaemons/com.lockbox.enforcer.plist
sleep 6

echo "== 6/6 Chrome profile"
UP=$(ls "$MP"/com.google.Chrome.extensions.ddkjiahejlhfcafbddmgiahcphecmpfh.plist "$MP"/*/com.google.Chrome.extensions.ddkjiahejlhfcafbddmgiahcphecmpfh.plist 2>/dev/null | head -1)
if plutil -p "$UP" 2>/dev/null | grep -q picker && grep -q DnsOverHttpsTemplates "$MP/com.google.Chrome.plist" 2>/dev/null; then
  echo "   Chrome profile already active and locked"
elif [ -n "$UP" ]; then
  echo "   SETUP profile is active. When the filters are pasted, install the normal one:"
  echo "   open /Library/Lockbox/Lockbox-Chrome.mobileconfig"
else
  launchctl asuser "$(id -u "$ME")" sudo -u "$ME" open "$BASE/Lockbox-Chrome-setup.mobileconfig" || true
  echo "   ACTION NEEDED — run: lockboxctl guide"
fi
echo
echo "Installed. Status: $(cat $BASE/status.txt 2>/dev/null)"
echo "Next step: lockboxctl guide"
