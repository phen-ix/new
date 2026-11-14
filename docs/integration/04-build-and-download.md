# Build and download DOOM Kernel for miatoll

## What a build produces

Exactly one deliverable, ready to flash:

```text
DOOM-Kernel-miatoll-<short-sha>.zip      AnyKernel3 flashable ZIP (recovery)
```

There is **one** build configuration. Kernel-level colour calibration (KCal) is
always compiled in; which colour-block owner is active on the device is chosen
**while flashing** (see *Colour control* below), so there is no second
"KCal-free" variant to pick between and no mismatched pair of downloads.

GitHub wraps everything uploaded through *workflow artifacts* in another ZIP, so
a flashable ZIP published that way arrives zipped twice. The workflow therefore
publishes the ZIP as a **release asset**, which is served as-is.

## Option A — download the newest build

Every successful push to the working branch publishes to one rolling release,
which holds **one asset: the newest flashable ZIP**.

- Release page: <https://github.com/phen-ix/new/releases/tag/ci-latest>
- Direct file: `https://github.com/phen-ix/new/releases/download/ci-latest/DOOM-Kernel-miatoll-<short-sha>.zip`

With GitHub CLI:

```bash
gh release view ci-latest --repo phen-ix/new
gh release download ci-latest --repo phen-ix/new --pattern '*.zip' --dir .
```

The release notes carry the exact source commit and the SHA-256 of the asset.
To verify:

```bash
sha256sum DOOM-Kernel-miatoll-<short-sha>.zip
```

The build is described in `.github/workflows/miatoll-kernel.yml`
(**DOOM Kernel — miatoll (Clang 22)**). A push to the working branch starts it
automatically; **Run workflow** starts it by hand. It fetches and verifies the
pinned toolchain, builds `vendor/xiaomi/miatoll_defconfig`, checks the required
features, audits compiler/linker commands, packages the ZIP and publishes it.
A newer push cancels an in-progress run through concurrency cancellation, so use
the run for the commit you actually want.

## Option B — build locally

Host packages: `bc bison flex libssl-dev libelf-dev cpio curl git xz-utils python3`.

```bash
scripts/fetch-llvm.sh        # pinned LLVM/Clang/LLD 22.1.8, checksum verified
scripts/build-miatoll.sh     # kernel + dtbs + modules under out/miatoll/
scripts/package-anykernel.sh # out/miatoll/anykernel/DOOM-Kernel-miatoll-<sha>.zip
```

Useful overrides:

```bash
OUT_DIR="$PWD/out/miatoll-fresh" ./scripts/build-miatoll.sh
```

Do not work around a compilation error by disabling a required feature.

## Inside the ZIP

```text
anykernel.sh                        installer (device check + flash-time choice)
Image                               ARM64 kernel (KCal compiled in)
dtb                                 cust-atoll-ab.dtb
dtbo.img                            4 overlays, page size 4096
tools/                              AnyKernel3 (pinned 41f04bd) + busybox/magiskboot
META-INF/                           recovery entry point
README.txt, PACKAGE_INFO.txt        build identity and instructions
```

The ZIP targets the unified **miatoll** devices (`curtana`, `joyeuse`,
`excalibur`, `gram`) using the device tree's boot layout: **A-only**, boot header
**v2**, page size **4096**, **DTB in boot**, **separate DTBO partition**. It
replaces the kernel and DTB inside the existing boot image, preserves the current
boot ramdisk, and flashes a matching `dtbo.img`. It does not flash a ROM,
recovery, vbmeta, or modem, and it does not install the optional `tcp_bic.ko` /
`tcp_htcp.ko` modules. NoMount kernel support is built in (protocol 23), but the
matching NoMount v2.3.0 userspace metamodule must be installed separately through
the KernelSU manager after boot.

## Colour control: the flash-time choice

AOSP ROMs hand LiveDisplay picture adjustment to the same DSPP PA/HSIC block that
KCal drives, and that block has a single writer: whichever side programs it last
wins. The installer therefore asks, before it unpacks the boot image:

| key | meaning |
| --- | --- |
| **VOL UP** | KCal **on** — KCal drives hue / saturation / value / contrast |
| **VOL DOWN** | KCal **off** — the ROM keeps the block, LiveDisplay behaves like stock |
| no key within 10 s | KCal **off** (the safe answer) |

Recoveries without `getevent`/`timeout` fall back to the default; create
`/sdcard/doom_kcal_on` before flashing to force KCal on in that case.

The answer is written into the boot image command line as `doom.kcal=0|1`. The
kernel reads it in `__setup()` before any display code runs, so it applies from
the first frame, persists across reboots, and is rewritten on every flash — a
reflash can never resurrect a stale value.

Check after booting:

```bash
su -c 'grep -o "doom.kcal=[01]" /proc/cmdline'
su -c 'dmesg | grep "KCAL: boot default"'
su -c 'cat /sys/devices/platform/kcal_ctrl.0/kcal_enable'
```

Switch at runtime without reflashing:

```bash
echo 1 > /sys/devices/platform/kcal_ctrl.0/kcal_enable   # KCal on
echo 0 > /sys/devices/platform/kcal_ctrl.0/kcal_enable   # ROM owns colour
```

The remaining nodes are `kcal` (`"R G B"` gains, 256 = neutral), `kcal_min`
(minimum gain, 20), `kcal_hue`, `kcal_sat`, `kcal_val` and `kcal_cont`. The
platform device registers as id 0, hence the `.0` suffix.

## Local raw outputs (not published)

`scripts/build-miatoll.sh` also leaves the raw, *non*-flashable outputs for
inspection; they are not uploaded by CI because the flashable ZIP is the only
deliverable:

```text
out/miatoll/artifacts/
  Image                        raw ARM64 kernel image
  cust-atoll-ab.dtb            device-tree blob
  *-atoll-ab-idp-overlay.dtbo  curtana/excalibur/gram/joyeuse overlays
  miatoll.config               the final .config
  BUILD_INFO.txt               commit, toolchain, feature inventory
  SHA256SUMS
out/miatoll/logs/              defconfig, build, config-validation, toolchain
```

Verify the local artifact set with `(cd out/miatoll/artifacts && sha256sum -c SHA256SUMS)`.

## Flash and limitations

Flash from a custom recovery (TWRP/OrangeFox/Lineage Recovery). Keep a known-good
`boot.img` and `dtbo.img` backup first. This is a testing build, not a
runtime-certified release; compilation and ZIP structure checks do not prove that
the device will boot or that Android 17 userspace will work correctly.
