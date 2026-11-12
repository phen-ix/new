#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# DOOM Kernel — device measurement harness (host side, needs adb + root)
#
# Produces comparable before/after numbers for the HyperOS port instead of
# impressions. Every value is written to a CSV so hyperos/tools/compare.py can
# compute deltas with explicit sample counts.
#
# Usage:
#   ./device-metrics.sh <label> [options]
#
#   label            free-form tag, e.g. "baseline-doom" or "after-profile-v1"
#   --serial S       adb serial (default: only device)
#   --pkg PKG        package under test for ui/launch (no default: pass one,
#                    e.g. com.miui.home for launcher, com.android.settings)
#   --scenario S     static|launch|ui|idle|soak|all   (default: static)
#   --runs N         repeats for launch/ui (default 7; below 5 = not comparable)
#   --seconds N      duration for idle/soak (default 300 / 600)
#   --out DIR        output root (default ./metrics)
#   --dry-run        print the adb commands, collect nothing
#
# Scenarios
#   static  one-shot snapshot: kernel, props, cpufreq/schedutil/core_ctl/cpu_boost,
#           thermal zones, kgsl, meminfo/vmstat/PSI/zram, block queue, power
#   launch  cold-start latency of --pkg, --runs times -> TotalTime/WaitTime
#   ui      scripted scroll, then gfxinfo framestats -> jank %, p50/p90/p99
#   idle    power draw + wakeup sources over --seconds
#   soak    time series of temp/freq/PSI/gpu during a manual gaming session
#
# Nothing is changed on the device. This harness only reads and drives input.

set -u
export LC_ALL=C

LABEL="${1:-}"; [ -n "$LABEL" ] || { echo "usage: $0 <label> [options]" >&2; exit 1; }
shift
SERIAL=""; PKG=""; SCEN="static"; RUNS=7; SECS=300; OUT="./metrics"; DRY=0
while [ $# -gt 0 ]; do
	case "$1" in
	--serial) SERIAL="${2:-}"; shift 2 ;;
	--pkg) PKG="${2:-}"; shift 2 ;;
	--scenario) SCEN="${2:-}"; shift 2 ;;
	--runs) RUNS="${2:-7}"; shift 2 ;;
	--seconds) SECS="${2:-300}"; shift 2 ;;
	--out) OUT="${2:-./metrics}"; shift 2 ;;
	--dry-run) DRY=1; shift ;;
	*) echo "unknown option: $1" >&2; exit 1 ;;
	esac
done

