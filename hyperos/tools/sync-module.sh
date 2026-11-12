#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0
#
# Copy the profile engine + profile data into the KSU module so the two never
# drift apart. Run this after editing hyperos/tools/doom-profile.sh or
# hyperos/profiles/*.conf.
set -eu
here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(CDPATH= cd -- "$here/../.." && pwd)
dest="$root/hyperos/ksu-module/miatoll-hyperos-profile/bin"

mkdir -p "$dest"
cp "$here/doom-profile.sh" "$dest/doom-profile.sh"
cp "$root/hyperos/profiles/hyperos-os3.0.3-miatoll.conf" "$dest/hyperos-os3.0.3-miatoll.conf"
chmod 0755 "$dest/doom-profile.sh"
echo "synced -> $dest"
ls -l "$dest"
