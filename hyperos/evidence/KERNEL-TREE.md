# شجرة النواة الصحيحة — تصحيح الهوية
# The real DOOM kernel tree — identity correction

**الخلاصة:** نواة DOOM ليست في هذا المستودع (`phen-ix/new`)، بل في
**`phen-ix/kernel`**، الفرع **`arena/c39745c5-kernel`**.

---

## 1. الدليل (من GitHub API، بدون تخمين)

| المستودع | الفرع | الإصدار | `drivers/kernelsu` | BBR3 | ملاحظة |
|---|---|---|---|---|---|
| **`phen-ix/kernel`** | **`arena/c39745c5-kernel`** | **4.14.357** | ✅ | ✅ `CONFIG_TCP_CONG_BBR3=y` | **الأحدث — هذا هو المطلوب** |
| `phen-ix/kernel` | `arena/2197b6cf-kernel` | 4.14.357 | ✅ | ✅ | أقدم بالتزامين (`a5e2339d`) |
| `phen-ix/kernel` | `16` (الافتراضي) | 4.14.357 | ❌ | ❌ | القاعدة قبل عمل DOOM (2026-05-27) |
| `phen-ix/new` (**هذا المستودع**) | `arena/ec72f3eb-new` | 4.14.356-rc1 | ❌ | ❌ | قاعدة CAF نظيفة + KCAL فقط |
| `phen-ix/kernel_tree` | `15` | 4.14.336 | ✅ | ❌ | Ye Olde، ليس DOOM |
| `rbnj/kernel_xiaomi_miatoll` | `ksu`, `bpf` | 4.14.356 | ✅ | ❌ | المصدر الأعلى لهذا المستودع |
| `phen-ix/nexusbase`, `kernel_xiaomi_sm6250xx` | — | — | ❌ | ❌ | ليست DOOM |

رأس الفرع الصحيح:

```
914294cb 2026-10-31T16:44:21Z  miatoll: default CPUFreq to schedutil     ← HEAD
8694e53b 2026-10-31T15:46:19Z  branding: rebrand miatoll kernel as DOOM Kernel
a5e2339d 2026-10-31T12:58:18Z  package/docs: identify NoMount+xxKSU final pre-test build
6cebc22a 2026-10-31T12:58:18Z  haptics: refresh AW8624 from Kinesis 17
a31f69a2 2026-10-31T12:58:18Z  nomount: add maxsteeel/nomount v2.2.0 and Android 17 cgroup controller
61e62210 2026-10-31T12:58:17Z  ksu: refresh xxKSU to upstream 32714 (UAPI 6)
```

## 2. مطابقة المواصفات المطلوبة

`arch/arm64/configs/vendor/xiaomi/miatoll_defconfig` في `arena/c39745c5-kernel`:

| المواصفة | السطر | القيمة |
|---|---|---|
| Kernel base 4.14.357-openela | `Makefile` | `SUBLEVEL = 357` ✅ |
| Device miatoll | — | `miatoll_defconfig` ✅ |
| xxKSU | 745-750 | `CONFIG_KSU=y`, `KSU_TAMPER_SYSCALL_TABLE`, `KSU_LSM_SECURITY_HOOKS`, `KSU_FEATURE_SULOG`, `KSU_FEATURE_ADBROOT`, `KSU_HEURISTIC_IN_TREE_BUILD` ✅ |
| BBRv3 | 159 + 754 | `CONFIG_TCP_CONG_BBR=y` + `CONFIG_TCP_CONG_BBR3=y` ✅ |
| هوية DOOM | 2 | `CONFIG_LOCALVERSION="-DOOM"` ✅ |
| NoMount | 751 | `CONFIG_NOMOUNT=y` (maxsteeel/nomount v2.2.0) |
| EROFS | 672 | `CONFIG_EROFS_FS=y` ✅ |

## 3. ما يتغيّر في تقريري (`hyperos/REPORT.md`)

التقرير بُني على شجرة هذا المستودع. الحقائق التالية **لا تنطبق** على شجرة DOOM
ويجب اعتماد القيم الجديدة:

