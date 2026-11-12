#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# DOOM Kernel — HyperOS ROM evidence collector (host side, Linux)
#
# Extracts exactly the facts the kernel analysis needs from the target ROM
# package:
#
#   HyperOS_Miatoll_20261107_@iputobject_OS3.0.3.0.VLCCNXM_15.zip
#   sha256 783ad4f7be1330483aedab39344921a1ca9df9d3ca519634352db0430a60264c
#
# It never modifies the archive; everything is written under --out.
#
# Usage:
#   ./rom-evidence.sh --zip FILE.zip [--out DIR] [--work DIR] [--keep] [--deep]
#
#   --deep   also try to mount/extract the dynamic partitions from
#            super.img.zst (needs ~8 GB free and lpunpack + erofs/ext4 tools).
#            Without --deep the script still answers the "what filesystem /
#            what props / what HAL" questions from the raw images by scanning
#            them, but the dossier is less complete.
#
# Tools, in order of preference (all optional, the script degrades):
#   python3 (required), unzip, sha256sum, zstd, lpunpack, simg2img,
#   magiskboot | unpackbootimg, cpio, dtc | mkdtboimg, debugfs | fsck.erofs,
#   file, strings, readelf (for vendor_boot-less 4.14 boot images: unused)
#
# Output tree (--out):
#   dossier/00-archive.txt              zip listing + hashes
#   dossier/01-boot.txt                 boot.img header, cmdline, dtb summary
#   dossier/02-ramdisk/                 unpacked ramdisk init scripts
#   dossier/03-dtbo.txt                 decoded dtbo overlays (thermal/core_ctl)
#   dossier/04-dynamic-partitions.txt   super.img layout, fs types, sizes
#   dossier/05-props.txt                system/vendor/product props of interest
#   dossier/06-power-thermal.txt        PowerHAL/ThermalHAL/perf services
#   dossier/07-init-services.txt       init rc services + actions of interest
#   dossier/08-filesystems.txt          fstab + mount policy
#   dossier/summary.md                  the answers, one line each
#
# Every line that could not be determined is written as "UNKNOWN: <reason>".
# The script never guesses.

set -u
export LC_ALL=C

ZIP=""
OUT="./hyperos-rom-dossier"
WORK=""
KEEP=0
DEEP=0

EXPECT_SHA256="783ad4f7be1330483aedab39344921a1ca9df9d3ca519634352db0430a60264c"

die() { printf 'FATAL: %s\n' "$*" >&2; exit 3; }
info() { printf '[i] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }

while [ $# -gt 0 ]; do
	case "$1" in
	--zip) ZIP="${2:-}"; shift 2 ;;
	--out) OUT="${2:-}"; shift 2 ;;
	--work) WORK="${2:-}"; shift 2 ;;
	--deep) DEEP=1; shift ;;
	--keep) KEEP=1; shift ;;
	-h|--help) sed -n '3,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
	*) die "unknown argument: $1" ;;
	esac
done

[ -n "$ZIP" ] || die "--zip is required"
[ -f "$ZIP" ] || die "no such file: $ZIP"
have python3 || die "python3 is required"
have unzip || die "unzip is required"

mkdir -p "$OUT" || die "cannot create $OUT"
D="$OUT/dossier"
mkdir -p "$D"
[ -n "$WORK" ] || WORK="$OUT/work"
mkdir -p "$WORK"

# ---------------------------------------------------------------------------
# 0. archive identity
# ---------------------------------------------------------------------------
info "hashing archive (3.5 GB takes a while)..."
SUM=$(sha256sum "$ZIP" | awk '{print $1}')
{
	echo "# archive"
	echo "path      : $ZIP"
	echo "bytes     : $(stat -c %s "$ZIP")"
	echo "sha256    : $SUM"
	echo "expected  : $EXPECT_SHA256"
	[ "$SUM" = "$EXPECT_SHA256" ] && echo "verdict   : MATCH (pixeldrain metadata)" \
		|| echo "verdict   : MISMATCH — do not use results, re-download the file"
	echo
	echo "# zip listing"
	unzip -l "$ZIP"
	echo
	echo "# zip integrity"
	unzip -t "$ZIP" 2>&1 | tail -n 3
} >"$D/00-archive.txt"
[ "$SUM" = "$EXPECT_SHA256" ] || warn "sha256 mismatch vs pixeldrain metadata — results are for a different file"

