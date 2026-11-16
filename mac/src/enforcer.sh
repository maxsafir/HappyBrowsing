#!/bin/bash
# HappyBrowsing enforcer — runs as root from launchd (com.happybrowsing.enforcer), every 5 seconds.
#   locked   -> target user is Standard, every block enforced, app guard on
#   pending  -> unlock requested, still locked, waits UNLOCK_DELAY seconds
#   unlocked -> target user is admin (blocks stay on, app guard off) until Re-lock or ADMIN_WINDOW ends

BASE=/Library/HappyBrowsing
CONF=$BASE/config
STATEF=$BASE/state
INBOX=$BASE/inbox
STATUS=$BASE/status.txt
TRUST=$BASE/trust
LOG=/var/log/happybrowsing.log
HOSTS=/etc/hosts
MP="/Library/Managed Preferences"
NEXTDNS=/usr/local/bin/nextdns
SIGCACHE=/var/run/happybrowsing-sig.txt
MARK=nppiofogichmlkadpbpkpojpidedifeh
export PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin

log() { echo "$(date '+%F %T') $*" >> "$LOG"; }

load() {
  TARGET_USER=""; ARMED=0; UNLOCK_DELAY=1800; ADMIN_WINDOW=7200; EXEMPT=""
  [ -f "$CONF" ] && . "$CONF"
  STATE=locked; UNLOCK_AT=0; RELOCK_AT=0
  [ -f "$STATEF" ] && . "$STATEF"
}
save_state() {
  printf 'STATE=%s\nUNLOCK_AT=%s\nRELOCK_AT=%s\n' "$STATE" "$UNLOCK_AT" "$RELOCK_AT" > "$STATEF.tmp"
  mv -f "$STATEF.tmp" "$STATEF"; chmod 644 "$STATEF"
}
is_admin() { dsmemberutil checkmembership -U "$1" -G admin 2>/dev/null | grep -q "is a member"; }
promote()  { dseditgroup -o edit -a "$1" -t user admin 2>/dev/null; dscacheutil -flushcache; log "promoted $1"; }
demote()   { dseditgroup -o edit -d "$1" -t user admin 2>/dev/null; dscacheutil -flushcache; log "demoted $1"; }
in_list()  { local x; for x in $2; do [ "$x" = "$1" ] && return 0; done; return 1; }

# ---------- admin group ----------
enforce_admins() {
  [ "$ARMED" = 1 ] || return
  local allowed="root $EXEMPT" m u
  [ "$STATE" = unlocked ] && allowed="$allowed $TARGET_USER"
  for m in $(dscl . -read /Groups/admin GroupMembership 2>/dev/null | sed 's/^GroupMembership://'); do
    in_list "$m" "$allowed" || demote "$m"
  done
  for u in $(dscl . -list /Users UniqueID | awk '$2>=500{print $1}'); do
    in_list "$u" "$allowed" && continue
    is_admin "$u" && demote "$u"
  done
  if [ "$STATE" = unlocked ] && ! is_admin "$TARGET_USER"; then promote "$TARGET_USER"; fi
}