| البند في التقرير | ما قيل (شجرة `new`) | الصحيح في شجرة DOOM |
|---|---|---|
| §2.2 KernelSU | غير موجود | **موجود** (xxKSU 32714، UAPI 6) |
| §2.2 / §2.12 BBR | غير موجود، الافتراضي `cubic` | **BBRv1 + BBRv3 مُجمَّعان** (`TCP_CONG_BBR3=y`)، لكن **الافتراضي ما زال `cubic`** لأن `net/ipv4/Kconfig` يضع `default DEFAULT_CUBIC` ولا يوجد `CONFIG_DEFAULT_TCP_CONG` في الـ defconfig ⇒ BBRv3 متاح لكنه غير مُفعَّل تلقائيًا |
| §2.4 الحاكم الافتراضي | `performance` | **`schedutil`** (`CONFIG_CPU_FREQ_DEFAULT_GOV_SCHEDUTIL=y`، سطر 130) |
| §2.4 `up_rate_limit_us` | 500 µs | **1000 µs** (لا يوجد `SCHEDUTIL_UP_RATE_LIMIT` في defconfig DOOM ⇒ الافتراضي) |
| §3 C1 EROFS | مفقود | **موجود ومفعّل** ⇒ الفجوة C1 **محلولة** |
| §3 C2 TMPFS_XATTR | مفقود | ما زال غير مفعّل (لا يوجد `CONFIG_TMPFS_XATTR`؛ `TMPFS_POSIX_ACL=y` فقط) |
| `hyperos_compat.config` | EROFS مطلوب | **غير مطلوب** لشجرة DOOM؛ يبقى TMPFS_XATTR مرشّحًا فقط |

**ما لا يتغيّر:** كل مسارات العقد في ملف البروفايل (`schedutil/*`, `core_ctl`,
`cpu_boost`, `msm_performance`, `zram`, `kgsl`, sysctls) صالحة كما هي — نفس
سلالة CAF 4.14. لكن **القيم الحالية** يجب أن تُقرأ من الجهاز بـ `--audit`
قبل أي مقارنة، لأن افتراضيات شجرة DOOM مختلفة (1000 بدل 500 في
`up_rate_limit_us`، وحاكم افتراضي schedutil).

## 4. كيف تُنقل هذه الأعمال إلى الشجرة الصحيحة

الالتزام في هذا المستودع إضافي بالكامل (17 ملفًا جديدًا، لا تعديل على ملف قائم)،
لذلك يُطبَّق على أي شجرة نظيفة:

```bash
git clone https://github.com/phen-ix/kernel.git doom
cd doom && git checkout arena/c39745c5-kernel
git remote add newtree https://github.com/phen-ix/new.git
git fetch newtree arena/ec72f3eb-new
git cherry-pick <sha-of-the-hyperos-commit>
# (أو ببساطة: cp -r من شجرة new؛ لا تعارض لأنه لا ملف مشترك)
```

بعد النقل يُعاد فقط:
1. `miatoll_defconfig` في شجرة DOOM **لا يحتاج** أي من بنود `hyperos_compat.config` (EROFS موجود).
2. `--audit` على الجهاز لتثبيت القيم الحالية الفعلية.
3. تحديث عمود "القيمة الحالية" في `hyperos-os3.0.3-miatoll.conf` بما يقوله `--audit`.

## 5. ملاحظة توافق تحتاج فحصًا من الروم

`CONFIG_NOMOUNT=y` (maxsteeel/nomount) يعترض عمليات التركيب ويحوّل مساراتها.
مع روم بورت يعتمد على أقسام ديناميكية (`super.img`) وoverlays، هذا بند يجب
التحقق منه مقابل `fstab` الروم و`dmesg` عند الإقلاع (هل كل الأقسام مركّبة من
المسار المتوقع؟). يُضاف إلى E-15 في `EVIDENCE-REQUIRED.md`.

---

## 6. خلاصة الإجابة

> **الفرع: `arena/c39745c5-kernel` في مستودع `phen-ix/kernel`.**
> التزام `914294cb` (2026-10-31) — «miatoll: default CPUFreq to schedutil».
> البديل الأقدم: `arena/2197b6cf-kernel`. القاعدة: `16`.