unzip -o -q "$ZIP" -d "$WORK/raw" || die "unzip failed"
ls -la "$WORK/raw" >"$D/00-archive-files.txt" 2>&1

# ---------------------------------------------------------------------------
# 1. boot.img
# ---------------------------------------------------------------------------
BOOT="$WORK/raw/boot.img"
BOOTD="$WORK/boot"
mkdir -p "$BOOTD"
: >"$D/01-boot.txt"

if [ -f "$BOOT" ]; then
	{
		echo "# boot.img"
		echo "bytes: $(stat -c %s "$BOOT")"
		echo "type : $(file -b "$BOOT" 2>/dev/null || echo UNKNOWN)"
		echo
	} >>"$D/01-boot.txt"

	if have magiskboot; then
		(cd "$BOOTD" && magiskboot unpack "$BOOT" >/dev/null 2>&1) \
			&& info "boot.img unpacked with magiskboot" \
			|| warn "magiskboot unpack failed"
		{
			echo "# magiskboot header"
			(cd "$BOOTD" && magiskboot cpio ramdisk.cpio "exists init.rc" 2>/dev/null)
			echo
			echo "# cmdline"
			(cd "$BOOTD" && magiskboot hexpatch --help >/dev/null 2>&1)
		} >>"$D/01-boot.txt" 2>&1
	elif have unpackbootimg; then
		(cd "$BOOTD" && unpackbootimg -i "$BOOT" >/dev/null 2>&1) \
			&& info "boot.img unpacked with unpackbootimg" \
			|| warn "unpackbootimg failed"
	else
		{
			echo "UNKNOWN: no magiskboot/unpackbootimg available."
			echo "Install one of them (magiskboot from Magisk, or AOSP unpackbootimg)"
			echo "to decode the header, cmdline and DTB of the ROM boot image."
		} >>"$D/01-boot.txt"
	fi

	# header fields are plain text in both AOSP and Qualcomm 4.14 headers
	{
		echo "# printable strings from the first 4 KiB (header/cmdline)"
		dd if="$BOOT" bs=4096 count=1 2>/dev/null | strings -n 6 | head -n 40
	} >>"$D/01-boot.txt"
else
	echo "UNKNOWN: archive contains no boot.img at top level" >>"$D/01-boot.txt"
fi

# DTB inside boot (atoll/miatoll may carry the DT here rather than in dtbo)
if [ -f "$BOOTD/dtb" ]; then
	python3 - "$BOOTD/dtb" "$D/01-boot-dtb.txt" <<'PY'
import sys, struct
data = open(sys.argv[1],'rb').read()
out = open(sys.argv[2],'w')
# FDT magic 0xd00dfeed, big endian
MAGIC = b'\xd0\x0d\xfe\xed'
idxs = []
i = 0
while True:
    j = data.find(MAGIC, i)
    if j < 0: break
    if j + 36 > len(data): break
    size = struct.unpack('>I', data[j+4:j+8])[0]
    if 0 < size < 4*1024*1024 and j + size <= len(data):
        idxs.append((j, size))
    i = j + 1
out.write("# FDT blobs found in boot dtb section: %d\n" % len(idxs))
for n,(off,size) in enumerate(idxs):
    blob = data[off:off+size]
    out.write("\n## fdt[%d] offset=0x%x size=%d\n" % (n, off, size))
    # crude scan of the strings block for model/compatible/qcom, keywords
    keys = (b'model', b'compatible', b'qcom,', b'thermal', b'core_ctl',
            b'gpu', b'cpufreq', b'msm_perf', b'miatoll', b'atoll', b'kgsl')
    lo = off
    while True:
        k = blob.find(b'qcom,', lo)
        if k < 0: break
        end = blob.find(b'\x00', k)
        s = blob[k:end].decode('ascii','replace')
        if len(s) < 90:
            out.write("  " + s + "\n")
        lo = k + 5