# ---------- sudoers / pam (restored while locked) ----------
enforce_auth_files() {
  [ "$ARMED" = 1 ] && [ "$STATE" != unlocked ] && [ -d "$BASE/snap" ] || return
  local f
  if ! cmp -s /etc/sudoers "$BASE/snap/sudoers"; then
    cp -f "$BASE/snap/sudoers" /etc/sudoers; chown root:wheel /etc/sudoers; chmod 440 /etc/sudoers; log "restored sudoers"
  fi
  for f in /etc/sudoers.d/*; do
    [ -e "$f" ] || continue
    [ -e "$BASE/snap/sudoers.d/$(basename "$f")" ] || { rm -f "$f"; log "removed $f"; }
  done
  for f in "$BASE"/snap/pam.d/*; do
    cmp -s "$f" "/etc/pam.d/$(basename "$f")" || { cp -f "$f" /etc/pam.d/; log "restored pam.d/$(basename "$f")"; }
  done
  for f in /etc/pam.d/*; do
    [ -e "$BASE/snap/pam.d/$(basename "$f")" ] || { rm -f "$f"; log "removed $f"; }
  done
}

# ---------- /etc/hosts (Instagram, every app incl. Chrome) ----------
# NOTE: Chrome reads /etc/hosts even with its own encrypted DNS, so YouTube must never be listed here.
enforce_hosts() {
  local want cur
  [ -f "$BASE/hosts-block.txt" ] || return
  want=$(cat "$BASE/hosts-block.txt")
  cur=$(awk '/^# >>> happybrowsing/{f=1;next}/^# <<< happybrowsing/{f=0;next}f' "$HOSTS")
  if [ "$cur" != "$want" ]; then
    awk '/^# >>> (happybrowsing|lockbox)$/{f=1;next}/^# <<< (happybrowsing|lockbox)$/{f=0;next}!f' "$HOSTS" | grep -v '# lockbox-test' > "$HOSTS.happybrowsing.tmp"
    { echo "# >>> happybrowsing"; printf '%s\n' "$want"; echo "# <<< happybrowsing"; } >> "$HOSTS.happybrowsing.tmp"
    cat "$HOSTS.happybrowsing.tmp" > "$HOSTS"; rm -f "$HOSTS.happybrowsing.tmp"
    chown root:wheel "$HOSTS"; chmod 644 "$HOSTS"
    dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
    log "hosts block re-applied"
  fi
}

# ---------- YouTube for every app except Chrome ----------
# Done by the NextDNS app on this Mac (see enforce_nextdns): every YouTube domain is forwarded to a
# dead endpoint. Chrome uses its own encrypted DNS, so it isn't affected. Old /etc/resolver files
# from 1.1–1.3.5 are removed here (macOS 26 ignores them).
cleanup_resolvers() {
  local f removed=0
  for f in /etc/resolver/*; do
    [ -f "$f" ] && head -1 "$f" 2>/dev/null | grep -q '^# lockbox' && { rm -f "$f"; removed=1; }
  done
  [ $removed = 1 ] && { killall -HUP mDNSResponder 2>/dev/null; log "removed old YouTube resolver files"; }
}

# ---------- Chrome profile present? ----------
CHROME_OK=1
ubol_open() { # true only if uBOL's settings are applied AND it's the setup (editable) variant
  local f
  for f in "$MP"/com.google.Chrome.extensions.ddkjiahejlhfcafbddmgiahcphecmpfh.plist "$MP"/*/com.google.Chrome.extensions.ddkjiahejlhfcafbddmgiahcphecmpfh.plist; do
    [ -f "$f" ] || continue
    plutil -p "$f" 2>/dev/null | grep -q picker && return 1 || return 0
  done
  return 1
}
check_chrome() {
  # OK = HappyBrowsing profile active, and (while locked) the LOCKED variant, so uBOL's filter editor stays closed.
  if grep -q "$MARK" "$MP/com.google.Chrome.plist" 2>/dev/null && \
     { [ "$STATE" = unlocked ] || ! ubol_open; }; then
    [ "$CHROME_OK" = 0 ] && log "chrome profile present again"; CHROME_OK=1
  else
    [ "$CHROME_OK" = 1 ] && log "chrome profile missing or still the setup version"; CHROME_OK=0
  fi
}

