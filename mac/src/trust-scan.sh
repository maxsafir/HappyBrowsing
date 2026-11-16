#!/bin/bash
# Records which apps are trusted to run while Lockbox is locked.
#   trust-scan.sh            scan /Applications and /Library (used on every re-lock)
#   trust-scan.sh <user>     also scan that user's ~/Applications and ~/Library (used when arming)
# Trusted = signed by a developer ID found here, or (for ad-hoc/unsigned apps) this exact build.
BASE=/Library/Lockbox
T=$BASE/trust
mkdir -p "$T"
U="$1"
DIRS=(/Applications /Library)
if [ -n "$U" ]; then
  H=$(dscl . -read "/Users/$U" NFSHomeDirectory 2>/dev/null | awk '{print $2}')
  [ -d "$H" ] && DIRS+=("$H/Applications" "$H/Library")
fi
teams=$(mktemp); hashes=$(mktemp)
cat "$T/teams.txt" >> "$teams" 2>/dev/null
cat "$T/cdhashes.txt" >> "$hashes" 2>/dev/null
echo 59GAB85EFG >> "$teams"   # Apple

record() {
  local out team cd
  out=$(codesign -dv --verbose=4 "$1" 2>&1)
  team=$(sed -n 's/^TeamIdentifier=//p' <<<"$out" | head -1)
  cd=$(sed -n 's/^CDHash=//p' <<<"$out" | head -1)
  if [ -n "$team" ] && [ "$team" != "not set" ]; then echo "$team" >> "$teams"
  elif [ -n "$cd" ]; then echo "$cd" >> "$hashes"; fi
}

# Skip private data folders (avoids macOS privacy prompts; no apps live there).
find "${DIRS[@]}" \( -path '*/Library/Containers' -o -path '*/Library/Group Containers' -o -path '*/Library/Mail' \
     -o -path '*/Library/Messages' -o -path '*/Library/Safari' -o -path '*/Library/Mobile Documents' \
     -o -path '*/Library/CloudStorage' -o -path '*/Library/Caches' -o -path '/Library/Lockbox' \) -prune \
     -o -name '*.app' -type d -print 2>/dev/null | while IFS= read -r app; do record "$app"; done

# Anything running right now is trusted too.
ps -axo comm= | grep '\.app/Contents/MacOS/' | while IFS= read -r p; do record "${p%%.app/Contents/MacOS/*}.app"; done

sort -u "$teams" | grep -v '^$' > "$T/teams.txt"
sort -u "$hashes" | grep -v '^$' > "$T/cdhashes.txt"
rm -f "$teams" "$hashes" /var/run/lockbox-sig.txt
chown -R root:wheel "$T"; chmod 755 "$T"; chmod 644 "$T"/*.txt
echo "trusted: $(wc -l < "$T/teams.txt" | tr -d ' ') developers, $(wc -l < "$T/cdhashes.txt" | tr -d ' ') ad-hoc builds"