out.close()
PY
	info "boot DTB scanned -> $D/01-boot-dtb.txt"
fi

# ramdisk init scripts
RD=""
for cand in "$BOOTD/ramdisk.cpio" "$BOOTD/ramdisk"; do
	[ -f "$cand" ] && RD="$cand" && break
done
if [ -n "$RD" ] && have cpio; then
	mkdir -p "$D/02-ramdisk"
	TRY="$WORK/rd"
	mkdir -p "$TRY"
	# magiskboot already gunzipped; raw cpio may still be compressed
	(cd "$TRY" && cpio -idm --no-absolute-filenames <"$RD") >/dev/null 2>&1 \
		|| warn "cpio extraction failed (compression? try magiskboot cpio extract)"
	if [ -n "$(ls -A "$TRY" 2>/dev/null)" ]; then
		cp -a "$TRY"/. "$D/02-ramdisk"/ 2>/dev/null
		info "ramdisk extracted -> $D/02-ramdisk"
	fi
else
	echo "UNKNOWN: no ramdisk / cpio tool (this is normal for a 4.14 GKI-less boot: ramdisk may be inside boot.img only)" \
		>"$D/02-ramdisk-README.txt"
fi

# ---------------------------------------------------------------------------
# 2. dtbo.img  (thermal trips, core_ctl, GPU levels, cpufreq tables)
# ---------------------------------------------------------------------------
DTBO="$WORK/raw/dtbo.img"
{
	echo "# dtbo.img"
	if [ -f "$DTBO" ]; then
		echo "bytes: $(stat -c %s "$DTBO")"
		echo "type : $(file -b "$DTBO" 2>/dev/null || echo UNKNOWN)"
		echo
		echo "# keyword scan (overlay strings: thermal zones, core_ctl, kgsl, cpufreq)"
		strings -n 4 "$DTBO" | grep -E "thermal|core_ctl|kgsl|gpu|cpufreq|qcom,|miatoll|atoll|trip|temp" \
			| sort -u | head -n 400
		echo
		echo "# NOTE: strings only. For trip points and cooling maps you need"
		echo "#       'mkdtboimg dump' or dtc on the decoded overlays."
	else
		echo "UNKNOWN: no dtbo.img in archive"
	fi
} >"$D/03-dtbo.txt"

if [ -f "$DTBO" ] && have mkdtboimg; then
	mkdir -p "$WORK/dtbo"
	mkdtboimg dump --output-dir "$WORK/dtbo" "$DTBO" >/dev/null 2>&1 \
		&& ls -la "$WORK/dtbo" >"$D/03-dtbo-files.txt" 2>&1
fi

# ---------------------------------------------------------------------------
# 3. dynamic partitions (super.img.zst)
# ---------------------------------------------------------------------------
SUPERZ="$WORK/raw/super.img.zst"
SUP="$WORK/super.img"
: >"$D/04-dynamic-partitions.txt"
{
	echo "# super image"
	echo "compressed bytes: $([ -f "$SUPERZ" ] && stat -c %s "$SUPERZ" || echo missing)"
} >>"$D/04-dynamic-partitions.txt"

if [ -f "$SUPERZ" ]; then
	if have zstd; then
		info "decompressing super.img.zst (3.5 GB, needs ~4 GB free)..."
		zstd -d -q -f "$SUPERZ" -o "$SUP" \
			&& info "super.img = $(stat -c %s "$SUP") bytes" \
			|| warn "zstd decompress failed"
	else
		warn "zstd not installed — cannot inspect super.img"
	fi
fi

