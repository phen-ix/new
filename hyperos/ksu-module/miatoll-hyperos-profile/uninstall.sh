#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# DOOM HyperOS profile — uninstall / disable path
#
# Restores every value this module ever wrote (from the newest backup), then
# keeps the backups on disk so nothing is lost if the restore was partial.

MODDIR=${0%/*}
STATE=/data/adb/doom-profile
ENGINE="$MODDIR/bin/doom-profile.sh"

if [ -r "$ENGINE" ] && [ -d "$STATE" ]; then
	sh "$ENGINE" --revert --state "$STATE" >>"$STATE/uninstall.log" 2>&1
fi

# A reboot also restores the kernel defaults for everything in this profile:
# none of the entries are persistent, they are runtime values only.
exit 0