# ---------- app guard ----------
# Reads each running app's code signature (cached per executable + mtime).
#  - blocked browsers are matched by signing identifier, so renaming Info.plist doesn't help
#  - while locked, apps from developers not in the trust list, and ad-hoc/unsigned builds
#    not in the trust list, are closed (this is what stops re-signed browsers)
sig_info() { # app exe -> "ident<TAB>team<TAB>cdhash"
  local app="$1" exe="$2" m key line out ident team cd
  m=$(stat -f %m "$exe" 2>/dev/null) || return 1
  key="$exe|$m"
  line=$(awk -F '\t' -v k="$key" '$1==k{print $2"\t"$3"\t"$4; exit}' "$SIGCACHE" 2>/dev/null)
  if [ -z "$line" ]; then
    out=$(codesign -dv --verbose=4 "$app" 2>&1)
    ident=$(sed -n 's/^Identifier=//p' <<<"$out" | head -1)
    team=$(sed -n 's/^TeamIdentifier=//p' <<<"$out" | head -1)
    cd=$(sed -n 's/^CDHash=//p' <<<"$out" | head -1)
    [ -n "$ident" ] || ident=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null)
    line="${ident:--}	${team:-not set}	${cd:--}"
    printf '%s\t%s\n' "$key" "$line" >> "$SIGCACHE"
  fi
  printf '%s\n' "$line"
}
guard_apps() {
  local guard=0
  [ "$ARMED" = 1 ] && [ "$STATE" != unlocked ] && [ -s "$TRUST/teams.txt" ] && guard=1
  touch "$SIGCACHE"
  ps -axo pid=,comm= | grep '\.app/Contents/MacOS/' | while read -r pid path; do
    app="${path%%.app/Contents/MacOS/*}.app"
    info=$(sig_info "$app" "$path") || continue
    IFS=$'\t' read -r ident team cd <<<"$info"
    reason=""
    grep -qxF "$ident" "$BASE/browsers.txt" && reason="blocked browser"
    [ -z "$reason" ] && [ "$ARMED" = 1 ] && [ "$CHROME_OK" = 0 ] && [ "$ident" = com.google.Chrome ] && reason="Chrome profile missing or setup version"
    if [ -z "$reason" ] && [ $guard = 1 ]; then
      case "$app" in /System/*|/usr/*|/Library/Apple/*) ;;
        *) if [ "$team" = "not set" ]; then
             grep -qxF "$cd" "$TRUST/cdhashes.txt" || reason="untrusted ad-hoc/unsigned build"
           else
             grep -qxF "$team" "$TRUST/teams.txt" || reason="untrusted developer $team"
           fi;;
      esac
    fi
    [ -n "$reason" ] && kill -9 "$pid" 2>/dev/null && log "closed $app [$ident]: $reason"
  done
}

# ---------- NextDNS ----------
nextdns_forwarders() { # -> args that send every YouTube domain to a dead DoH endpoint
  local d
  for d in $(grep -v '^#' "$BASE/youtube-domains.txt" 2>/dev/null); do
    printf -- '-forwarder\n%s=https://127.0.0.1:9/dns-query\n' "$d"
  done
}
enforce_nextdns() {
  [ -x "$NEXTDNS" ] || return
  local cfg missing=0 d; cfg=$("$NEXTDNS" config 2>/dev/null)
  for d in $(grep -v '^#' "$BASE/youtube-domains.txt" 2>/dev/null); do
    grep -qF "forwarder $d.=" <<<"$cfg" || grep -qF "forwarder $d=" <<<"$cfg" || missing=1
  done
  if [ $missing = 1 ]; then
    local id; id=$("$NEXTDNS" config 2>/dev/null | awk '/^(profile|config) /{print $2; exit}' | sed 's/.*=//')
    if [ -n "$id" ]; then
      local args=(); while IFS= read -r a; do args+=("$a"); done < <(nextdns_forwarders)
      "$NEXTDNS" install -profile "$id" -report-client-info -auto-activate "${args[@]}" >/dev/null 2>&1 && log "nextdns YouTube forwarders re-applied"
    fi
  fi
  "$NEXTDNS" status 2>/dev/null | grep -qi running || { "$NEXTDNS" start >/dev/null 2>&1; log "nextdns started"; }
  local need=0 svc
  while IFS= read -r svc; do
    case "$svc" in An\ asterisk*|\**) continue;; esac
    networksetup -getdnsservers "$svc" 2>/dev/null | grep -qx '127.0.0.1' || need=1
  done < <(networksetup -listallnetworkservices 2>/dev/null)
  [ $need = 1 ] && { "$NEXTDNS" activate >/dev/null 2>&1; log "nextdns re-activated"; }
}

# ---------- requests from the HappyBrowsing app ----------
relocked() { # runs once whenever we go back to locked
  ( "$BASE/trust-scan.sh" >> "$LOG" 2>&1 ) &   # trust apps installed during the unlock
}
process_inbox() {
  local now; now=$(date +%s)
  if [ -e "$INBOX/relock" ]; then
    rm -f "$INBOX"/*
    if [ "$STATE" != locked ]; then local was=$STATE; STATE=locked; UNLOCK_AT=0; RELOCK_AT=0; save_state; log "relock by button"; [ "$was" = unlocked ] && relocked; fi
  fi
  if [ -e "$INBOX/cancel" ]; then
    rm -f "$INBOX/cancel" "$INBOX/unlock"
    if [ "$STATE" = pending ]; then STATE=locked; UNLOCK_AT=0; save_state; log "unlock cancelled"; fi
  fi
  if [ -e "$INBOX/unlock" ]; then
    rm -f "$INBOX/unlock"
    if [ "$STATE" = locked ]; then STATE=pending; UNLOCK_AT=$((now + UNLOCK_DELAY)); save_state; log "unlock requested"; fi
  fi
  rm -f "$INBOX"/* 2>/dev/null
  if [ "$STATE" = pending ] && [ "$now" -ge "$UNLOCK_AT" ]; then
    STATE=unlocked; RELOCK_AT=$((now + ADMIN_WINDOW)); save_state; log "unlocked"
  fi
  if [ "$STATE" = unlocked ] && [ "$now" -ge "$RELOCK_AT" ]; then
    STATE=locked; UNLOCK_AT=0; RELOCK_AT=0; save_state; log "auto relock"; relocked
  fi
}

write_status() {
  local now msg; now=$(date +%s)
  case "$STATE" in
    locked)   msg="LOCKED";;
    pending)  msg="UNLOCK PENDING — admin rights in $(( (UNLOCK_AT-now+59)/60 )) min";;
    unlocked) msg="UNLOCKED (admin) — auto re-lock in $(( (RELOCK_AT-now+59)/60 )) min";;
  esac
  [ "$ARMED" = 1 ] || msg="$msg (not armed yet)"
  [ "$CHROME_OK" = 1 ] || msg="$msg — Chrome closed: install the normal HappyBrowsing – Chrome profile"
  echo "$msg" > "$STATUS.tmp"; mv -f "$STATUS.tmp" "$STATUS"; chmod 644 "$STATUS"
}

# ---------- main loop ----------
mkdir -p "$INBOX"; chmod 1777 "$INBOX"
log "enforcer 1.5.1 started"
i=0
while true; do
  load
  process_inbox
  enforce_admins
  enforce_auth_files
  enforce_hosts
  cleanup_resolvers
  check_chrome
  guard_apps
  [ $((i % 6)) = 0 ] && enforce_nextdns
  [ $((i % 720)) = 0 ] && [ $i -gt 0 ] && : > "$SIGCACHE"
  write_status
  i=$((i + 1))
  sleep 5
done
