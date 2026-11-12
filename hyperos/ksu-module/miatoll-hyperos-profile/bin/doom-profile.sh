#!/system/bin/sh
# SPDX-License-Identifier: GPL-2.0
#
# DOOM HyperOS Port Profile engine
# ---------------------------------
# Applies / reverts a *declarative* list of kernel runtime knobs for a specific
# ROM build, with strict safety properties:
#
#   * never writes to a node that is missing, read-only, or outside the
#     declared bounds,
#   * refuses to apply a value whose evidence gate is PENDING unless the
#     operator explicitly passes --allow-pending,
#   * records every original value before the first write and reads the value
#     back after writing (a failed read-back is rolled back immediately),
#   * can always be reverted to the exact pre-profile state (persistent
#     backup under the state directory, survives reboot),
#   * is a no-op when the profile file has no READY entries.
#
# The engine never guesses. If a knob is not present on this device (e.g. the
# ROM's own DT does not create a core_ctl node) it is reported, not forced.
#
# Usage:
#   doom-profile.sh --audit                 read-only snapshot + gate report
#   doom-profile.sh --apply                 apply READY entries only
#   doom-profile.sh --apply --allow-pending apply READY + PENDING (explicit)
#   doom-profile.sh --status                state of the last run
#   doom-profile.sh --diff                  current values vs profile targets
#   doom-profile.sh --revert [--backup N]   restore recorded originals
#
# Options:
#   --profile FILE   profile file (default: alongside this script)
#   --state DIR      state/backup dir (default /data/adb/doom-profile)
#   --root DIR       prefix for node paths (testing / offline inspection)
#   --quiet          only warnings and errors
#
# Exit codes: 0 ok, 1 usage error, 2 some entries skipped/failed, 3 fatal.

set -u

PROG=$(basename "$0")
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROFILE_DEFAULT="$SCRIPT_DIR/../profiles/hyperos-os3.0.3-miatoll.conf"
STATE_DIR="/data/adb/doom-profile"
ROOT=""
PROFILE=""
MODE=""
ALLOW_PENDING=0
QUIET=0
BACKUP_ID=""

# --- output helpers ---------------------------------------------------------
say()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*"; }
warn() { printf 'WARN: %s\n' "$*" >&2; }
err()  { printf 'ERROR: %s\n' "$*" >&2; }

usage() {
	sed -n '2,40p' "$0" | sed -n 's/^#[ ]\{0,1\}//p'
	exit 1
}

# --- argument parsing -------------------------------------------------------
while [ $# -gt 0 ]; do
	case "$1" in
	--audit)         MODE="audit" ;;
	--apply)         MODE="apply" ;;
	--revert)        MODE="revert" ;;
	--status)        MODE="status" ;;
	--diff)          MODE="diff" ;;
	--allow-pending) ALLOW_PENDING=1 ;;
	--quiet)         QUIET=1 ;;
	--profile)       shift; PROFILE="${1:-}" ;;
	--state)         shift; STATE_DIR="${1:-}" ;;
	--root)          shift; ROOT="${1:-}" ;;
	--backup)        shift; BACKUP_ID="${1:-}" ;;
	-h|--help)       usage ;;
	*) err "unknown argument: $1"; usage ;;
	esac
	shift
done

[ -n "$MODE" ] || { err "no mode given"; usage; }
[ -n "$PROFILE" ] || PROFILE="$PROFILE_DEFAULT"

# Strip a trailing slash from ROOT so "$ROOT$node" stays well-formed.
ROOT="${ROOT%/}"

if [ ! -r "$PROFILE" ]; then
	err "profile not found or not readable: $PROFILE"
	exit 3
fi

# --- node helpers -----------------------------------------------------------
node_path() { printf '%s%s' "$ROOT" "$1"; }

node_read() { # $1 = node path -> prints value (trimmed), returns 1 if unreadable
	p=$(node_path "$1")
	[ -f "$p" ] || return 1
	[ -r "$p" ] || return 1
	tr -d '\r' <"$p" 2>/dev/null | head -n 2 | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

node_exists() { [ -e "$(node_path "$1")" ]; }

node_writable() { [ -w "$(node_path "$1")" ]; }

node_write() { # $1 = path, $2 = value ; returns 0 on success
	p=$(node_path "$1")
	printf '%s' "$2" >"$p" 2>/dev/null
}

in_range() { # $1 value, $2 min, $3 max -> 0 if within (or unbounded)
	v=$1; lo=$2; hi=$3
	case "$v" in ''|*[!0-9]*) return 0 ;; esac   # non-numeric: no numeric bound
	case "$lo" in ''|-) lo="" ;; esac
	case "$hi" in ''|-) hi="" ;; esac
	[ -n "$lo" ] && [ "$v" -lt "$lo" ] && return 1
	[ -n "$hi" ] && [ "$v" -gt "$hi" ] && return 1
	return 0
}

