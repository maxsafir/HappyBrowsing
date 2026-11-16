#!/bin/bash
# Removes Lockbox completely. Needs root, so it only works while unlocked.
[ "$(id -u)" = 0 ] || { echo "run with sudo (only possible while unlocked)"; exit 1; }
read -r -p "Remove Lockbox and all its blocks? Type REMOVE: " a; [ "$a" = REMOVE ] || exit 1
launchctl bootout system/com.lockbox.enforcer 2>/dev/null
rm -f /Library/LaunchDaemons/com.lockbox.enforcer.plist
awk '/^# >>> lockbox/{f=1;next}/^# <<< lockbox/{f=0;next}!f' /etc/hosts > /tmp/h && cat /tmp/h > /etc/hosts && rm /tmp/h
for f in /etc/resolver/*; do head -1 "$f" 2>/dev/null | grep -q "^# lockbox" && rm -f "$f"; done
profiles remove -identifier com.lockbox.chrome 2>/dev/null || echo "Remove 'Lockbox – Chrome' in System Settings → General → Device Management."
if [ -x /usr/local/bin/nextdns ]; then /usr/local/bin/nextdns deactivate; /usr/local/bin/nextdns uninstall; rm -f /usr/local/bin/nextdns; fi
rm -rf /Applications/Lockbox.app /Library/Lockbox /usr/local/bin/lockboxctl /var/run/lockbox-bundles.txt
dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
echo "Lockbox removed. Restart the Mac."
