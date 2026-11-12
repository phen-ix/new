#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# DOOM HyperOS profile — post-fs-data stage
#
# Runs before most Android services start, so this is the only point where the
# *pre-userspace* state of the profile nodes can be captured. That snapshot is
# exactly the evidence Phase D needs to tell whether the ROM's PowerHAL /
# thermal service is writing these nodes itself.
#
# It writes nothing to the kernel. Read-only by design.

MODDIR=${0%/*}
STATE=/data/adb/doom-profile
mkdir -p "$STATE" 2>/dev/null

# 1. snapshot before any userspace tuner gets a chance to touch anything
if [ -r "$MODDIR/bin/doom-profile.sh" ]; then
	sh "$MODDIR/bin/doom-profile.sh" --audit \
		--profile "$MODDIR/bin/hyperos-os3.0.3-miatoll.conf" \
		--state "$STATE" --quiet \
		>"$STATE/early-boot-audit.txt" 2>&1
fi

# 2. record what the ROM itself has already set, so comparisons are possible
{
	echo "## boot early snapshot $(date -u 2>/dev/null)"
	echo "-- cmdline"; cat /proc/cmdline 2>/dev/null
	echo "-- version"; cat /proc/version 2>/dev/null
	echo "-- props"
	getprop 2>/dev/null | grep -E "ro.build.version|ro.mi.os|ro.board.platform|ro.lmk|ro.config.zram|ro.hardware"
} >"$STATE/early-boot-env.txt" 2>&1

exit 0