# --- state / locking --------------------------------------------------------
lock_acquire() {
	mkdir -p "$STATE_DIR" 2>/dev/null || return 1
	LOCK="$STATE_DIR/.lock"
	if ! mkdir "$LOCK" 2>/dev/null; then
		# stale lock older than 2 minutes is broken automatically
		if [ -d "$LOCK" ] && [ -n "$(find "$LOCK" -mmin +2 2>/dev/null)" ]; then
			rmdir "$LOCK" 2>/dev/null
			mkdir "$LOCK" 2>/dev/null || return 1
		else
			return 1
		fi
	fi
	echo $$ >"$LOCK/pid" 2>/dev/null
	return 0
}

lock_release() { [ -n "${LOCK:-}" ] && rm -rf "$LOCK" 2>/dev/null; }

# --- profile parsing --------------------------------------------------------
# Format, one entry per line, fields separated by whitespace:
#   <node> <value> <min> <max> <gate> <evidence-id>
# Blank lines and lines starting with '#' are ignored. Fields 3/4 may be '-'.
profile_field() { # $1 line, $2 index
	printf '%s' "$1" | awk -v i="$2" '{print $i}'
}

valid_line() {
	case "$1" in
	''|\#*) return 1 ;;
	esac
	set -- $1
	[ $# -ge 6 ] || return 1
	return 0
}

# --- audit ------------------------------------------------------------------
run_audit() {
	say "# DOOM HyperOS profile audit"
	say "# profile   : $PROFILE"
	say "# generated : $(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"
	say "# fields    : gate state node current target evidence"
	ready=0; pending=0; missing=0; ro=0
	while IFS= read -r line; do
		valid_line "$line" || continue
		set -- $line
		node=$1; target=$2; lo=$3; hi=$4; gate=$5; evid=$6
		if [ "$gate" = "READY" ]; then ready=$((ready + 1)); else pending=$((pending + 1)); fi
		if ! node_exists "$node"; then
			missing=$((missing + 1))
			printf '%s MISSING  %s - %s %s\n' "$gate" "$node" "$target" "$evid"
			continue
		fi
		if ! node_writable "$node"; then
			ro=$((ro + 1))
			printf '%s READONLY %s %s %s %s\n' "$gate" "$node" "$(node_read "$node")" "$target" "$evid"
			continue
		fi
		cur=$(node_read "$node")
		if [ "$target" = "-" ]; then
			# observe-only entry: recorded for the dossier, never written
			printf '%s %-9s %s %s %s %s\n' "$gate" OBSERVE "$node" "$cur" - "$6"
			continue
		fi
		if [ "$cur" = "$target" ]; then state=SAME; else state=DIFF; fi
		if ! in_range "$target" "$lo" "$hi"; then state=OUTOFRANGE; fi
		printf '%s %-9s %s %s %s %s\n' "$gate" "$state" "$node" "$cur" "$target" "$evid"
	done <"$PROFILE"
	say "# summary   : ready=$ready pending=$pending missing=$missing readonly=$ro"
	say "# NOTE: audit performs no writes."
}

# --- apply ------------------------------------------------------------------
backup_file_new() {
	BK="$STATE_DIR/backup-$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo run).tsv"
	: >"$BK"
	printf '%s\n' "$BK"
}

record_original() { # $1 path, $2 original value
	printf '%s\t%s\n' "$1" "$2" >>"$BK"
}

run_apply() {
	if [ "$ALLOW_PENDING" -eq 1 ]; then
		warn "--allow-pending set: entries without device evidence will be applied."
	elif ! grep -q '^[^#].*[[:space:]]READY[[:space:]]' "$PROFILE" 2>/dev/null; then
		say "no READY entries in profile -> nothing to apply (by design)."
		say "run --audit to snapshot current values; use --allow-pending to override."
		return 0
	fi

	lock_acquire || { err "another instance holds $STATE_DIR/.lock"; return 3; }
	trap 'lock_release' EXIT INT TERM

	BK=$(backup_file_new)
	SEEN="$STATE_DIR/.seen-$$"
	: >"$SEEN"
	applied=0; skipped=0; failed=0
	while IFS= read -r line; do
		valid_line "$line" || continue
		set -- $line
		node=$1; target=$2; lo=$3; hi=$4; gate=$5; evid=$6
		if [ "$gate" != "READY" ] && [ "$ALLOW_PENDING" -ne 1 ]; then
			skipped=$((skipped + 1)); continue
		fi
		if [ "$target" = "-" ]; then
			# observe-only entry: never write, never treat as a failure
			skipped=$((skipped + 1)); continue
		fi
		if ! in_range "$target" "$lo" "$hi"; then
			warn "target out of declared bounds, skipped: $node = $target [$lo..$hi] ($evid)"
			skipped=$((skipped + 1)); continue
		fi
		if grep -qx "$node" "${SEEN:-/dev/null}" 2>/dev/null; then
			warn "duplicate entry for $node, skipped ($evid)"
			skipped=$((skipped + 1)); continue
		fi
		printf '%s\n' "$node" >>"$SEEN"
		if ! node_exists "$node"; then
			warn "missing node, skipped: $node ($evid)"; skipped=$((skipped + 1)); continue
		fi
		if ! node_writable "$node"; then
			warn "not writable, skipped: $node ($evid)"; skipped=$((skipped + 1)); continue
		fi
		orig=$(node_read "$node")
		if [ "$orig" = "$target" ]; then
			say "already set: $node = $target"; skipped=$((skipped + 1)); continue
		fi
		record_original "$node" "$orig"
		if ! node_write "$node" "$target"; then
			warn "write failed: $node <- $target ($evid)"; failed=$((failed + 1)); continue
		fi
		now=$(node_read "$node")
		if [ "$now" != "$target" ]; then
			# Some nodes normalise the value (e.g. round to a supported
			# frequency). Accept only an exact match, else roll back.
			warn "read-back mismatch on $node: wrote '$target' got '$now' -> reverting"
			node_write "$node" "$orig"
			failed=$((failed + 1)); continue
		fi
		say "applied: $node : $orig -> $target"
		applied=$((applied + 1))
	done <"$PROFILE"

	printf '%s\n' "backup=$BK" >"$STATE_DIR/last-run"
	printf '%s\n' "applied=$applied" >>"$STATE_DIR/last-run"
	printf '%s\n' "skipped=$skipped" >>"$STATE_DIR/last-run"
	printf '%s\n' "failed=$failed" >>"$STATE_DIR/last-run"
	printf '%s\n' "when=$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)" >>"$STATE_DIR/last-run"

	rm -f "$SEEN"
	say "summary: applied=$applied skipped=$skipped failed=$failed backup=$BK"
	[ "$failed" -gt 0 ] && return 2
	return 0
}

# --- revert -----------------------------------------------------------------
run_revert() {
	if [ -n "$BACKUP_ID" ]; then
		BK="$STATE_DIR/backup-$BACKUP_ID.tsv"
	else
		BK=$(ls -1 "$STATE_DIR"/backup-*.tsv 2>/dev/null | sort | tail -n 1)
	fi
	if [ -z "${BK:-}" ] || [ ! -r "$BK" ]; then
		err "no backup found in $STATE_DIR (nothing to revert)"
		return 3
	fi
	lock_acquire || { err "another instance holds the lock"; return 3; }
	trap 'lock_release' EXIT INT TERM

	say "# reverting from $BK"
	restored=0; failed=0
	while IFS='	' read -r node orig; do
		[ -n "${node:-}" ] || continue
		if ! node_exists "$node"; then
			warn "node gone since backup: $node"; continue
		fi
		cur=$(node_read "$node")
		if [ "$cur" = "$orig" ]; then continue; fi
		if node_write "$node" "$orig"; then
			now=$(node_read "$node")
			if [ "$now" = "$orig" ]; then
				say "restored: $node : $cur -> $orig"
				restored=$((restored + 1))
			else
				warn "restore mismatch on $node: wanted '$orig' got '$now'"
				failed=$((failed + 1))
			fi
		else
			warn "restore write failed: $node"
			failed=$((failed + 1))
		fi
	done <"$BK"
	say "summary: restored=$restored failed=$failed"
	[ "$failed" -gt 0 ] && return 2
	return 0
}

# --- status / diff ----------------------------------------------------------
run_status() {
	if [ -r "$STATE_DIR/last-run" ]; then
		say "# last run"
		cat "$STATE_DIR/last-run"
	else
		say "no previous run recorded in $STATE_DIR"
	fi
	profile_summary=$(grep -c '^[^#]' "$PROFILE" 2>/dev/null || echo 0)
	say "# profile entries: $profile_summary"
	say "# profile file   : $PROFILE"
}

run_diff() {
	while IFS= read -r line; do
		valid_line "$line" || continue
		set -- $line
		node=$1; target=$2; gate=$5; evid=$6
		cur=$(node_read "$node") || cur="<missing>"
		if [ "$target" = "-" ]; then
			printf 'OBS   %-70s current=%-12s gate=%s %s\n' \
				"$node" "$cur" "$gate" "$evid"
			continue
		fi
		if [ "$cur" = "$target" ]; then
			printf 'SAME  %-70s %-12s gate=%s %s\n' "$node" "$cur" "$gate" "$evid"
		else
			printf 'DIFF  %-70s current=%-12s target=%-12s gate=%s %s\n' \
				"$node" "$cur" "$target" "$gate" "$evid"
		fi
	done <"$PROFILE"
}

# --- main -------------------------------------------------------------------
case "$MODE" in
audit)  run_audit ;;
apply)  run_apply ;;
revert) run_revert ;;
status) run_status ;;
diff)   run_diff ;;
esac