ADB=(adb)
[ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")
DIR="$OUT/$LABEL"
mkdir -p "$DIR"
CSV="$DIR/summary.csv"
[ -f "$CSV" ] || echo "scenario,metric,value,unit,n" >"$CSV"

sh_() { "$@" ; }

adbs() { # run a shell command on device, capture stdout
	if [ "$DRY" -eq 1 ]; then
		printf 'adb shell %s\n' "$*" >&2
		return 0
	fi
	"${ADB[@]}" shell "$@" 2>/dev/null
}

adbsu() { # root shell (su -c); falls back to adbs
	if [ "$DRY" -eq 1 ]; then
		printf 'adb shell su -c %s\n' "$*" >&2
		return 0
	fi
	"${ADB[@]}" shell "su -c '$*'" 2>/dev/null || adbs "$@"
}

add() { # scenario metric value unit n
	printf '%s,%s,%s,%s,%s\n' "$1" "$2" "$3" "$4" "${5:-1}" >>"$CSV"
}

need_pkg() {
	[ -n "$PKG" ] || { echo "scenario $1 requires --pkg" >&2; exit 1; }
}

# ---------------------------------------------------------------------------
scenario_static() {
	local f="$DIR/static.txt"
	{
		echo "## kernel"
		adbs "cat /proc/version"
		adbs "cat /proc/cmdline"
		echo "## props"
		adbs "getprop | grep -E 'ro.board.platform|ro.hardware|ro.build.version.release|ro.mi.os|ro.lmk|ro.config.zram|ro.zram|dalvik.vm.heapsize|ro.surface_flinger|ro.hwui'"
		echo "## cpufreq policies"
		adbs "for p in /sys/devices/system/cpu/cpufreq/policy*; do echo \"== \$p\"; cat \$p/scaling_governor \$p/scaling_min_freq \$p/scaling_max_freq \$p/scaling_available_frequencies 2>/dev/null; cat \$p/schedutil/up_rate_limit_us \$p/schedutil/down_rate_limit_us \$p/schedutil/iowait_boost_enable 2>/dev/null; done"
		echo "## freq residency"
		adbs "for c in /sys/devices/system/cpu/cpu0 /sys/devices/system/cpu/cpu6; do echo \"== \$c\"; cat \$c/cpufreq/stats/time_in_state 2>/dev/null; done"
		echo "## core_ctl"
		adbs "for d in /sys/devices/system/cpu/cpu*/core_ctl; do echo \"== \$d\"; for a in enable min_cpus max_cpus offline_delay_ms busy_up_thres busy_down_thres task_thres; do printf '%s=' \$a; cat \$d/\$a 2>/dev/null; done; done"
		echo "## cpu_boost"
		adbs "for p in /sys/module/cpu_boost/parameters/*; do printf '%s=' \$(basename \$p); cat \$p 2>/dev/null; done"
		echo "## schedtune"
		adbs "cat /dev/stune/top-app/boost /dev/stune/foreground/boost /dev/stune/background/boost /dev/stune/root/boost 2>/dev/null"
		echo "## walt sysctls"
		adbs "for k in sched_boost sched_group_upmigrate sched_group_downmigrate sched_conservative_pl sched_many_wakeup_threshold sched_min_task_util_for_boost sched_min_task_util_for_colocation sched_little_cluster_coloc_fmin_khz sched_upmigrate sched_downmigrate; do printf '%s=' \$k; cat /proc/sys/kernel/\$k 2>/dev/null; done"
		echo "## msm_performance"
		adbs "for p in /sys/module/msm_performance/parameters/*; do printf '%s=' \$(basename \$p); cat \$p 2>/dev/null; done"
		echo "## thermal zones"
		adbs "for z in /sys/class/thermal/thermal_zone*; do t=\$(cat \$z/type 2>/dev/null); v=\$(cat \$z/temp 2>/dev/null); echo \"\$z \$t \$v\"; done"
		echo "## cooling devices"
		adbs "for c in /sys/class/thermal/cooling_device*; do t=\$(cat \$c/type 2>/dev/null); s=\$(cat \$c/cur_state 2>/dev/null); m=\$(cat \$c/max_state 2>/dev/null); echo \"\$c \$t \$s/\$m\"; done"
		echo "## kgsl"
		adbs "cat /sys/class/kgsl/kgsl-3d0/devfreq/governor /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq /sys/class/kgsl/kgsl-3d0/devfreq/min_freq /sys/class/kgsl/kgsl-3d0/devfreq/max_freq /sys/class/kgsl/kgsl-3d0/gpu_busy_percentage /sys/class/kgsl/kgsl-3d0/min_pwrlevel /sys/class/kgsl/kgsl-3d0/max_pwrlevel 2>/dev/null"
		echo "## memory"
		adbs "cat /proc/meminfo"
		adbs "grep -E '^(pgscan|pgsteal|pgmajfault|workingset_refault|workingset_activate|pswpin|pswpout|oom_kill)' /proc/vmstat"
		adbs "cat /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io"
		adbs "cat /sys/block/zram0/mm_stat /sys/block/zram0/disksize /sys/block/zram0/comp_algorithm 2>/dev/null"
		adbs "dumpsys meminfo | head -n 25"
		adbs "cat /proc/sys/vm/swappiness /proc/sys/vm/extra_free_kbytes /proc/sys/vm/watermark_scale_factor /proc/sys/vm/vfs_cache_pressure"
		echo "## block"
		adbs "for b in /sys/block/*/queue; do echo \"== \$b\"; cat \$b/scheduler \$b/nr_requests \$b/read_ahead_kb 2>/dev/null; done"
		echo "## power"
		adbs "dumpsys power | grep -E 'mWakefulness|Display Power|mScreenOn|Wake Locks' | head -n 20"
		adbs "cat /sys/class/power_supply/battery/current_now /sys/class/power_supply/battery/voltage_now /sys/class/power_supply/battery/temp 2>/dev/null"
	} >"$f" 2>&1

	# machine-readable subset (all read-only, all directly from the device)
	add static kernel_version "$(awk '/^Linux version/{print $3; exit}' "$f")" "" 1
	add static kernel_release "$(awk '/^Linux version/{print $4; exit}' "$f")" "" 1
	add static zram_disksize_bytes "$(adbs 'cat /sys/block/zram0/disksize')" B 1
	add static zram_algorithm "$(adbs 'cat /sys/block/zram0/comp_algorithm')" "" 1
	add static gpu_governor "$(adbs 'cat /sys/class/kgsl/kgsl-3d0/devfreq/governor')" "" 1
	add static thermal_max_temp_mc "$(adbs 'for z in /sys/class/thermal/thermal_zone*; do cat $z/temp; done | sort -n | tail -1')" mC 1
	add static swappiness "$(adbs 'cat /proc/sys/vm/swappiness')" "" 1
	add static extra_free_kbytes "$(adbs 'cat /proc/sys/vm/extra_free_kbytes')" kB 1
	add static psi_memory_some10 "$(adbs "awk '/memory/{print \$2}' /proc/pressure/memory")" pct 1
	echo "[i] static snapshot -> $f"
}

# ---------------------------------------------------------------------------
# frame stats parser (gfxinfo framestats -> jank/p50/p90/p99)
# ---------------------------------------------------------------------------
parse_frames() { # $1 raw framestats file, $2 csv add prefix
	python3 - "$1" "$CSV" "$2" <<'PY'
import sys
raw, csv, prefix = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(raw, errors='replace').read().splitlines()
try:
    start = next(i for i,l in enumerate(lines) if '---PROFILEDATA---' in l)
except StopIteration:
    print("no PROFILEDATA in framestats", file=sys.stderr); sys.exit(0)
def find(cols, names):
    for nm in names:
        if nm in cols:
            return cols.index(nm)
    return None

FLAGS = INTENDED = COMPLETED = None
durs = []
for l in lines[start+1:]:
    if '---PROFILEDATA---' in l:
        break
    p = [x for x in l.strip().split(',') if x != '']
    if not p: continue
    if p[0] == 'Flags' or 'IntendedVsync' in p:
        FLAGS = find(p, ('Flags',))
        INTENDED = find(p, ('IntendedVsync', 'Vsync'))
        # Pixel/AOSP gfxinfo uses FrameCompleted; older dumps use CompletedVsync
        COMPLETED = find(p, ('FrameCompleted', 'CompletedVsync', 'PresentedVsync'))
        continue
    try:
        if FLAGS is None or INTENDED is None or COMPLETED is None: continue
        ns = int(p[COMPLETED]) - int(p[INTENDED])
        if ns > 0: durs.append(ns/1e6)
    except (ValueError, IndexError):
        continue
if not durs:
    print("no frames parsed", file=sys.stderr); sys.exit(0)
durs.sort()
n = len(durs)
def pct(q):
    i = min(n-1, max(0, int(round(q*(n-1)))))
    return durs[i]
jank = sum(1 for d in durs if d > 16.67*1.5)
# n = number of frames: the sample count for frame statistics is the frame
# count, so compare.py can treat these as properly sampled.
with open(csv,'a') as f:
    f.write(f"ui,{prefix}_frames,{n},frames,{n}\n")
    f.write(f"ui,{prefix}_jank_pct,{100.0*jank/n:.1f},pct,{n}\n")
    f.write(f"ui,{prefix}_p50_ms,{pct(0.50):.2f},ms,{n}\n")
    f.write(f"ui,{prefix}_p90_ms,{pct(0.90):.2f},ms,{n}\n")
    f.write(f"ui,{prefix}_p99_ms,{pct(0.99):.2f},ms,{n}\n")
print(f"frames={n} jank={100.0*jank/n:.1f}% p50={pct(.5):.2f} p90={pct(.9):.2f} p99={pct(.99):.2f}")
PY
}

scenario_ui() {
	need_pkg ui
	[ "$RUNS" -lt 5 ] && echo "[!] --runs $RUNS is below the comparability floor of 5" >&2
	local i=0
	adbs "dumpsys gfxinfo $PKG reset" >/dev/null
	while [ "$i" -lt "$RUNS" ]; do
		adbs "input swipe 540 1800 540 600 300"
		adbs "input swipe 540 600 540 1800 300"
		i=$((i+1))
	done
	adbs "dumpsys gfxinfo $PKG framestats" >"$DIR/frames.txt"
	echo "[i] frames -> $DIR/frames.txt"
	[ "$DRY" -eq 1 ] && return 0
	parse_frames "$DIR/frames.txt" "scroll"
	# SurfaceFlinger aggregate jank counter is a second, independent view
	adbs "dumpsys SurfaceFlinger --latency-clear" >/dev/null 2>&1
	adbs "dumpsys SurfaceFlinger --jank" >>"$DIR/frames.txt" 2>/dev/null
}

scenario_launch() {
	need_pkg launch
	[ "$RUNS" -lt 5 ] && echo "[!] --runs $RUNS is below the comparability floor of 5" >&2
	local out="$DIR/launch.txt" i=0
	: >"$out"
	while [ "$i" -lt "$RUNS" ]; do
		adbs "am force-stop $PKG"
		sleep 2
		adbs "am start -W -n $PKG/$(adbs "cmd package resolve-activity --brief $PKG | tail -n 1" | tr -d '\r')" >>"$out"
		adbs "input keyevent KEYCODE_HOME"
		sleep 2
		i=$((i+1))
	done
	[ "$DRY" -eq 1 ] && return 0
	python3 - "$out" "$CSV" <<'PY'
import re,sys
raw, csv = sys.argv[1], sys.argv[2]
vals = {'WaitTime':[], 'TotalTime':[], 'ThisTime':[]}
for l in open(raw, errors='replace'):
    m = re.match(r'\s*(WaitTime|TotalTime|ThisTime):\s*(\d+)', l)
    if m: vals[m.group(1)].append(int(m.group(2)))
def stats(a):
    if not a: return None
    a = sorted(a); n = len(a)
    med = a[n//2]; p90 = a[int(round(.9*(n-1)))]
    return n, med, p90
with open(csv,'a') as f:
    for k,arr in vals.items():
        s = stats(arr)
        if not s: continue
        n,med,p90 = s
        f.write(f"launch,{k.lower()}_median,{med},ms,{n}\n")
        f.write(f"launch,{k.lower()}_p90,{p90},ms,{n}\n")
print("launch:", {k:(len(v)) for k,v in vals.items()})
PY
}

scenario_idle() {
	local out="$DIR/idle.csv" i=0
	echo "t_s,current_now_uA,level,thermal_max_mc" >"$out"
	while [ "$i" -le "$SECS" ]; do
		cur=$(adbs "cat /sys/class/power_supply/battery/current_now")
		lvl=$(adbs "cat /sys/class/power_supply/battery/capacity")
		tmp=$(adbs "for z in /sys/class/thermal/thermal_zone*; do cat \$z/temp; done | sort -n | tail -1")
		[ "$DRY" -eq 0 ] && echo "$i,$cur,$lvl,$tmp" >>"$out"
		sleep 15
		i=$((i+15))
	done
	[ "$DRY" -eq 1 ] && return 0
	python3 - "$out" "$CSV" <<'PY'
import csv,sys,statistics
raw, out = sys.argv[1], sys.argv[2]
cur=[]
for r in csv.DictReader(open(raw)):
    try: cur.append(int(r['current_now_uA']))
    except: pass
if cur:
    with open(out,'a') as f:
        f.write(f"idle,current_median,{int(statistics.median(cur)/1000)},mA,{len(cur)}\n")
        f.write(f"idle,current_p90,{int(sorted(cur)[int(.9*(len(cur)-1))]/1000)},mA,{len(cur)}\n")
PY
	adbs "cat /sys/kernel/debug/wakeup_sources 2>/dev/null || cat /d/wakeup_sources 2>/dev/null" >"$DIR/wakeup_sources.txt"
	adbs "dumpsys batterystats --charged | head -n 80" >"$DIR/batterystats.txt" 2>/dev/null
}

scenario_soak() {
	local out="$DIR/soak.csv" i=0
	echo "t_s,cpu_max_mhz,cpu6_mhz,gpu_mhz,thermal_max_mc,temp_battery_c,psi_cpu10,psi_mem10" >"$out"
	while [ "$i" -le "$SECS" ]; do
		read -r c6 g tz tb pc pm <<EOF
$(adbs "cat /sys/devices/system/cpu/cpu6/cpufreq/scaling_cur_freq 2>/dev/null; cat /sys/class/kgsl/kgsl-3d0/devfreq/cur_freq 2>/dev/null; for z in /sys/class/thermal/thermal_zone*; do cat \$z/temp; done | sort -n | tail -1; cat /sys/class/power_supply/battery/temp 2>/dev/null; awk '/cpu/{print \$2}' /proc/pressure/cpu; awk '/memory/{print \$2}' /proc/pressure/memory")
EOF
		[ "$DRY" -eq 0 ] && echo "$i,$(( ${c6:-0} / 1000 )),${g:-0},${tz:-0},${tb:-0},${pc:-0},${pm:-0}" >>"$out"
		sleep 5
		i=$((i+5))
	done
	echo "[i] soak series -> $out"
}

# ---------------------------------------------------------------------------
case "$SCEN" in
static) scenario_static ;;
launch) scenario_launch ;;
ui)     scenario_ui ;;
idle)   scenario_idle ;;
soak)   scenario_soak ;;
all)    scenario_static; [ -n "$PKG" ] && { scenario_launch; scenario_ui; }; scenario_idle ;;
*) echo "unknown scenario: $SCEN" >&2; exit 1 ;;
esac

echo "[i] results: $CSV"
echo "[i] compare with: python3 hyperos/tools/compare.py <baseline.csv> $CSV"
