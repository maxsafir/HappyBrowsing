-- Lockbox app: request an unlock, cancel it, or re-lock.
on sh(c)
	try
		return do shell script c
	on error
		return ""
	end try
end sh

on run
	set s to sh("cat /Library/Lockbox/status.txt")
	if s is "" then set s to "Lockbox is not running."
	set delayMin to sh("awk -F= '/^UNLOCK_DELAY/{print int($2/60)}' /Library/Lockbox/config")
	set windowMin to sh("awk -F= '/^ADMIN_WINDOW/{print int($2/60)}' /Library/Lockbox/config")
	set reqLabel to "Request unlock (" & delayMin & " min wait)"
	if s starts with "LOCKED" then
		set btns to {"Close", reqLabel}
	else if s starts with "UNLOCK PENDING" then
		set btns to {"Close", "Cancel unlock request"}
	else if s starts with "UNLOCKED" then
		set btns to {"Close", "Re-lock now"}
	else
		set btns to {"Close"}
	end if
	set msg to "Status: " & s & return & return & "Unlocking makes your account an admin (to install apps or use sudo) after a " & delayMin & "-minute wait. The YouTube and Instagram blocks stay on. Admin ends when you press Re-lock, or automatically after " & windowMin & " minutes."
	set b to button returned of (display dialog msg buttons btns default button "Close" with title "Lockbox")
	if b is reqLabel then
		sh("touch /Library/Lockbox/inbox/unlock")
	else if b is "Cancel unlock request" then
		sh("touch /Library/Lockbox/inbox/cancel")
	else if b is "Re-lock now" then
		sh("touch /Library/Lockbox/inbox/relock")
	else
		return
	end if
	delay 7
	display dialog ("Status: " & sh("cat /Library/Lockbox/status.txt")) buttons {"OK"} default button "OK" with title "Lockbox"
end run