if [ -f "$SUP" ]; then
	LS="$WORK/lp"
	mkdir -p "$LS"
	if have lpunpack; then
		info "unpacking logical partitions (lpunpack)..."
		lpunpack --slot=0 "$SUP" "$LS" >/dev/null 2>&1 || lpunpack "$SUP" "$LS" >/dev/null 2>&1
		ls -la "$LS" >>"$D/04-dynamic-partitions.txt"
	else
		echo "UNKNOWN: lpunpack missing (android-tools / otatools)" >>"$D/04-dynamic-partitions.txt"
	fi
	{
		echo
		echo "# magic scan of super.img (first 64 MiB) for fs signatures"
		dd if="$SUP" bs=1M count=64 2>/dev/null | strings -n 8 \
			| grep -E "^(system|vendor|product|system_ext|odm)[ _]" | sort -u | head -30
	} >>"$D/04-dynamic-partitions.txt"
else
	echo "UNKNOWN: super.img not available" >>"$D/04-dynamic-partitions.txt"
fi

# ---------------------------------------------------------------------------
# 4/5. partition content: props, HAL services, init scripts, fstab
# ---------------------------------------------------------------------------
IMG_DIR=""
for c in "$WORK/lp" "$WORK/raw"; do
	[ -d "$c" ] && [ -n "$(ls -A "$c" 2>/dev/null)" ] && IMG_DIR="$c" && break
done

PROPS="$D/05-props.txt"
: >"$PROPS"

extract_partition() { # $1 image path, $2 dest dir
	local img="$1" dst="$2"
	mkdir -p "$dst"
	if have fsck.erofs; then
		fsck.erofs --extract="$dst" "$img" >/dev/null 2>&1 && return 0
	fi
	if have debugfs; then
		debugfs -R "rdump / $dst" "$img" >/dev/null 2>&1 && return 0
	fi
	if [ "$(id -u)" -eq 0 ]; then
		mkdir -p "$dst.mnt"
		mount -o loop,ro "$img" "$dst.mnt" 2>/dev/null \
			&& { cp -a "$dst.mnt"/. "$dst"/ 2>/dev/null; umount "$dst.mnt"; return 0; }
	fi
	return 1
}

