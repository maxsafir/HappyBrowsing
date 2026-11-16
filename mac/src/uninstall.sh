#!/bin/bash
# Removes HappyBrowsing completely. Needs root, so it only works while unlocked.
[ "$(id -u)" = 0 ] || { echo "run with sudo (only possible while unlocked)"; exit 1; }
read -r -p "Remove HappyBrowsing and all its blocks? Type REMOVE: " a; [ "$a" = REMOVE ] || exit 1
launchctl bootout system/com.happybrowsing.enforcer 2>/dev/null
rm -f /Library/LaunchDaemons/com.happybrowsing.enforcer.plist
awk '/^# >>> (happybrowsing|lockbox)$/{f=1;next}/^# <<< (happybrowsing|lockbox)$/{f=0;next}!f' /etc/hosts > /tmp/h && cat /tmp/h > /etc/hosts && rm /tmp/h
for f in /etc/resolver/*; do head -1 "$f" 2>/dev/null | grep -q "^# lockbox" && rm -f "$f"; done
profiles remove -identifier com.lockbox.chrome 2>/dev/null || echo "Remove 'HappyBrowsing – Chrome' in System Settings → General → Device Management."
if [ -x /usr/local/bin/nextdns ]; then /usr/local/bin/nextdns deactivate; /usr/local/bin/nextdns uninstall; rm -f /usr/local/bin/nextdns; fi
rm -rf /Applications/HappyBrowsing.app /Library/HappyBrowsing /usr/local/bin/happybrowsing /var/run/happybrowsing-bundles.txt
dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
echo "HappyBrowsing removed. Restart the Mac."
