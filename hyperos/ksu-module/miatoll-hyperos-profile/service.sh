#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# DOOM HyperOS profile — late_start service stage
#
# Waits for boot_completed (so the ROM's own PowerHAL / thermald / perf
# services have already written their values), then:
#   1. audits the profile nodes again  -> /data/adb/doom-profile/late-boot-audit.txt
#   2. applies only READY entries      -> nothing today, by design
#
# Toggle: create /data/adb/modules/miatoll_hyperos_profile/disable to skip, or
# set DOOM_PROFILE_ALLOW_PENDING=1 in /data/adb/doom-profile/env to let PENDING
# entries through while experimenting (they will be recorded in the backup).

MODDIR=${0%/*}
STATE=/data/adb/doom-profile
PROFILE="$MODDIR/bin/hyperos-os3.0.3-miatoll.conf"
ENGINE="$MODDIR/bin/doom-profile.sh"
mkdir -p "$STATE" 2>/dev/null

[ -f "/data/adb/modules/miatoll_hyperos_profile/disable" ] && exit 0
[ -r "$ENGINE" ] || exit 0

# wait for the ROM to finish booting (max 180 s), the nodes are meaningless before
i=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ]; do
	i=$((i + 3))
	[ "$i" -ge 180 ] && break
	sleep 3
done

# give the ROM's own tuners a moment to settle
sleep 20

sh "$ENGINE" --audit --profile "$PROFILE" --state "$STATE" --quiet \
	>"$STATE/late-boot-audit.txt" 2>&1

ALLOW=""
[ -r "$STATE/env" ] && ALLOW=$(sed -n 's/^DOOM_PROFILE_ALLOW_PENDING=1$/--allow-pending/p' "$STATE/env")

if [ -n "$ALLOW" ]; then
	sh "$ENGINE" --apply --allow-pending --profile "$PROFILE" --state "$STATE" \
		>>"$STATE/engine.log" 2>&1
else
	sh "$ENGINE" --apply --profile "$PROFILE" --state "$STATE" \
		>>"$STATE/engine.log" 2>&1
fi

exit 0