if [ -n "$IMG_DIR" ]; then
	for img in "$IMG_DIR"/*.img; do
		[ -f "$img" ] || continue
		name=$(basename "$img" .img)
		# skip the super container itself and tiny slot images
		case "$name" in super) continue ;; esac
		est=$(stat -c %s "$img")
		[ "$est" -gt 104857600 ] || continue
		info "scanning $name.img ($(numfmt --to=iec "$est" 2>/dev/null || echo "$est B"))"
		# strings-based prop scan always works, extraction is a bonus
		{
			echo
			echo "## $name"
			echo "# filesystem magic: $(dd if="$img" bs=1024 skip=1 count=1 2>/dev/null | xxd -p -l 4 2>/dev/null || echo UNKNOWN)"
			strings -n 6 "$img" | grep -E "^(ro|persist|vendor|dalvik|debug)\.(build|product|vendor|system|hardware|board|miui|lmk|zram|hwui|sf|display|opengles|egl|cpu|sched)" \
				| sort -u | head -n 600
		} >>"$PROPS" 2>&1
		if [ "$DEEP" -eq 1 ]; then
			dest="$WORK/extract/$name"
			if extract_partition "$img" "$dest"; then
				info "extracted $name -> $dest"
			else
				warn "could not extract $name (install erofs-utils / e2fsprogs, or run as root)"
			fi
		fi
	done
fi

# If partitions were extracted, mine the interesting files
EX="$WORK/extract"
if [ -d "$EX" ]; then
	{
		echo "# power / thermal / performance services and configs"
		find "$EX" -type f \( -name "*.rc" -o -name "*.xml" -o -name "*.json" \
			-o -name "*.conf" -o -name "*.prop" \) 2>/dev/null \
			| grep -Ei "thermal|power|perf|lmk|zram|sched|cpu|gpu|boost|miui|hyperos|display|fps" \
			| sed "s|$EX/||" | sort | head -n 500
		echo
		echo "# HAL binaries present"
		find "$EX" -type f -path "*bin/hw*" 2>/dev/null | sed "s|$EX/||" | sort
		echo
		echo "# thermal-engine / mi_thermald style files"
		find "$EX" -type f 2>/dev/null | grep -Ei "thermal" | sed "s|$EX/||" | sort
	} >"$D/06-power-thermal.txt" 2>&1

	{
		echo "# init rc services of interest"
		find "$EX" -name "*.rc" -type f 2>/dev/null | while read -r f; do
			if grep -qiE "thermal|power|perf|lmk|zram|kgsl|msm_performance|schedtune|boost" "$f" 2>/dev/null; then
				echo
				echo "## ${f#"$EX"/}"
				grep -nE "^(service|on |class |    (write|setprop|chown|chmod|start|trigger))" "$f" \
					| grep -iE "thermal|power|perf|lmk|zram|kgsl|msm_perf|schedtune|boost|write /sys|write /proc" \
					| head -n 80
			fi
		done
	} >"$D/07-init-services.txt" 2>&1

	{
		echo "# fstab / first-stage mount config"
		find "$EX" -type f \( -name "fstab*" -o -name "*fstab*" \) 2>/dev/null | while read -r f; do
			echo
			echo "## ${f#"$EX"/}"
			cat "$f"
		done
		echo
		echo "# filesystem drivers required by the above fstab entries:"
		find "$EX" -type f -name "fstab*" -exec cat {} \; 2>/dev/null \
			| awk '{for(i=1;i<=NF;i++) if($i ~ /^(ext4|f2fs|erofs)$/) print $i}' | sort -u
	} >"$D/08-filesystems.txt" 2>&1
fi

# ---------------------------------------------------------------------------
# 5. summary of the answers the kernel analysis needs
# ---------------------------------------------------------------------------
SUMIMG="$D/summary.md"
{
	echo "# ROM evidence summary"
	echo
	echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
	echo "Archive  : $ZIP"
	echo "sha256   : $SUM"
	echo
	echo "| question | answer |"
	echo "|---|---|"
	answer() { printf '| %s | %s |\n' "$1" "$2"; }

	if [ -f "$D/08-filesystems.txt" ]; then
		fs=$(grep -E "^(ext4|f2fs|erofs)$" "$D/08-filesystems.txt" | sort -u | tr '\n' ' ')
	else
		fs=""
	fi
	[ -n "$fs" ] && answer "filesystems used by ROM" "\`$fs\`" \
		|| answer "filesystems used by ROM" "UNKNOWN (needs --deep + erofs-utils/e2fsprogs)"

	if [ -s "$PROPS" ]; then
		for key in ro.board.platform ro.hardware ro.product.device ro.build.version.release \
			ro.mi.os.version.name ro.mi.os.version.incremental ro.lmk.critical ro.lmk.medium \
			ro.config.zram ro.zram.size; do
			v=$(grep -m1 -E "^$key=" "$PROPS" 2>/dev/null | cut -d= -f2-)
			[ -n "$v" ] && answer "$key" "\`$v\`" || answer "$key" "not found in scan"
		done
	else
		answer "system props" "UNKNOWN (prop scan produced nothing)"
	fi

	if [ -f "$D/06-power-thermal.txt" ]; then
		hal=$(grep -c "bin/hw" "$D/06-power-thermal.txt" 2>/dev/null || echo 0)
		th=$(grep -ci "thermal" "$D/06-power-thermal.txt" 2>/dev/null || echo 0)
		answer "HAL binaries listed" "$hal entries"
		answer "thermal-related files" "$th entries"
	fi

	if [ -f "$D/03-dtbo.txt" ]; then
		n=$(grep -ci "thermal" "$D/03-dtbo.txt" 2>/dev/null || echo 0)
		answer "thermal strings in dtbo" "$n"
	fi

	echo
	echo "## What to send back"
	echo
	echo "Attach: 00-archive.txt 01-boot.txt 03-dtbo.txt 04-dynamic-partitions.txt"
	echo "        05-props.txt 06-power-thermal.txt 07-init-services.txt 08-filesystems.txt"
	echo "These are text and small; the raw images stay in $WORK."
} >"$SUMIMG"

if [ "$KEEP" -eq 0 ]; then
	info "raw images kept in $WORK (delete manually if not needed)"
fi

info "done: $D/summary.md"
cat "$SUMIMG"
